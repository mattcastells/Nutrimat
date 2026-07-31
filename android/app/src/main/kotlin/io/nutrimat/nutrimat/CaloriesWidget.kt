package io.nutrimat.nutrimat

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar

/**
 * El widget de calorías restantes de la pantalla de inicio del teléfono.
 *
 * Un widget lo dibuja el launcher, en su proceso y con la app cerrada, así que
 * no puede preguntarle nada a Dart: lo único que hay es un dato guardado. La
 * app lo escribe cuando cambia algo (canal `io.nutrimat.app/widget`) y acá se
 * lee.
 *
 * **La regla que manda es no mentir.** El dato guardado tiene la fecha del día
 * al que pertenece, y si esa fecha no es hoy el widget no muestra nada de él:
 * dice que hay que abrir la app. Un widget que no se actualizó desde ayer
 * mostrando "te quedan 1.234 kcal" es peor que uno vacío, porque no se
 * distingue de uno al día — es la misma regla por la que la app nunca presenta
 * una estimación como si fuera una medición.
 */
class CaloriesWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        render(context, manager, appWidgetIds)
    }

    companion object {

        /**
         * Las gotas que hay dibujadas en el layout. RemoteViews no puede crear
         * vistas, así que este número es un techo del XML, no una decisión: por
         * eso al lado va la cuenta exacta, que sí puede pasar de ocho.
         */
        private val DROPS = intArrayOf(
            R.id.nm_widget_drop_1,
            R.id.nm_widget_drop_2,
            R.id.nm_widget_drop_3,
            R.id.nm_widget_drop_4,
            R.id.nm_widget_drop_5,
            R.id.nm_widget_drop_6,
            R.id.nm_widget_drop_7,
            R.id.nm_widget_drop_8,
        )

        /**
         * Redibuja los widgets que haya puestos. Sin ninguno no hace nada, que
         * es el caso de casi todo el mundo: nadie tiene por qué pagar el costo
         * de un widget que no puso.
         */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(
                ComponentName(context, CaloriesWidget::class.java),
            )
            if (ids.isEmpty()) return
            render(context, manager, ids)
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val state = CaloriesWidgetStore.read(context)
            val fresh = state != null && state.date == todayIso()

            for (id in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.nm_widget_calories)

                if (fresh) {
                    renderDay(views, state!!)
                } else {
                    renderStale(views, hadData = state != null)
                }

                views.setOnClickPendingIntent(R.id.nm_widget_root, openApp(context))
                manager.updateAppWidget(id, views)
            }
        }

        private fun renderDay(views: RemoteViews, state: CaloriesWidgetState) {
            views.setViewVisibility(R.id.nm_widget_value, View.VISIBLE)
            views.setTextViewText(R.id.nm_widget_value, state.value)
            views.setTextViewText(R.id.nm_widget_label, state.label)
            views.setTextViewText(R.id.nm_widget_detail, state.detail)

            // ── Agua ──────────────────────────────────────────────────────
            // Una gota llena por vaso tomado y una vacía por cada uno que falta
            // hasta la meta. Las de más allá de la meta se esconden en vez de
            // quedar dibujadas: ocho gotas fijas con una meta de cinco diría que
            // faltan tres que nadie se propuso.
            val visible = maxOf(state.waterGoal, state.waterGlasses)
            for ((index, dropId) in DROPS.withIndex()) {
                val nth = index + 1
                if (nth > visible) {
                    views.setViewVisibility(dropId, View.GONE)
                    continue
                }
                views.setViewVisibility(dropId, View.VISIBLE)
                views.setImageViewResource(
                    dropId,
                    if (nth <= state.waterGlasses) {
                        R.drawable.nm_widget_drop_full
                    } else {
                        R.drawable.nm_widget_drop_empty
                    },
                )
            }
            views.setViewVisibility(R.id.nm_widget_water_count, View.VISIBLE)
            views.setTextViewText(
                R.id.nm_widget_water_count,
                "${state.waterGlasses}/${state.waterGoal}",
            )

            // ── Macros ────────────────────────────────────────────────────
            views.setViewVisibility(R.id.nm_widget_macros, View.VISIBLE)
            views.setTextViewText(R.id.nm_widget_protein_label, state.proteinLabel)
            views.setProgressBar(R.id.nm_widget_protein_bar, 100, state.proteinPercent, false)
            views.setTextViewText(R.id.nm_widget_carbs_label, state.carbsLabel)
            views.setProgressBar(R.id.nm_widget_carbs_bar, 100, state.carbsPercent, false)
            views.setTextViewText(R.id.nm_widget_fat_label, state.fatLabel)
            views.setProgressBar(R.id.nm_widget_fat_bar, 100, state.fatPercent, false)
        }

        /**
         * El dato no es de hoy, o no hay ninguno.
         *
         * Se esconde **todo** lo que sería de otro día —las gotas, las barras,
         * la cuenta— y no solo el número grande. Media pantalla con los macros
         * de ayer al lado de un guion se lee como si el guion fuera el problema
         * y el resto estuviera bien.
         */
        private fun renderStale(views: RemoteViews, hadData: Boolean) {
            // El número grande se esconde, no se reemplaza por un guion: a 26 sp
            // y en color de acento, un "—" suelto se lee como una raya de la
            // interfaz y no como "acá iba un número que hoy no tengo".
            views.setViewVisibility(R.id.nm_widget_value, View.GONE)
            // Se distingue "nunca se cargó" de "el dato es de otro día": la
            // primera es una app recién instalada y la segunda es un número que
            // ya no vale. Confundirlas manda a buscar el problema al lugar
            // equivocado.
            views.setTextViewText(
                R.id.nm_widget_label,
                if (hadData) "Datos de otro día" else "Todavía sin datos",
            )
            views.setTextViewText(R.id.nm_widget_detail, "Abrí Nutrimat para hoy")

            for (dropId in DROPS) {
                views.setViewVisibility(dropId, View.GONE)
            }
            views.setViewVisibility(R.id.nm_widget_water_count, View.GONE)
            views.setViewVisibility(R.id.nm_widget_macros, View.GONE)
        }

        /**
         * Tocar el widget abre la app. `FLAG_IMMUTABLE` es obligatorio desde
         * API 31 y acá además es lo correcto: nadie tiene que poder cambiarle el
         * destino a este intent.
         */
        private fun openApp(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /**
         * El día de hoy en la zona del teléfono, en el mismo formato que manda
         * Dart (`isoDate`). Se compara texto y no fechas a propósito: es la
         * única forma de que las dos puntas no puedan discrepar por husos ni por
         * horarios de verano.
         */
        fun todayIso(): String {
            val now = Calendar.getInstance()
            return "%04d-%02d-%02d".format(
                now.get(Calendar.YEAR),
                now.get(Calendar.MONTH) + 1,
                now.get(Calendar.DAY_OF_MONTH),
            )
        }
    }
}

