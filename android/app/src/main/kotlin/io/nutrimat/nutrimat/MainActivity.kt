package io.nutrimat.nutrimat

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.health.connect.client.PermissionController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.launch

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
        const val WIDGET_CHANNEL = "io.nutrimat.app/widget"
        const val APK_MIME = "application/vnd.android.package-archive"
        const val REQ_HEALTH_PERMISSIONS = 7301
    }

    /** La llamada de Dart que espera el resultado del pedido de permisos. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    /**
     * El pedido de permisos de Health Connect, con `startActivityForResult`.
     *
     * `registerForActivityResult` sería más lindo y **no está**:
     * `FlutterActivity` hereda de `android.app.Activity`, no de
     * `ComponentActivity`, así que no trae la API nueva ni `lifecycleScope`.
     * Cambiar la clase base a `FlutterFragmentActivity` los traería, y también
     * cambiaría la actividad de la que dependen la cámara, el escáner y el
     * selector de fotos — no vale la pena arriesgar eso por azúcar sintáctica.
     * El contrato se usa igual: solo se crea el intent y se parsea el resultado
     * a mano.
     */
    private val healthContract = PermissionController.createRequestPermissionResultContract()

    /**
     * Para las llamadas `suspend` del puente. Propio y no `lifecycleScope`, por
     * lo mismo de arriba; se cancela con la actividad para no dejar corrutinas
     * hablándole a una pantalla que ya no está.
     */
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    @Deprecated("Sin ComponentActivity no hay otra forma; ver healthContract.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_HEALTH_PERMISSIONS) return
        val granted = healthContract.parseResult(resultCode, data)
        pendingPermissionResult?.success(
            granted.containsAll(HealthConnectBridge.PERMISSIONS),
        )
        pendingPermissionResult = null
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

        // Widget de la pantalla de inicio. Canal aparte, igual que los otros
        // dos: lo único que comparten es el proceso.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publish" -> {
                        val date = call.argument<String>("date")
                        if (date == null) {
                            result.error("no_date", "Falta la fecha del dato.", null)
                        } else {
                            CaloriesWidgetStore.write(
                                this,
                                CaloriesWidgetState(
                                    date = date,
                                    value = call.argument<String>("value") ?: "—",
                                    label = call.argument<String>("label") ?: "",
                                    // −1 y no 0: sin objetivo la barra del día no
                                    // se dibuja, en vez de dibujarse vacía.
                                    caloriesPercent = call.argument<Int>("caloriesPercent") ?: -1,
                                    waterGlasses = call.argument<Int>("waterGlasses") ?: 0,
                                    waterGoal = call.argument<Int>("waterGoal") ?: 0,
                                    waterMax = call.argument<Int>("waterMax") ?: 40,
                                    proteinLabel = call.argument<String>("proteinLabel") ?: "",
                                    proteinPercent = call.argument<Int>("proteinPercent") ?: 0,
                                    carbsLabel = call.argument<String>("carbsLabel") ?: "",
                                    carbsPercent = call.argument<Int>("carbsPercent") ?: 0,
                                    fatLabel = call.argument<String>("fatLabel") ?: "",
                                    fatPercent = call.argument<Int>("fatPercent") ?: 0,
                                    intakeLabel = call.argument<String>("intakeLabel") ?: "",
                                    activityLabel = call.argument<String>("activityLabel") ?: "",
                                    sleepLabel = call.argument<String>("sleepLabel") ?: "",
                                    streakLabel = call.argument<String>("streakLabel") ?: "",
                                    staleLabel = call.argument<String>("staleLabel") ?: "",
                                ),
                            )
                            CaloriesWidget.refresh(this)
                            result.success(null)
                        }
                    }
                    // Los vasos que se tocaron en el widget mientras la app no
                    // corría. El widget no escribe en la base —el documento es
                    // uno y reescribirlo de a dos procesos pisa datos—, así que
                    // los anota y la app se los lleva acá.
                    "drainPendingWater" ->
                        result.success(CaloriesWidgetStore.drainPending(this))
                    else -> result.notImplemented()
                }
            }

        // Health Connect. Todo lo de acá es `suspend`, así que cada llamada
        // corre en el scope de la actividad y contesta cuando termina.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HealthConnectBridge.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "availability" ->
                        result.success(HealthConnectBridge.availability(this))
                    "hasPermissions" -> scope.launch {
                        result.success(HealthConnectBridge.hasAllPermissions(this@MainActivity))
                    }
                    // El permiso lo concede Health Connect en su propia pantalla,
                    // no el diálogo de permisos de Android: se pide con un
                    // contrato de resultado de actividad y la respuesta llega por
                    // el callback, no de vuelta de esta llamada.
                    "requestPermissions" -> {
                        pendingPermissionResult = result
                        startActivityForResult(
                            healthContract.createIntent(this, HealthConnectBridge.PERMISSIONS),
                            REQ_HEALTH_PERMISSIONS,
                        )
                    }
                    "read" -> scope.launch {
                        try {
                            result.success(HealthConnectBridge.read(this@MainActivity))
                        } catch (error: Exception) {
                            // Un fallo de lectura no puede quedar en silencio: la
                            // pantalla de Integraciones muestra el motivo.
                            result.error("read_failed", error.message, null)
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
