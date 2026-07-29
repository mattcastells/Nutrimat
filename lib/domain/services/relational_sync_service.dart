import 'dart:async';

import '../../core/error/app_error.dart';
import '../../data/local/local_store.dart';
import '../../data/remote/relational_sync_client.dart';
import '../repositories/auth_gateway.dart';

/// Estado de la persistencia relacional, para poder mirarla desde Ajustes.
sealed class SyncState {
  const SyncState();
}

class SyncIdle extends SyncState {
  const SyncIdle(this.lastPush, this.rows);

  final DateTime? lastPush;

  /// Cuántas filas se escribieron por tabla en la última subida.
  final Map<String, int> rows;

  int get totalRows => rows.values.fold(0, (acc, n) => acc + n);
}

class SyncRunning extends SyncState {
  const SyncRunning();
}

class SyncFailed extends SyncState {
  const SyncFailed(this.error, this.lastPush);

  final AppError error;
  final DateTime? lastPush;
}

/// Mantiene las tablas al día con lo que hay en el teléfono.
///
/// Convive con el respaldo JSON en vez de reemplazarlo, **a propósito**. Los
/// dos escriben: el documento sigue siendo la fuente de verdad de la app y las
/// filas se llenan en paralelo. Así, si esto falla, no puede romper nada de lo
/// que ya funcionaba — y si el documento se pierde, las filas están.
///
/// Cuando las filas estén verificadas contra varios días de uso real se da
/// vuelta la verdad: mandan las tablas y el documento queda como respaldo. Ese
/// paso es una línea acá, no una reescritura.
class RelationalSyncService {
  RelationalSyncService({
    required RelationalSyncClient client,
    required AuthGateway auth,
    required LocalStore store,
    this.debounce = const Duration(seconds: 8),
  }) : _client = client,
       _auth = auth,
       _store = store;

  final RelationalSyncClient _client;
  final AuthGateway _auth;
  final LocalStore _store;

  /// Un poco más largo que el del respaldo: escribir filas es más caro que
  /// subir un archivo, y no hay apuro porque el documento ya salió.
  final Duration debounce;

  Timer? _timer;
  bool _running = false;
  bool _dirty = false;
  DateTime? _lastPush;
  Map<String, int> _lastRows = const <String, int>{};

  /// Misma puerta que el respaldo: hasta no haber decidido qué hacer con lo
  /// remoto no se escribe nada. Sin esto, un teléfono recién instalado podría
  /// empezar a escribir filas vacías antes de traerse lo que había.
  bool _canPush = false;
  bool get canPush => _canPush;

  final StreamController<SyncState> _states =
      StreamController<SyncState>.broadcast();
  Stream<SyncState> get states => _states.stream;

  SyncState _current = const SyncIdle(null, <String, int>{});
  SyncState get state => _current;

  void _emit(SyncState next) {
    _current = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Decide qué hacer al entrar y recién ahí habilita la escritura.
  ///
  /// Si el teléfono está vacío y la base tiene filas, se traen. Es el caso de
  /// reinstalar o cambiar de dispositivo, y es lo que convierte a las tablas
  /// en persistencia de verdad y no en una copia de solo escritura.
  ///
  /// Con datos locales no se toca nada: pisarlos sería el mismo error al
  /// revés. Pase lo que pase se abre la puerta, porque dejarla cerrada por un
  /// fallo de red sería no volver a escribir nunca.
  Future<bool> openAfterPull({
    required bool localIsEmpty,
    required Future<void> Function(Map<String, dynamic> document) apply,
  }) async {
    final account = _auth.currentAccount;
    if (account == null) return false;

    var traido = false;
    try {
      if (localIsEmpty) {
        final document = await _client.pull(
          userId: account.id,
          store: _store,
        );
        if (document != null) {
          await apply(document);
          traido = true;
        }
      }
    } on AppError {
      // Sin conexión no se trae, pero tampoco se bloquea la escritura.
    } finally {
      _canPush = true;
    }
    return traido;
  }

  /// Avisa que algo cambió. Barato: no escribe nada por sí solo.
  void markDirty() {
    if (_auth.currentAccount == null || !_canPush) return;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(push()));
  }

  /// Escribe ahora. Se usa al cerrar sesión y desde el botón manual.
  Future<void> push() async {
    final account = _auth.currentAccount;
    if (account == null || !_canPush) return;
    if (_running) {
      _dirty = true;
      return;
    }

    // Un teléfono sin nada cargado no tiene qué escribir. Mismo criterio que
    // el respaldo: no puede convertirse en el mecanismo que vacía la base.
    if (!_store.hasUserData) return;

    _timer?.cancel();
    _running = true;
    _dirty = false;
    _emit(const SyncRunning());

    try {
      _lastRows = await _client.push(userId: account.id, store: _store);
      _lastPush = DateTime.now();
      _emit(SyncIdle(_lastPush, _lastRows));
    } on AppError catch (error) {
      // Que falle no rompe nada: el dato ya está en el teléfono y en el
      // respaldo JSON. Se reintenta con el próximo cambio.
      _emit(SyncFailed(error, _lastPush));
    } finally {
      _running = false;
    }

    if (_dirty) await push();
  }

  /// Cuántas filas hay del lado del servidor, por tabla.
  Future<Map<String, int>> remoteCounts() async {
    final account = _auth.currentAccount;
    if (account == null) return const <String, int>{};
    return _client.counts(account.id);
  }

  void dispose() {
    _timer?.cancel();
    _states.close();
  }
}