/**
 * Lo que el widget muestra, tal como lo dejó la app.
 *
 * Los textos vienen ya formateados desde Dart: el separador de miles y las
 * palabras ("kcal restantes", "kcal de más", "P 120/140") salen del mismo lugar
 * que los de Inicio. Acá no se formatea nada porque dos formateadores terminan
 * diciendo cosas distintas del mismo número. Los que sí son números son cuentas
 * —vasos y porcentajes—, porque de eso se decide *cuánto dibujar*.
 */
data class CaloriesWidgetState(
    val date: String,
    val value: String,
    val label: String,
    val detail: String,
    val waterGlasses: Int,
    val waterGoal: Int,
    val proteinLabel: String,
    val proteinPercent: Int,
    val carbsLabel: String,
    val carbsPercent: Int,
    val fatLabel: String,
    val fatPercent: Int,
)

/**
 * El dato del widget, en sus propias preferencias.
 *
 * Archivo aparte del de Flutter (`FlutterSharedPreferences`) a propósito: leer
 * el almacenamiento interno de un plugin ataría el widget a un detalle de
 * implementación que puede cambiar con una actualización de dependencias, y el
 * síntoma sería un widget que deja de actualizarse sin que nada falle.
 */
object CaloriesWidgetStore {

    private const val PREFS = "nm_widget"
    private const val KEY_DATE = "date"

    fun write(context: Context, state: CaloriesWidgetState) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DATE, state.date)
            .putString("value", state.value)
            .putString("label", state.label)
            .putString("detail", state.detail)
            .putInt("waterGlasses", state.waterGlasses)
            .putInt("waterGoal", state.waterGoal)
            .putString("proteinLabel", state.proteinLabel)
            .putInt("proteinPercent", state.proteinPercent)
            .putString("carbsLabel", state.carbsLabel)
            .putInt("carbsPercent", state.carbsPercent)
            .putString("fatLabel", state.fatLabel)
            .putInt("fatPercent", state.fatPercent)
            .apply()
    }

    fun read(context: Context): CaloriesWidgetState? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val date = prefs.getString(KEY_DATE, null) ?: return null
        return CaloriesWidgetState(
            date = date,
            value = prefs.getString("value", "—") ?: "—",
            label = prefs.getString("label", "") ?: "",
            detail = prefs.getString("detail", "") ?: "",
            waterGlasses = prefs.getInt("waterGlasses", 0),
            waterGoal = prefs.getInt("waterGoal", 0),
            proteinLabel = prefs.getString("proteinLabel", "") ?: "",
            proteinPercent = prefs.getInt("proteinPercent", 0),
            carbsLabel = prefs.getString("carbsLabel", "") ?: "",
            carbsPercent = prefs.getInt("carbsPercent", 0),
            fatLabel = prefs.getString("fatLabel", "") ?: "",
            fatPercent = prefs.getInt("fatPercent", 0),
        )
    }
}
