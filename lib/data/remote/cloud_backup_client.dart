import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';

/// Qué hay guardado en la nube, sin bajarlo entero.
class CloudBackupInfo {
  const CloudBackupInfo({required this.updatedAt, required this.sizeBytes});

  final DateTime updatedAt;
  final int sizeBytes;

  String get sizeLabel {
    const kb = 1024;
    if (sizeBytes >= kb * kb) {
      return '${(sizeBytes / (kb * kb)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / kb).ceil()} kB';
  }
}

/// Sube y baja el documento del usuario a Storage.
///
/// Es el **mismo JSON** que exporta Configuración → Privacidad, guardado en
/// `{user_id}/backup.json` dentro del bucket privado. La política por prefijo
/// que ya protege las fotos lo protege igual: nadie más puede leerlo.
///
/// Se guarda como un único objeto y no como filas en las 24 tablas. Para una
/// app personal alcanza: cubre no perder nada y cambiar de teléfono, que es lo
/// que hace falta. Si algún día se necesita consultar del lado del servidor —
/// estadísticas, compartir, varios dispositivos a la vez — hay que pasar a
/// sincronización relacional, y esto queda como el camino de migración.
class CloudBackupClient {
  CloudBackupClient(this._storage);

  factory CloudBackupClient.fromInstance() =>
      CloudBackupClient(Supabase.instance.client.storage);

  final SupabaseStorageClient _storage;

  /// Bucket propio: los de fotos restringen los MIME a imágenes y rechazan el
  /// JSON. Tiene la misma política por prefijo.
  static const String bucket = 'backups';
  static const String fileName = 'backup.json';

  String _pathFor(String userId) => '$userId/$fileName';

  /// Sube el documento, reemplazando el anterior.
  Future<void> upload({
    required String userId,
    required String documentJson,
  }) async {
    try {
      await _storage
          .from(bucket)
          .uploadBinary(
            _pathFor(userId),
            Uint8List.fromList(utf8.encode(documentJson)),
            fileOptions: const FileOptions(
              contentType: 'application/json',
              // Sin esto el segundo respaldo falla con "ya existe": lo que
              // queremos es justamente pisar el anterior.
              upsert: true,
            ),
          );
    } on StorageException catch (error) {
      throw _translate(error);
    } on Exception {
      throw _offline;
    }
  }

  /// Devuelve el documento guardado, o `null` si nunca se respaldó.
  Future<String?> download(String userId) async {
    try {
      final bytes = await _storage.from(bucket).download(_pathFor(userId));
      return utf8.decode(bytes);
    } on StorageException catch (error) {
      if (_isNotFound(error)) return null;
      throw _translate(error);
    } on Exception {
      throw _offline;
    }
  }

  /// Metadatos del respaldo sin descargarlo. Sirve para decir "última copia:
  /// hace 3 minutos" sin gastar datos móviles en bajar todo.
  Future<CloudBackupInfo?> info(String userId) async {
    try {
      final files = await _storage
          .from(bucket)
          .list(path: userId, searchOptions: const SearchOptions(limit: 100));

      for (final file in files) {
        // `endsWith` y no `==`: según la versión, Storage devuelve el nombre
        // relativo a la carpeta (`backup.json`) o la ruta completa
        // (`<uid>/backup.json`). Comparando por igualdad, la segunda forma no
        // matcheaba nunca y la pantalla concluía que no había ninguna copia
        // —con el respaldo ahí— y dejaba el botón de restaurar apagado.
        if (!file.name.endsWith(fileName)) continue;
        final size = (file.metadata?['size'] as num?)?.toInt() ?? 0;
        final updated =
            DateTime.tryParse(file.updatedAt ?? file.createdAt ?? '') ??
            DateTime.now();
        return CloudBackupInfo(
          updatedAt: updated.toLocal(),
          sizeBytes: size,
        );
      }
      return null;
    } on StorageException catch (error) {
      if (_isNotFound(error)) return null;
      throw _translate(error);
    } on Exception {
      throw _offline;
    }
  }

  static bool _isNotFound(StorageException error) =>
      error.statusCode == '404' ||
      error.error == 'not_found' ||
      error.message.toLowerCase().contains('not found');

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'Sin conexión: el respaldo va a subir cuando vuelva internet.',
  );

  static AppError _translate(StorageException error) {
    if (error.statusCode == '401' || error.statusCode == '403') {
      return const AppError(
        code: ApiErrorCode.unauthenticated,
        message: 'Tu sesión venció. Volvé a entrar para seguir respaldando.',
      );
    }
    if (error.statusCode == '413') {
      return const AppError(
        code: ApiErrorCode.validation,
        message:
            'El respaldo superó el límite de 8 MB. Exportalo a un archivo '
            'desde Privacidad.',
      );
    }
    return AppError(
      code: ApiErrorCode.server,
      message: 'El respaldo falló (${error.message}). Se reintenta solo.',
    );
  }
}
