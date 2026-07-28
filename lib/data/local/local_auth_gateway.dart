import 'dart:async';

import '../../core/error/app_error.dart';
import '../../domain/repositories/auth_gateway.dart';

/// Sesión sin servidor, para cuando la compilación no tiene Supabase
/// configurado.
///
/// **No autentica nada**: acepta cualquier par de credenciales bien formadas y
/// guarda el correo en memoria. Existe para que `flutter run` y `flutter test`
/// funcionen en una máquina sin claves, y para que el modo demo (D-15) siga
/// entrando sin cuenta.
///
/// Por eso `AuthGateway` es una interfaz y no una clase concreta: la diferencia
/// entre "hay sesión de verdad" y "hay sesión de mentira" tiene que ser
/// explícita en el arranque, no un `if` escondido en una pantalla.
class LocalAuthGateway implements AuthGateway {
  LocalAuthGateway({AuthAccount? initial}) : _account = initial;

  AuthAccount? _account;
  final StreamController<AuthAccount?> _changes =
      StreamController<AuthAccount?>.broadcast();

  @override
  AuthAccount? get currentAccount => _account;

  @override
  bool get hasSession => _account != null;

  @override
  Stream<AuthAccount?> get changes => _changes.stream;

  void _set(AuthAccount? account) {
    _account = account;
    _changes.add(account);
  }

  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw const AppError(
        code: ApiErrorCode.invalidCredentials,
        message: 'El correo o la contraseña no coinciden.',
      );
    }
    // El id es estable para el mismo correo: si algún día estos datos se
    // suben, no queda un usuario distinto por cada inicio de sesión local.
    final account = AuthAccount(id: 'local:$email', email: email);
    _set(account);
    return account;
  }

  @override
  Future<AuthAccount?> signUp({
    required String email,
    required String password,
  }) => signIn(email: email, password: password);

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<void> sendPasswordReset(String email) async {
    throw const AppError(
      code: ApiErrorCode.providerUnavailable,
      message:
          'Esta compilación no tiene servidor: no se puede recuperar la '
          'contraseña.',
    );
  }

  void dispose() => _changes.close();
}
