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
          );
      return path;
    } on StorageException catch (error) {
      throw _translate(error);
    } on Exception {
      throw _offline;
    }
  }

  /// URL temporal para mostrar la foto. Los buckets son privados: no existe
  /// una URL permanente y es a propósito.
  Future<String> signedUrl({
    required PhotoBucket bucket,
    required String path,
  }) async {
    try {
      return await _storage
          .from(bucket.id)
          .createSignedUrl(path, signedUrlTtl.inSeconds);
    } on StorageException catch (error) {
      throw _translate(error);
    } on Exception {
      throw _offline;
    }
  }

  Future<void> remove({
    required PhotoBucket bucket,
    required String path,
  }) async {
    try {
      await _storage.from(bucket.id).remove(<String>[path]);
    } on StorageException catch (error) {
      throw _translate(error);
    } on Exception {
      // Borrar una foto que quizá ya no está no puede romperle el día a nadie:
      // el registro local ya se borró, que es lo que la persona pidió.
    }
  }

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
