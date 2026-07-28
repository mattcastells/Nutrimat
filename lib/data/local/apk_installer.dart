import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../domain/services/update_service.dart';

/// Instala el APK descargado delegando en el instalador de paquetes de
/// Android.
///
/// La app **no instala nada por su cuenta**: escribe el archivo y le pide al
/// sistema que lo abra. Android muestra su propio diálogo de confirmación con
/// el nombre y los permisos, y ahí la persona decide. Eso exige el permiso
/// `REQUEST_INSTALL_PACKAGES` en el manifest y, la primera vez, que se habilite
/// a Nutrimat como origen confiable en Ajustes de Android.
class AndroidApkInstaller implements ApkInstaller {
  const AndroidApkInstaller();

  @override
  Future<void> install(List<int> apkBytes, {required String fileName}) async {
    // El directorio de soporte es privado de la app y `open_filex` lo expone
    // por su FileProvider; la carpeta de descargas exigiría permisos de
    // almacenamiento que no queremos pedir.
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

    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      throw AppError(
        code: ApiErrorCode.permissionDenied,
        message: switch (result.type) {
          ResultType.permissionDenied =>
            'Android necesita tu permiso para instalar apps desde Nutrimat. '
                'Habilitalo en Ajustes → Apps → Nutrimat → Instalar apps '
                'desconocidas.',
          ResultType.noAppToOpen =>
            'Este teléfono no puede abrir el instalador de paquetes. Descargá '
                'el APK desde GitHub e instalalo a mano.',
          _ =>
            'No pudimos abrir el instalador. Descargá el APK desde GitHub e '
                'instalalo a mano.',
        },
      );
    }
  }
}
