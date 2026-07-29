import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../domain/services/update_service.dart';

/// Instala el APK descargado delegando en el instalador de paquetes de
/// Android.
///
/// La app **no instala nada por su cuenta**: escribe el archivo y le pide al
/// sistema que lo abra. Android muestra su propio diálogo de confirmación con
/// el nombre y los permisos, y ahí la persona decide.
///
/// Eso exige dos cosas distintas, y confundirlas fue el motivo de que la
/// actualización se descargara sin instalarse nunca:
///
/// 1. `REQUEST_INSTALL_PACKAGES` en el manifest. Solo habilita a **pedir**.
/// 2. Que la persona haya marcado a Nutrimat como origen confiable en
///    Ajustes → Apps → Nutrimat → Instalar apps desconocidas. Es por app
///    instaladora, no global: por eso otras apps sí pueden instalar y esta no.
///
/// Sin el punto 2, lanzar el intent igual "funciona" —el sistema no devuelve
/// error— y el instalador se cierra sin hacer nada. Por eso [canInstall] se
/// consulta antes y [openInstallSettings] lleva directo a la pantalla donde se
/// habilita.
class AndroidApkInstaller implements ApkInstaller {
  const AndroidApkInstaller();

  static const MethodChannel _channel = MethodChannel(
    'io.nutrimat.app/installer',
  );

  @override
  Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openInstallSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openInstallSettings');
    } on PlatformException {
      throw const AppError(
        code: ApiErrorCode.server,
        message:
            'No pudimos abrir Ajustes. Buscá Apps → Nutrimat → Instalar apps '
            'desconocidas y habilitalo a mano.',
      );
    }
  }

  @override
  Future<void> install(List<int> apkBytes, {required String fileName}) async {
    // El directorio de soporte es privado de la app y el FileProvider de
    // `nm_update_paths.xml` lo expone; la carpeta de descargas exigiría
    // permisos de almacenamiento que no queremos pedir.
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');

    try {
      // Un intento anterior pudo dejar un archivo a medias.
      if (await file.exists()) await file.delete();
      await file.writeAsBytes(apkBytes, flush: true);
    } on FileSystemException {
      throw const AppError(
        code: ApiErrorCode.server,
        message:
            'No pudimos guardar la actualización. Liberá espacio en el '
            'teléfono y probá de nuevo.',
      );
    }

    final String result;
    try {
      result =
          await _channel.invokeMethod<String>(
            'install',
            <String, dynamic>{'path': file.path},
          ) ??
          'unknown';
    } on PlatformException {
      throw const AppError(
        code: ApiErrorCode.server,
        message:
            'No pudimos abrir el instalador. Descargá el APK desde GitHub e '
            'instalalo a mano.',
      );
    }

    if (result == 'ok') return;

    throw AppError(
      code: result == 'permission_required'
          ? ApiErrorCode.permissionDenied
          : ApiErrorCode.server,
      message: switch (result) {
        'permission_required' =>
          'Android necesita tu permiso para instalar apps desde Nutrimat.',
        'no_installer' =>
          'Este teléfono no puede abrir el instalador de paquetes. Descargá '
              'el APK desde GitHub e instalalo a mano.',
        'missing_file' =>
          'La actualización descargada no quedó en el teléfono. Probá de '
              'nuevo.',
        _ =>
          'No pudimos abrir el instalador. Descargá el APK desde GitHub e '
              'instalalo a mano.',
      },
    );
  }
}
