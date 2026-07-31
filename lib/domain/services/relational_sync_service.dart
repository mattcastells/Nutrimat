import 'dart:async';

import '../../core/error/app_error.dart';
import '../../data/local/local_store.dart';
import '../../data/remote/relational_sync_client.dart';
import '../repositories/auth_gateway.dart';
import 'document_merge.dart';

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

/// Mantiene las tablas y el dispositivo al día, en los dos sentidos.
///
/// **Las tablas son la fuente de verdad de la cuenta**; el documento local es la
/// copia con la que trabaja este dispositivo, y el respaldo JSON quedó como red
/// de seguridad. Al entrar se trae lo que hay en las filas y se reconcilia con
/// lo local ([openAfterPull]); de ahí en más cada cambio se escribe en los dos
/// lados.
///
/// Antes era al revés —el documento mandaba y las filas eran una copia de solo
/// escritura— y así estuvo a propósito mientras se verificaba que las filas
/// coincidieran. Eso alcanzaba para un solo dispositivo y no alcanza para dos:
/// sin traer, la misma cuenta abierta en el teléfono y en el navegador diverge
/// desde el primer registro y no se vuelve a encontrar.
///
/// Que esto falle sigue sin romper nada: el dato ya está en el dispositivo y en
/// el respaldo JSON, y la reconciliación no puede quedarse con menos registros
/// de los que había.
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

  /// Trae las filas al entrar, las reconcilia con lo local y recién ahí
  /// habilita la escritura.
  ///
  /// **Acá es donde las tablas pasan a ser la fuente de verdad.** Antes solo se
  /// consultaban si el teléfono estaba vacío: en cuanto había algo local, la app
  /// no volvía a mirarlas nunca, y las filas eran un respaldo de solo escritura.
  /// Con eso la misma cuenta no se puede usar desde dos lados — un navegador que
  /// ya se visitó una vez tiene su propia copia en `localStorage`, así que desde
  /// la segunda visita la web y el teléfono divergen y no se vuelven a
  /// encontrar.
  ///
  /// Ahora se trae siempre y se reconcilia con [mergeDocuments], que es una
  /// unión por id donde gana el más reciente y **no puede quedar con menos
  /// registros que los que había**. Lo local que todavía no se subió sobrevive;
  /// lo que se cargó en otro dispositivo entra.
  ///
  /// Pase lo que pase se abre la puerta de escritura: dejarla cerrada por un
  /// fallo de red sería no volver a escribir nunca.
  Future<bool> openAfterPull({
    required Future<void> Function(Map<String, dynamic> document) apply,
  }) async {
    final account = _auth.currentAccount;
    if (account == null) return false;

    var traido = false;
    try {
      final remote = await _client.pull(userId: account.id, store: _store);
      if (remote != null) {
        final merged = mergeDocuments(
          local: _store.toDocument(),
          remote: remote,
        );
        await apply(merged);
        traido = true;
      }
    } on AppError {
      // Sin conexión no se trae, pero tampoco se bloquea la escritura ni se
      // toca lo local: un fallo de lectura no puede parecerse a "no había
      // nada".
    } finally {
      _canPush = true;
    }

    // Después de abrir la puerta, no antes: `markDirty` sale temprano mientras
    // `_canPush` sea false, así que llamarlo adentro del `try` no habría hecho
    // nada — y en silencio.
    //
    // Sube lo que quedó solo de este lado. Sin esto, un registro cargado sin
    // conexión se reconcilia bien en pantalla y nunca llega a las tablas: la
    // próxima vez volvería a estar solo de este lado.
    if (traido) markDirty();
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
