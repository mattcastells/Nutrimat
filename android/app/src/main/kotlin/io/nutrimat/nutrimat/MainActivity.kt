package io.nutrimat.nutrimat

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Instalación del APK de una actualización.
 *
 * Se hace acá y no con un plugin genérico de "abrir archivo" porque Android
 * exige un paso que ningún plugin de ese tipo contempla: desde Android 8 la
 * autorización para instalar apps **no la da el manifest**, la da la persona
 * app por app (`REQUEST_INSTALL_PACKAGES` solo habilita a pedirla). Sin ese
 * permiso `startActivity` igual devuelve éxito y el sistema descarta la
 * instalación: la app cree que todo salió bien y el teléfono no instala nada.
 * Por eso `install` chequea primero y devuelve `permission_required` para que
 * la app pueda mandar a Ajustes.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "io.nutrimat.app/installer"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canRequestInstalls())
                    "openInstallSettings" -> result.success(openInstallSettings())
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no_path", "Falta la ruta del APK.", null)
                        } else {
                            result.success(install(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Bajar a la galería la foto de una comida. Canal aparte porque no
        // tiene nada que ver con instalar el APK de una actualización.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GallerySaver.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canSave" -> result.success(GallerySaver.canSave())
                    "save" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName")
                        if (bytes == null || fileName == null) {
                            result.error("no_image", "Falta la foto a guardar.", null)
                        } else {
                            result.success(GallerySaver.save(this, bytes, fileName))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Antes de API 26 el permiso del manifest alcanzaba. */
    private fun canRequestInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    /**
     * La pantalla de "Instalar apps desconocidas" es por app: se abre ya
     * filtrada en Nutrimat para que no haya que buscarla en una lista larga.
     */
    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false

        val targeted = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        // Algunas ROMs no aceptan el filtro por paquete; ahí va la lista
        // completa, y como último recurso la ficha de la app.
        val fallbacks = listOf(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )

        for (intent in listOf(targeted) + fallbacks) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                continue
            }
        }
        return false
    }

    private fun install(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing_file"
        if (!canRequestInstalls()) return "permission_required"

        val uri: Uri = try {
            FileProvider.getUriForFile(this, "$packageName.updates", file)
        } catch (_: IllegalArgumentException) {
            return "unshareable_file"
        }

        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        return try {
            startActivity(intent)
            "ok"
        } catch (_: ActivityNotFoundException) {
            "no_installer"
        }
    }
}
