import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/ai_analysis.dart';

/// Llama a la Edge Function `analyze-meal-photo`.
///
/// La app **no habla con Gemini**: le pasa a la función la ruta de la foto ya
/// subida al bucket y la función hace el resto. La clave de Gemini vive en los
/// secretos del proyecto y nunca baja al teléfono — una clave dentro de un APK
/// es una clave regalada.
class GeminiAnalysisClient {
  GeminiAnalysisClient(this._functions);

  factory GeminiAnalysisClient.fromInstance() =>
      GeminiAnalysisClient(Supabase.instance.client.functions);

  final FunctionsClient _functions;

  static const String functionName = 'analyze-meal-photo';

  /// La hermana por texto: misma validación y misma cuota, sin foto.
  static const String textFunctionName = 'analyze-meal-text';

  /// La función se corta sola a los 25 s contra Gemini; esto cubre eso más la
  /// descarga de la foto y la red.
  ///
  /// `invoke` **no trae timeout propio**: sin esto, una función que muere deja
  /// la pantalla girando para siempre, sin error y sin forma de salir.
  static const Duration timeout = Duration(seconds: 45);

  /// Estima una comida a partir de una descripción escrita.
  ///
  /// Es lo que el catálogo de productos envasados no puede contestar: "dos
  /// empanadas de carne" no tiene código de barras.
  Future<AiAnalysis> analyzeText({required String description}) async {
    final FunctionResponse response;
    try {
      response = await _functions
          .invoke(
            textFunctionName,
            body: <String, dynamic>{'description': description},
          )
          .timeout(timeout);
    } on FunctionException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message:
            'La estimación tardó demasiado. Probá de nuevo o cargá la comida '
            'a mano.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'No pudimos estimar la comida: revisá tu conexión.',
      );
    }

    return _toAnalysis(response.data, photoPath: null);
  }

  /// Analiza una foto **ya subida al bucket**.
  ///
  /// [description] es lo que la persona aclaró sobre la foto, si aclaró algo.
  /// Va vacía o nula la mayoría de las veces y entonces ni se manda: la foto
  /// sola tiene que seguir funcionando igual.
  Future<AiAnalysis> analyze({
    required String photoPath,
    String? description,
  }) async {
    final hint = description?.trim() ?? '';
    final FunctionResponse response;
    try {
      response = await _functions
          .invoke(
            functionName,
            body: <String, dynamic>{
              'photoPath': photoPath,
              if (hint.isNotEmpty) 'description': hint,
            },
          )
          .timeout(timeout);
    } on FunctionException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message:
            'El análisis tardó demasiado. La foto quedó guardada: cargá la '
            'comida a mano o probá de nuevo.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message:
            'No pudimos analizar la foto: revisá tu conexión. La foto ya está '
            'guardada, podés cargar la comida a mano.',
      );
    }

    return _toAnalysis(response.data, photoPath: photoPath);
  }

  /// Misma forma de respuesta para foto y texto: una sola lectura.
  ///
  /// Todo lo que no cierre sale como [ApiErrorCode.aiInvalidResponse] y no como
  /// un error de casteo. Un `as String` sobre un campo que no vino lanza un
  /// `TypeError`, que **no es una `Exception`**: se escapa de cualquier
  /// `on AppError` y de cualquier `on Exception`, y la pantalla que lo pidió se
  /// queda cargando para siempre. La forma de la respuesta la decide el
  /// servidor, así que acá se la trata como entrada, no como promesa.
  static AiAnalysis _toAnalysis(Object? data, {required String? photoPath}) {
    if (data is! Map) throw _unreadable;

    final id = data['id'];
    if (id is! String || id.isEmpty) throw _unreadable;

    final rawItems = data['items'];
    if (rawItems != null && rawItems is! List) throw _unreadable;

    return AiAnalysis(
      id: id,
      photoPath: photoPath,
      status: AiAnalysisStatus.completed,
      model: data['model'] as String? ?? 'gemini',
      promptVersion: data['promptVersion'] as String? ?? 'v3',
      latencyMs: (data['latencyMs'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.now(),
      items: <AiAnalysisItem>[
        for (final raw in (rawItems as List<dynamic>?) ?? <dynamic>[])
          _toItem(raw),
      ],
    );
  }

  static const AppError _unreadable = AppError(
    code: ApiErrorCode.aiInvalidResponse,
    message:
        'El análisis devolvió algo que no pudimos leer. Cargá la comida a '
        'mano.',
  );

  static AiAnalysisItem _toItem(Object? raw) {
    if (raw is! Map) throw _unreadable;

    final name = raw['name'];
    final quantity = raw['quantity'];
    final unit = raw['unit'];
    final kcal = raw['kcal'];
    if (name is! String || quantity is! num || unit is! String || kcal is! num) {
      throw _unreadable;
    }

    // Los macros y la confianza se completan en cero si faltan: un ítem con
    // nombre y calorías ya es útil, y perderlo entero por un macro ausente
    // sería peor que mostrarlo con un cero visible que la persona corrige.
    return AiAnalysisItem(
      name: name,
      quantity: quantity.toDouble(),
      unit: unit,
      kcal: kcal.round(),
      proteinG: (raw['proteinG'] as num?)?.toDouble() ?? 0,
      carbsG: (raw['carbsG'] as num?)?.toDouble() ?? 0,
      fatG: (raw['fatG'] as num?)?.toDouble() ?? 0,
      confidence: (raw['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  /// La función devuelve `{error: {code, message}}`; el mensaje ya viene
  /// redactado para mostrar, así que se respeta en vez de reescribirlo acá.
  static AppError _translate(FunctionException error) {
    final details = error.details;
    String? code;
    String? message;

    if (details is Map && details['error'] is Map) {
      final inner = details['error'] as Map;
      code = inner['code'] as String?;
      message = inner['message'] as String?;
    }

    final apiCode = ApiErrorCode.values.firstWhere(
      (c) => c.wire == code,
      orElse: () => ApiErrorCode.upstreamFailed,
    );

    return AppError(
      code: apiCode,
      message:
          message ??
          'El análisis falló. Cargá la comida a mano; la foto queda adjunta.',
    );
  }
}
