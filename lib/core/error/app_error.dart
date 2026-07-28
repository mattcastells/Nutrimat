/// Códigos de error de la API (09-api-contracts.md §2, 10-types §API envelope).
enum ApiErrorCode {
  unauthenticated('ERR_UNAUTHENTICATED'),
  forbidden('ERR_FORBIDDEN'),
  notFound('ERR_NOT_FOUND'),
  validation('ERR_VALIDATION'),
  conflict('ERR_CONFLICT'),
  rateLimited('ERR_RATE_LIMITED'),
  quotaExceeded('ERR_QUOTA_EXCEEDED'),
  upstreamTimeout('ERR_UPSTREAM_TIMEOUT'),
  upstreamFailed('ERR_UPSTREAM_FAILED'),
  aiInvalidResponse('ERR_AI_INVALID_RESPONSE'),
  aiNoFood('ERR_AI_NO_FOOD'),
  permissionDenied('ERR_PERMISSION_DENIED'),
  providerUnavailable('ERR_PROVIDER_UNAVAILABLE'),
  syncFailed('ERR_SYNC_FAILED'),
  offline('ERR_OFFLINE'),
  server('ERR_SERVER'),
  emailTaken('ERR_EMAIL_TAKEN'),
  weakPassword('ERR_WEAK_PASSWORD'),
  invalidCredentials('ERR_INVALID_CREDENTIALS'),
  reauthRequired('ERR_REAUTH_REQUIRED');

  const ApiErrorCode(this.wire);

  final String wire;

  /// Los errores reintentables no revierten una escritura optimista (D-08).
  bool get isRetryable => switch (this) {
    ApiErrorCode.offline ||
    ApiErrorCode.server ||
    ApiErrorCode.upstreamTimeout ||
    ApiErrorCode.upstreamFailed ||
    ApiErrorCode.syncFailed ||
    ApiErrorCode.rateLimited => true,
    _ => false,
  };
}

/// Error de aplicación con mensaje ya redactado para el usuario.
///
/// El handoff prohíbe "Ocurrió un error": cada mensaje dice qué falló y qué
/// puede hacer la persona (05-component-library §5).
class AppError implements Exception {
  const AppError({
    required this.code,
    required this.message,
    this.fields = const <String, String>{},
    this.requestId,
  });

  final ApiErrorCode code;
  final String message;

  /// Errores por campo, para pintarlos debajo del input que corresponde.
  final Map<String, String> fields;
  final String? requestId;

  bool get isRetryable => code.isRetryable;

  static const AppError offline = AppError(
    code: ApiErrorCode.offline,
    message: 'No hay conexión. Vas a poder reintentar cuando vuelva.',
  );

  @override
  String toString() => '${code.wire}: $message';
}

/// Error de una fórmula pura: siempre nombra la función y el campo ofensor
/// (11-calculation-rules.md, reglas transversales).
class CalculationError implements Exception {
  const CalculationError(this.calculation, this.field, this.detail);

  final String calculation;
  final String field;
  final String detail;

  @override
  String toString() => 'CalculationError($calculation, $field): $detail';
}
