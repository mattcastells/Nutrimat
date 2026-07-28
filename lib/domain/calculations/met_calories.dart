import '../../core/error/app_error.dart';
import 'rounding.dart';

abstract final class MetRanges {
  static const double minMet = 0.9;
  static const double maxMet = 23.0;
  static const int minDurationMinutes = 1;

  /// Sin tope práctico en la UI: el límite es el del modelo, un día (D-22).
  static const int maxDurationMinutes = 1440;

  /// Por encima de este valor la UI pide confirmar la duración, sin bloquear.
  static const int longSessionThresholdMinutes = 240;
}

/// Estimación de gasto por MET (§8). ★
///
/// ```
/// caloriasActividad = MET × 3,5 × pesoKg ÷ 200 × duracionMinutos
/// ```
///
/// Redondeo `round_half_up` al entero, **una sola vez**, al final.
/// Ejemplo canónico: 100 kg · MET 3,5 · 30 min → 184 kcal.
int calculateCaloriesFromMet({
  required double met,
  required double weightKg,
  required int durationMinutes,
}) {
  if (met < MetRanges.minMet || met > MetRanges.maxMet) {
    throw const CalculationError(
      'calculateCaloriesFromMet',
      'met',
      'debe estar entre 0,9 y 23,0',
    );
  }
  if (weightKg < 25 || weightKg > 400) {
    throw const CalculationError(
      'calculateCaloriesFromMet',
      'weightKg',
      'debe estar entre 25 y 400 kg',
    );
  }
  if (durationMinutes < MetRanges.minDurationMinutes ||
      durationMinutes > MetRanges.maxDurationMinutes) {
    throw const CalculationError(
      'calculateCaloriesFromMet',
      'durationMinutes',
      'debe estar entre 1 y 1440 minutos',
    );
  }

  final caloriesPerMinute = met * 3.5 * weightKg / 200;
  return roundHalfUp(caloriesPerMinute * durationMinutes);
}

/// Gasto informado por un proveedor (§10 y RN-05).
///
/// `activeCalories` es inválido si es nulo, ≤ 0, o si su tasa supera
/// 1500 kcal/hora — casi siempre un error de unidad del proveedor.
bool providerCaloriesAreValid({
  required int? activeCalories,
  required int durationMinutes,
}) {
  if (activeCalories == null || activeCalories <= 0) return false;
  if (durationMinutes <= 0) return false;
  final perHour = activeCalories / durationMinutes * 60;
  return perHour <= 1500;
}
