/// Conexión a Supabase, resuelta en tiempo de compilación.
///
/// Los valores entran por `--dart-define`, normalmente desde un archivo:
///
/// ```bash
/// flutter run --dart-define-from-file=env/local.json
/// ```
///
/// Si falta cualquiera de los dos, la app arranca en **modo local**: sin red,
/// con la sesión y los datos guardados solo en el teléfono. Eso mantiene
/// `flutter run` y `flutter test` andando en una máquina sin credenciales, y
/// evita el peor final posible — una app que compila, se instala y falla recién
/// al intentar iniciar sesión.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');

  /// La `publishable key` (`sb_publishable_…`). Viaja en el cliente a
  /// propósito: es segura **porque** existe RLS, no porque sea secreta.
  ///
  /// La `secret key` no entra acá jamás: saltea RLS y vive solo en los
  /// secretos de las Edge Functions.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Motivo legible cuando no está configurada, para mostrarlo en Ajustes en
  /// vez de dejar a alguien adivinando por qué no puede entrar.
  static String? get unavailableReason {
    if (url.isEmpty && publishableKey.isEmpty) {
      return 'Esta compilación no tiene servidor configurado: los datos viven '
          'solo en este teléfono.';
    }
    if (url.isEmpty) return 'Falta SUPABASE_URL en esta compilación.';
    return 'Falta SUPABASE_PUBLISHABLE_KEY en esta compilación.';
  }
}
