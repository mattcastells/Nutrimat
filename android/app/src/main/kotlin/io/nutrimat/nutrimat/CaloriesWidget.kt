package io.nutrimat.nutrimat

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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
 * al que pertenece, y si esa fecha no es hoy el widget no muestra el número:
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
                    views.setTextViewText(R.id.nm_widget_value, state!!.value)
                    views.setTextViewText(R.id.nm_widget_label, state.label)
                    views.setTextViewText(R.id.nm_widget_detail, state.detail)
                } else {
                    // Se distingue "nunca se cargó" de "el dato es de otro día":
                    // la primera es una app recién instalada y la segunda es un
                    // número que ya no vale. Confundirlas manda a buscar el
                    // problema al lugar equivocado.
                    views.setTextViewText(R.id.nm_widget_value, "—")
                    views.setTextViewText(
                        R.id.nm_widget_label,
                        if (state == null) "Todavía sin datos" else "Datos de otro día",
                    )
                    views.setTextViewText(R.id.nm_widget_detail, "Abrí Nutrimat para hoy")
                }

                views.setOnClickPendingIntent(R.id.nm_widget_root, openApp(context))
                manager.updateAppWidget(id, views)
            }
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
 * palabras ("kcal restantes", "kcal de más") salen del mismo lugar que los de
 * Inicio. Acá no se formatea nada porque dos formateadores terminan diciendo
 * cosas distintas del mismo número.
 */
data class CaloriesWidgetState(
    val date: String,
    val value: String,
    val label: String,
    val detail: String,
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
    private const val KEY_VALUE = "value"
    private const val KEY_LABEL = "label"
    private const val KEY_DETAIL = "detail"

    fun write(context: Context, state: CaloriesWidgetState) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DATE, state.date)
            .putString(KEY_VALUE, state.value)
            .putString(KEY_LABEL, state.label)
            .putString(KEY_DETAIL, state.detail)
            .apply()
    }

    fun read(context: Context): CaloriesWidgetState? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val date = prefs.getString(KEY_DATE, null) ?: return null
        return CaloriesWidgetState(
            date = date,
            value = prefs.getString(KEY_VALUE, "—") ?: "—",
            label = prefs.getString(KEY_LABEL, "") ?: "",
            detail = prefs.getString(KEY_DETAIL, "") ?: "",
        )
    }
}
