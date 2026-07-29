import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/models/food.dart';

/// Alimentos genéricos, vía la Edge Function `food-search`.
///
/// La app **no habla con USDA**: su clave vive en los secretos del proyecto.
/// Una clave dentro de un APK es una clave regalada, igual que con Gemini.
///
/// Qué agrega. Open Food Facts es un catálogo de productos envasados con
/// código de barras: sabe de un yogur de una marca y es ciego a "pechuga de
/// pollo" o "arroz cocido". USDA cubre justamente lo genérico y crudo.
class UsdaFoodClient {
  UsdaFoodClient(this._functions);

  factory UsdaFoodClient.fromInstance() =>
      UsdaFoodClient(Supabase.instance.client.functions);

  final FunctionsClient _functions;

  static const String functionName = 'food-search';

  /// Corto a propósito: es una búsqueda mientras se escribe, y una espera
  /// larga acá se siente como que la app se colgó.
  static const Duration timeout = Duration(seconds: 15);

  Future<List<Food>> search(String query, {int limit = 20}) async {
    if (query.trim().length < 2) return const <Food>[];

    final FunctionResponse response;
    try {
      response = await _functions
          .invoke(
            functionName,
            body: <String, dynamic>{'query': query.trim(), 'limit': limit},
          )
          .timeout(timeout);
    } on FunctionException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'El catálogo tardó demasiado. Probá de nuevo.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Sin conexión: no pudimos consultar el catálogo.',
      );
    }

    final data = response.data;
    if (data is! Map) return const <Food>[];
    final raw = data['foods'] as List<dynamic>? ?? <dynamic>[];

    // Un alimento mal formado se saltea; el resto de la búsqueda sigue.
    final foods = <Food>[];
    for (final entry in raw) {
      try {
        foods.add(Food.fromJson(entry as Map<String, dynamic>));
      } on Object {
        continue;
      }
    }
    return foods;
  }

  static AppError _translate(FunctionException error) {
    final details = error.details;
    String? code;
    String? message;
    if (details is Map && details['error'] is Map) {
      final inner = details['error'] as Map;
      code = inner['code'] as String?;
      message = inner['message'] as String?;
    }
    return AppError(
      code: ApiErrorCode.values.firstWhere(
        (c) => c.wire == code,
        orElse: () => ApiErrorCode.upstreamFailed,
      ),
      message: message ?? 'No pudimos consultar el catálogo de alimentos.',
    );
  }
}
