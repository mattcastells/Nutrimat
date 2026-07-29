import 'dart:async';

import '../../core/error/app_error.dart';
import '../../data/remote/cloud_backup_client.dart';
import '../repositories/auth_gateway.dart';

/// Estado del respaldo, para mostrarlo en Configuración.
sealed class BackupState {
  const BackupState();
}

/// No hay servidor configurado o no hay sesión: el respaldo no aplica.
class BackupUnavailable extends BackupState {
  const BackupUnavailable(this.reason);

  final String reason;
}

class BackupIdle extends BackupState {
  const BackupIdle(this.lastUpload);

  /// `null` si nunca se subió nada.
  final DateTime? lastUpload;
}

class BackupUploading extends BackupState {
  const BackupUploading();
}

class BackupFailed extends BackupState {
  const BackupFailed(this.error, this.lastUpload);

  final AppError error;
  final DateTime? lastUpload;
}

/// Sube el documento del usuario a la nube cuando algo cambia.
///
/// Dos decisiones que definen el comportamiento:
///
/// **Se agrupa antes de subir.** Sumar cuatro vasos de agua son cuatro
/// cambios en pocos segundos; subir el documento entero cuatro veces sería
/// gastar los datos de alguien al pedo. Se espera a que la mano se quede
/// quieta y se sube una sola vez.
///
/// **Un fallo no interrumpe nada.** Si no hay internet o el servidor no
/// contesta, el dato ya está guardado en el teléfono y el respaldo se reintenta
/// en el próximo cambio. La app nunca bloquea una comida por no poder
/// respaldarla.
class CloudBackupService {
  CloudBackupService({
    required CloudBackupClient client,
    required AuthGateway auth,
    required String Function() readDocument,
    this.debounce = const Duration(seconds: 5),
  }) : _client = client,
       _auth = auth,
       _readDocument = readDocument;

  final CloudBackupClient _client;
  final AuthGateway _auth;
  final String Function() _readDocument;

  /// Cuánto se espera desde el último cambio antes de subir.
  final Duration debounce;

  Timer? _timer;
  DateTime? _lastUpload;
  bool _uploading = false;

  /// Hasta que no se haya decidido qué hacer con el respaldo remoto, **no se
  /// sube nada**.
  ///
  /// Sin esta puerta pasa lo peor que puede pasar: reinstalás, entrás, la app
  /// crea un perfil vacío, ese cambio dispara el respaldo y el documento vacío
  /// pisa el bueno. El respaldo se convierte en el mecanismo que borra los
  /// datos que debía proteger.
  bool _canUpload = false;

  /// Habilita la subida. Lo llama [openAfterRestore] cuando ya resolvió si
  /// había algo que traer.
  bool get canUpload => _canUpload;

  /// Queda pendiente cuando llega un cambio mientras se está subiendo: hay que
  /// volver a subir al terminar, porque lo que se mandó ya quedó viejo.
  bool _dirty = false;

  final StreamController<BackupState> _states =
      StreamController<BackupState>.broadcast();

  Stream<BackupState> get states => _states.stream;

  BackupState _current = const BackupIdle(null);
  BackupState get state => _current;

  void _emit(BackupState next) {
    _current = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Trae el respaldo remoto **antes** de habilitar cualquier subida.
  ///
  /// Solo restaura si el teléfono está vacío, que es el caso de una
  /// reinstalación o un dispositivo nuevo. Si ya hay datos locales no toca
  /// nada: pisarlos sería el mismo error al revés.
  ///
  /// Pase lo que pase habilita la subida al terminar — si fallara la consulta
  /// y quedara cerrada para siempre, la app dejaría de respaldar en silencio.
  Future<bool> openAfterRestore({
    required bool localIsEmpty,
    required Future<void> Function(String documentJson) apply,
  }) async {
    if (_auth.currentAccount == null) return false;

    var restored = false;
    try {
      if (localIsEmpty) {
        final json = await _client.download(_auth.currentAccount!.id);
        if (json != null) {
          await apply(json);
          restored = true;
        }
      }
    } on AppError {
      // Sin conexión no se restaura, pero tampoco se sube: la puerta se abre
      // igual y el próximo cambio local manda lo que haya.
    } finally {
      _canUpload = true;
    }
    return restored;
  }

  /// Avisa que algo cambió. Barato de llamar: no sube nada por sí solo.
  void markDirty() {
    if (_auth.currentAccount == null || !_canUpload) return;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  /// Sube ahora, sin esperar. Se usa al cerrar sesión y desde el botón manual.
  Future<void> flush() async {
    final account = _auth.currentAccount;
    if (account == null || !_canUpload) return;
    if (_uploading) {
      _dirty = true;
      return;
    }

    _timer?.cancel();
    _uploading = true;
    _dirty = false;
    _emit(const BackupUploading());

    try {
      await _client.upload(
        userId: account.id,
        documentJson: _readDocument(),
      );
      _lastUpload = DateTime.now();
      _emit(BackupIdle(_lastUpload));
    } on AppError catch (error) {
      _emit(BackupFailed(error, _lastUpload));
    } finally {
      _uploading = false;
    }

    // Llegó otro cambio mientras subía: lo que se mandó ya está viejo.
    if (_dirty) await flush();
  }

  /// Trae el respaldo de la nube. Devuelve `null` si no hay ninguno.
  Future<String?> restore() async {
    final account = _auth.currentAccount;
    if (account == null) return null;
    return _client.download(account.id);
  }

  Future<CloudBackupInfo?> remoteInfo() async {
    final account = _auth.currentAccount;
    if (account == null) return null;
    return _client.info(account.id);
  }

  void dispose() {
    _timer?.cancel();
    _states.close();
  }
}
