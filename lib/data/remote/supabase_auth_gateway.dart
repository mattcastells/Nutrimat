import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/repositories/auth_gateway.dart';

/// Autenticación real contra Supabase Auth.
///
/// `supabase_flutter` persiste la sesión y refresca el token solo; acá no se
/// guarda ningún token a mano. El `id` que devuelve es `auth.uid()`, la clave
/// sobre la que están escritas las 78 políticas RLS.
class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._auth, this._functions);

  /// Toma el cliente ya inicializado en `bootstrap()`.
  factory SupabaseAuthGateway.fromInstance() => SupabaseAuthGateway(
    Supabase.instance.client.auth,
    Supabase.instance.client.functions,
  );

  final GoTrueClient _auth;

  /// Borrar la cuenta necesita la secret key, así que lo hace una Edge
  /// Function y no el cliente.
  final FunctionsClient _functions;

  static AuthAccount? _toAccount(User? user) {
    if (user == null) return null;
    return AuthAccount(id: user.id, email: user.email ?? '');
  }

  @override
  AuthAccount? get currentAccount => _toAccount(_auth.currentUser);

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  Stream<AuthAccount?> get changes =>
      _auth.onAuthStateChange.map((state) => _toAccount(state.session?.user));

  @override
  Future<AuthAccount> signIn({
    required String email,
    required String password,
  }) async {
    final AuthResponse response;
    try {
      response = await _auth
          .signInWithPassword(email: email, password: password)
          .timeout(timeout);
    } on AuthException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw _slow;
    } on Exception {
      throw _offline;
    }

    final account = _toAccount(response.user);
    if (account == null) {
      throw const AppError(
        code: ApiErrorCode.invalidCredentials,
        message: 'El correo o la contraseña no coinciden.',
      );
    }
    return account;
  }

  @override
  Future<AuthAccount?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final name = displayName?.trim();
    final AuthResponse response;
    try {
      response = await _auth
          .signUp(
            email: email,
            password: password,
            // Lo lee el trigger `handle_new_user` para poblar
            // `profiles.display_name`; sin esto queda la parte del mail previa
            // a la arroba y eso es lo que terminan viendo los pals.
            data: name == null || name.isEmpty
                ? null
                : <String, dynamic>{'display_name': name},
          )
          .timeout(timeout);
    } on AuthException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw _slow;
    } on Exception {
      throw _offline;
    }

    // Sin sesión = el proyecto pide confirmar el correo antes de entrar.
    if (response.session == null) return null;
    return _toAccount(response.user);
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Exception {
      // Cerrar sesión no puede fallar de cara a la persona: si el servidor no
      // contesta, la librería ya borró la sesión local, que es lo que importa.
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.resetPasswordForEmail(email).timeout(timeout);
    } on AuthException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw _slow;
    } on Exception {
      throw _offline;
    }
  }

  /// Entrar, crear la cuenta y pedir el correo de recuperación no llevan más
  /// que esto. Sin plazo propio, una señal mala —el socket abre y no
  /// contesta— dejaba el botón "Entrar" girando para siempre, sin error y sin
  /// forma de salir salvo matar la app.
  static const Duration timeout = Duration(seconds: 30);

  /// "No hay señal" y "hay señal pero no contesta" mandan a mirar lugares
  /// distintos, así que se dicen distinto.
  static const AppError _slow = AppError(
    code: ApiErrorCode.upstreamTimeout,
    message: 'El servidor tardó demasiado en contestar. Probá de nuevo.',
  );

  @override
  Future<void> deleteAccount() async {
    // Lo hace la Edge Function `delete-account`, porque borrar de `auth.users`
    // necesita la secret key y esa clave no puede viajar en el APK. El JWT va
    // en el header y la función resuelve de ahí a quién borrar: nunca del
    // cuerpo del pedido.
    final FunctionResponse response;
    try {
      response = await _functions
          .invoke('delete-account')
          .timeout(deleteTimeout);
    } on FunctionException catch (error) {
      throw AppError(
        code: ApiErrorCode.server,
        message: _messageOf(error.details) ??
            'No pudimos borrar la cuenta. Probá de nuevo en un rato.',
        requestId: '${error.status}',
      );
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'El borrado tardó demasiado. Revisá tu conexión y fijate en '
            'un rato si la cuenta sigue estando.',
      );
    } on Exception {
      throw _offline;
    }

    if (response.status != 200) {
      throw AppError(
        code: ApiErrorCode.server,
        message: _messageOf(response.data) ??
            'No pudimos borrar la cuenta. Probá de nuevo en un rato.',
        requestId: '${response.status}',
      );
    }
  }

  /// Borrar toca cuatro buckets antes de la cuenta: no es una operación corta.
  static const Duration deleteTimeout = Duration(seconds: 60);

  /// El texto que la función puso en `{ error: { message } }`, si vino con esa
  /// forma. Cualquier otra cosa es `null` y se usa el mensaje genérico: un
  /// `as String` acá dejaría el borrado sin explicación por una respuesta con
  /// forma inesperada.
  static String? _messageOf(Object? data) {
    if (data is! Map) return null;
    final error = data['error'];
    if (error is! Map) return null;
    final message = error['message'];
    return message is String && message.isNotEmpty ? message : null;
  }

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'No pudimos conectarnos. Revisá tu conexión y probá de nuevo.',
  );

  /// Traduce los errores de GoTrue a mensajes que dicen qué hacer.
  ///
  /// El handoff prohíbe "Ocurrió un error" (05-component-library §5), así que
  /// cada caso conocido tiene su texto; el resto cae en uno genérico pero que
  /// al menos indica el paso siguiente.
  static AppError _translate(AuthException error) {
    final code = error.code ?? '';
    final message = error.message.toLowerCase();

    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return const AppError(
        code: ApiErrorCode.invalidCredentials,
        message: 'El correo o la contraseña no coinciden.',
      );
    }
    if (code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return const AppError(
        code: ApiErrorCode.unauthenticated,
        message: 'Falta confirmar el correo. Buscá el mail que te mandamos y '
            'abrí el enlace.',
      );
    }
    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        message.contains('already registered')) {
      return const AppError(
        code: ApiErrorCode.emailTaken,
        message: 'Ya hay una cuenta con ese correo. Probá iniciar sesión.',
      );
    }
    if (code == 'email_address_invalid' ||
        code == 'validation_failed' ||
        message.contains('email address') && message.contains('invalid')) {
      return const AppError(
        code: ApiErrorCode.validation,
        message: 'Ese correo no es válido. Revisá que esté bien escrito.',
        fields: <String, String>{'email': 'Correo inválido'},
      );
    }
    if (code == 'weak_password' || message.contains('password')) {
      return const AppError(
        code: ApiErrorCode.weakPassword,
        message:
            'La contraseña necesita al menos 8 caracteres, una letra y un '
            'número.',
      );
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_email_send_rate_limit' ||
        error.statusCode == '429') {
      return const AppError(
        code: ApiErrorCode.rateLimited,
        message: 'Demasiados intentos seguidos. Esperá un minuto y probá de '
            'nuevo.',
      );
    }

    // El mensaje del proveedor viene en inglés y no le sirve a nadie; queda en
    // `requestId` por si hace falta rastrearlo.
    return AppError(
      code: ApiErrorCode.server,
      message: 'No pudimos completar la operación. Probá de nuevo en un rato.',
      requestId: error.message,
    );
  }
}
