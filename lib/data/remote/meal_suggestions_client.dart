import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/meal_suggestion.dart';

/// Llama a la Edge Function `suggest-meals`.
///
/// Igual que las de estimación: la app no habla con Gemini, le pasa el
/// presupuesto a la función y la clave nunca baja al teléfono.
class MealSuggestionsClient {
  MealSuggestionsClient(this._functions);

  factory MealSuggestionsClient.fromInstance() =>
      MealSuggestionsClient(Supabase.instance.client.functions);

  final FunctionsClient _functions;

  static const String functionName = 'suggest-meals';

  /// La función se corta sola a los 25 s contra Gemini; esto cubre eso más la
  /// red. Sin timeout propio, una función que muere deja la pantalla girando
  /// para siempre, sin error y sin forma de salir.
  static const Duration timeout = Duration(seconds: 45);

  /// Abajo de esto ni se pregunta.
  ///
  /// Está repetido del lado del servidor a propósito: el servidor tiene que
  /// defenderse igual de un cliente viejo, y el cliente no tiene por qué gastar
  /// un viaje —ni una unidad de cuota— para que le contesten que no.
  static const int minBudgetKcal = 150;

  /// Tres comidas que entran en [remainingKcal].
  Future<List<MealSuggestion>> suggest({
    required int remainingKcal,
    MealSlot? slot,
    int? remainingProteinG,
  }) async {
    final FunctionResponse response;
    try {
      response = await _functions
          .invoke(
            functionName,
            body: <String, dynamic>{
              'remainingKcal': remainingKcal,
              if (slot != null) 'slot': slot.label,
              if (remainingProteinG != null && remainingProteinG > 0)
                'remainingProteinG': remainingProteinG,
            },
          )
          .timeout(timeout);
    } on FunctionException catch (error) {
      throw _translate(error);
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'Las sugerencias tardaron demasiado. Probá de nuevo.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'No pudimos pedir sugerencias: revisá tu conexión.',
      );
    }

    return parse(response.data, budgetKcal: remainingKcal);
  }

  /// Lee la respuesta y **vuelve a comprobar el presupuesto**.
  ///
  /// El servidor ya descarta lo que no entra; esto lo hace de nuevo del lado del
  /// teléfono. No es desconfianza del código de al lado: es que este es el
  /// último lugar antes de que un número llegue a los ojos de alguien, y la
  /// regla —"nunca sugerir algo que no entra"— es de las que no se delegan.
  /// Público para poder probarlo sin servidor de por medio.
  static List<MealSuggestion> parse(
    dynamic data, {
    required int budgetKcal,
  }) {
    if (data is! Map) return const <MealSuggestion>[];
    final raw = data['options'];
    if (raw is! List) return const <MealSuggestion>[];

    final out = <MealSuggestion>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final option = MealSuggestion.fromJson(Map<String, dynamic>.from(entry));
      if (option == null) continue;
      if (option.kcal > budgetKcal) continue;

      // Y que el total sea de verdad la suma de sus partes. Si no lo es, uno de
      // los dos números miente y no hay forma de saber cuál: se descarta.
      final suma = option.items.fold<int>(0, (acc, i) => acc + i.kcal);
      if ((suma - option.kcal).abs() > 40) continue;
      if (suma > budgetKcal) continue;

      out.add(option);
    }
    return out;
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

    final apiCode = ApiErrorCode.values.firstWhere(
      (c) => c.wire == code,
      orElse: () => ApiErrorCode.upstreamFailed,
    );

    return AppError(
      code: apiCode,
      message: message ?? 'No pudimos traer sugerencias. Probá de nuevo.',
    );
  }
}
