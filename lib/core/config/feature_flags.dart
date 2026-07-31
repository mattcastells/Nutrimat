/// Interruptores de las integraciones que todavía no están conectadas de
/// verdad.
///
/// Regla: **mientras una integración devuelva datos inventados, su flag va en
/// `false`**. Es preferible una pantalla que diga "todavía no" a un registro
/// falso metido en el historial de la persona — el producto se apoya en que
/// ningún número sea inventado (RN-03, D-07).
///
/// Se encienden en tiempo de compilación:
/// ```bash
/// flutter run --dart-define=NM_AI_PHOTO=true
/// ```
abstract final class FeatureFlags {
  /// Análisis de foto con Gemini.
  ///
  /// Ya no devuelve un resultado fijo: la Edge Function `analyze-meal-photo`
  /// está desplegada, con la clave del lado del servidor y la cuota diaria de
  /// 20 análisis (D-18).
  ///
  /// Encendido por defecto. En una compilación **sin** Supabase no hay a quién
  /// preguntarle, así que ahí se apaga solo.
  static const bool aiPhotoAnalysis = bool.fromEnvironment(
    'NM_AI_PHOTO',
    defaultValue: true,
  );

  /// Importación desde Health Connect.
  ///
  /// Ya no inserta actividades de ejemplo: lee de verdad el peso, la grasa
  /// corporal y el sueño de los últimos 30 días (`HealthConnectGateway`). Con
  /// esto entran los datos de Samsung Health y del Zepp app, que escriben ahí —
  /// Zepp no tiene API pública para leerle nada a nadie, así que este es el
  /// único camino que existe para un Amazfit.
  ///
  /// Encendido por defecto. En un teléfono sin Health Connect la pantalla de
  /// Integraciones lo dice y no ofrece conectar.
  static const bool healthConnectSync = bool.fromEnvironment(
    'NM_HEALTH_SYNC',
    defaultValue: true,
  );

  // El flag `cloudBackup` se sacó: no lo leía nadie y encima mentía. Decía
  // "mientras esté apagado, los datos viven solo en este teléfono", y el
  // respaldo a la nube funciona desde hace varias versiones — lo decide
  // `SupabaseConfig.isConfigured`, no un flag. Un interruptor apagado que
  // describe un comportamiento que ya no existe es peor que no tenerlo:
  // manda a buscar el problema al lugar equivocado.

  /// Catálogo externo de alimentos (Open Food Facts). No necesita clave.
  static const bool onlineFoodCatalog = bool.fromEnvironment(
    'NM_FOOD_CATALOG',
    defaultValue: true,
  );
}
