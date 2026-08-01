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
  ///
  /// [displayName] es el nombre que van a ver los pals. Si no va, el servidor
  /// cae en la parte del correo anterior a la arroba, que es exactamente lo
  /// que no queremos mostrarle a nadie.
  Future<AuthAccount?> signUp({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);

  /// Borra la cuenta del servidor: las fotos de los buckets, las filas de todas
  /// las tablas y el usuario de Auth.
  ///
  /// Lanza [AppError] si algo no se pudo borrar. **Eso importa**: la pantalla
  /// no puede limpiar el teléfono ni cerrar sesión hasta que esto termine bien,
  /// porque si falla y ya se borró lo local, la persona se queda sin sus datos
  /// **y** con la cuenta viva. Antes esta operación no existía y la pantalla
  /// hacía solo `signOut`, así que "eliminar la cuenta" no eliminaba nada.
  ///
  /// Sin servidor configurado no hay cuenta que borrar y no hace nada.
  Future<void> deleteAccount();
}
