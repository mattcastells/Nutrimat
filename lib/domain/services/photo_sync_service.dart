import 'dart:io';

import '../../core/error/app_error.dart';
import '../../data/remote/photo_storage_client.dart';
import '../repositories/auth_gateway.dart';

/// Sube al bucket las fotos que la app guardó en el teléfono y devuelve la
/// ruta remota, que es lo que queda en `photo_path`.
///
/// El punto es que `photo_path` termine siendo **siempre** una ruta del bucket
/// y no una ruta de archivo del teléfono. Un `/data/user/0/.../cache/foto.jpg`
/// guardado en el respaldo apunta a un archivo que en otro teléfono no existe:
/// la foto se vería hoy y desaparecería al restaurar, que es justo lo que se
/// quiere evitar.
class PhotoSyncService {
  const PhotoSyncService({
    required PhotoStorageClient client,
    required AuthGateway auth,
  }) : _client = client,
       _auth = auth;

  final PhotoStorageClient _client;
  final AuthGateway _auth;

  /// Una ruta del bucket es `{uuid}/{uuid}.jpg`: dos segmentos y nada más. Lo
  /// que llega de la cámara es una ruta absoluta del sistema de archivos.
  static bool isRemotePath(String path) {
    if (path.startsWith('/') || path.contains(':\\')) return false;
    return path.split('/').length == 2;
  }

  /// Sube la foto si hace falta y devuelve la ruta a guardar.
  ///
  /// Devuelve la ruta original cuando no hay nada que hacer: sin sesión, sin
  /// archivo, o porque ya está en el bucket. Nunca lanza — que una foto no
  /// suba no puede impedir que se registre la comida.
  Future<String?> ensureUploaded({
    required PhotoBucket bucket,
    required String recordId,
    required String? localPath,
    // Al guardar una comida, que la foto no suba no puede frenar el guardado:
    // queda la ruta local y se reintenta. Al **analizar**, en cambio, la
    // función necesita la foto en el bucket sí o sí, y tragarse el error
    // convierte "no pudimos subir la foto" en "no encontramos esa foto", que
    // manda a buscar el problema al lugar equivocado.
    bool rethrowOnFailure = false,
  }) async {
    if (localPath == null || localPath.isEmpty) return localPath;
    if (isRemotePath(localPath)) return localPath;

    final account = _auth.currentAccount;
    if (account == null) return localPath;

    final file = File(localPath);
    if (!file.existsSync()) return localPath;

    try {
      return await _client.upload(
        bucket: bucket,
        userId: account.id,
        recordId: recordId,
        file: file,
      );
    } on AppError {
      if (rethrowOnFailure) rethrow;
      // Queda la ruta local: se ve en este teléfono y el próximo guardado del
      // mismo registro vuelve a intentar la subida.
      return localPath;
    }
  }

  /// URL temporal para mostrar una foto del bucket, o `null` si la ruta es
  /// local (todavía sin subir) o no hay sesión.
  Future<String?> viewUrl({
    required PhotoBucket bucket,
    required String? path,
  }) async {
    if (path == null || path.isEmpty || !isRemotePath(path)) return null;
    if (_auth.currentAccount == null) return null;
    try {
      return await _client.signedUrl(bucket: bucket, path: path);
    } on AppError {
      return null;
    }
  }

  Future<void> delete({
    required PhotoBucket bucket,
    required String? path,
  }) async {
    if (path == null || !isRemotePath(path)) return;
    if (_auth.currentAccount == null) return;
    await _client.remove(bucket: bucket, path: path);
  }
}
