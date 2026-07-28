import '../../core/error/app_error.dart';

/// La cuenta con la que se abrió la sesión.
class AuthAccount {
  const AuthAccount({required this.id, required this.email});

  /// `auth.users.id` en Supabase. Es el mismo valor que `auth.uid()` usa en
  /// todas las políticas RLS, así que es la clave de todo lo que se sincronice
  /// después.
  final String id;
  final String email;
}

/// Inicio de sesión, alta y recuperación de contraseña.
///
/// Vive aparte de `ProfileRepository` a propósito: el perfil (peso, objetivo,
/// unidades) es un dato de la app y la sesión es un dato del servidor. Mezclar
/// las dos cosas fue lo que dejó un `signIn(email)` sin contraseña, que parecía
/// autenticación y no lo era.
abstract interface class AuthGateway {
  /// Sesión ya abierta al arrancar, si `supabase_flutter` la pudo restaurar
  /// desde el almacenamiento del dispositivo.
  AuthAccount? get currentAccount;

  bool get hasSession;

  /// Emite en cada cambio de sesión, incluido el refresco de token que hace la
  /// librería sola.
  Stream<AuthAccount?> get changes;

  /// Lanza [AppError] con `invalidCredentials` si el par no es válido.
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  });

  /// Con la confirmación por correo activada en el proyecto, devuelve `null`:
  /// la cuenta existe pero todavía no hay sesión hasta que se confirme.
  Future<AuthAccount?> signUp({
    required String email,
    required String password,
  });

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);
}
