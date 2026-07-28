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
  /// Para prenderlo hace falta el adaptador nativo en `data/native/`, los
  /// permisos de lectura y `minSdk 29` (D-21). Hoy la sincronización inserta
  /// tres actividades de ejemplo.
  static const bool healthConnectSync = bool.fromEnvironment('NM_HEALTH_SYNC');

  /// Respaldo y sincronización en la nube (Supabase).
  ///
  /// Mientras esté apagado, los datos viven solo en este teléfono y el
  /// respaldo es el archivo JSON de Configuración → Privacidad.
  static const bool cloudBackup = bool.fromEnvironment('NM_CLOUD');

  /// Catálogo externo de alimentos (Open Food Facts). No necesita clave.
  static const bool onlineFoodCatalog = bool.fromEnvironment(
    'NM_FOOD_CATALOG',
    defaultValue: true,
  );
}
