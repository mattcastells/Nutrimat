import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';

/// Los tres buckets de la migración 18.
enum PhotoBucket {
  meal('meal-photos'),
  activity('activity-photos'),
  progress('progress-photos');

  const PhotoBucket(this.id);

  final String id;
}

/// Sube y sirve las fotos guardadas en Storage.
///
/// La ruta es `{user_id}/{registro_id}.jpg` **siempre**: es la convención de la
/// que dependen las políticas del bucket, que comparan la primera carpeta con
/// `auth.uid()`. Armar la ruta acá y en un solo lugar es lo que impide que un
/// descuido en una pantalla deje una foto fuera del alcance de la política.
class PhotoStorageClient {
  PhotoStorageClient(this._storage);

  factory PhotoStorageClient.fromInstance() =>
      PhotoStorageClient(Supabase.instance.client.storage);

  final SupabaseStorageClient _storage;

  /// Cuánto vale una URL firmada. Una hora alcanza de sobra para mirar una
  /// foto y es corta como para que no sirva de nada si se filtra.
  static const Duration signedUrlTtl = Duration(hours: 1);

  static String pathFor({required String userId, required String recordId}) =>
      '$userId/$recordId.jpg';

  /// Sube la foto y devuelve la ruta guardada, que es lo que va en la columna
  /// `photo_path` del registro.
  Future<String> upload({
    required PhotoBucket bucket,
    required String userId,
    required String recordId,
    required File file,
  }) async {
    final path = pathFor(userId: userId, recordId: recordId);
    try {
      await _storage
          .from(bucket.id)
          .upload(
            path,
            file,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              // Editar una comida y cambiarle la foto reemplaza la anterior en
              // vez de acumular huérfanas que nadie va a borrar.
              upsert: true,
            ),
          )
          .timeout(uploadTimeout);
      return path;
    } on StorageException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message:
            'La foto tardó demasiado en subir. Revisá tu conexión y probá de '
            'nuevo.',
      );
    } on Exception {
      throw _offline;
    }
  }

  /// La subida **no trae timeout propio**.
  ///
  /// Sin esto, con señal mala el `Future` no termina nunca: el análisis por
  /// foto se quedaba girando para siempre en "Está tardando más de lo normal",
  /// porque esperaba una subida que ya no iba a completarse. Una foto de 1024
  /// px comprimida al 80 % pesa unos cientos de kB; 40 s cubre una red lenta
  /// de sobra.
  static const Duration uploadTimeout = Duration(seconds: 40);

  /// URL temporal para mostrar la foto. Los buckets son privados: no existe
  /// una URL permanente y es a propósito.
  Future<String> signedUrl({
    required PhotoBucket bucket,
    required String path,
  }) async {
    try {
      return await _storage
          .from(bucket.id)
          .createSignedUrl(path, signedUrlTtl.inSeconds)
          .timeout(timeout);
    } on StorageException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'La foto tardó demasiado en cargar. Probá de nuevo.',
      );
    } on Exception {
      throw _offline;
    }
  }

  /// Borra la foto del bucket.
  ///
  /// **Lanza si no se pudo borrar**, y eso no es un detalle: `purgeDeletedPhotos`
  /// limpia `photoPath` del registro solo cuando esto no lanzó, justamente para
  /// no dejar una foto en el bucket sin nada que la nombre. Antes acá se tragaba
  /// cualquier `Exception` —incluido el `SocketException` de estar sin
  /// conexión—, así que la purga creía haber borrado, limpiaba la ruta, y la
  /// foto quedaba huérfana **para siempre** en el único recurso que de verdad
  /// puede llenarse.
  ///
  /// Lo único que sigue contando como éxito es que la foto ya no esté: un 404
  /// es el final que se buscaba.
  Future<void> remove({
    required PhotoBucket bucket,
    required String path,
  }) async {
    try {
      await _storage.from(bucket.id).remove(<String>[path]).timeout(timeout);
    } on StorageException catch (error) {
      if (error.statusCode == '404') return;
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'No pudimos borrar la foto: el servidor no contestó.',
      );
    } on Exception {
      throw _offline;
    }
  }

  /// Listar y borrar son pedidos chicos; con más de esto, algo anda mal.
  static const Duration timeout = Duration(seconds: 20);

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'Sin conexión: la foto se sube cuando vuelva internet.',
  );

  static AppError _translate(StorageException error) {
    if (error.statusCode == '401' || error.statusCode == '403') {
      return const AppError(
        code: ApiErrorCode.unauthenticated,
        message: 'Tu sesión venció. Volvé a entrar para subir la foto.',
      );
    }
    if (error.statusCode == '413') {
      return const AppError(
        code: ApiErrorCode.validation,
        message: 'La foto supera los 8 MB. Sacala con menos resolución.',
      );
    }
    return AppError(
      code: ApiErrorCode.server,
      message: 'No pudimos subir la foto (${error.message}).',
    );
  }
}
