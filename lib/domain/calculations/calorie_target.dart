import '../../core/error/app_error.dart';
import '../enums/enums.dart';
import 'rounding.dart';

/// Objetivo calórico base: déficit o superávit sobre el TDEE (§3).
class CalorieTargetResult {
  const CalorieTargetResult({
    required this.target,
    required this.clamped,
    required this.uncappedTarget,
    required this.minimum,
  });

  /// Valor final a usar (ya clampeado si hizo falta).
  final int target;

  /// Si el clamp de RN-12 actuó, la UI lo dice explícitamente.
  final bool clamped;

  /// El valor antes del clamp, para poder explicar el ajuste.
  final int uncappedTarget;
  final int minimum;

  String get clampNotice =>
      'Ajustamos tu objetivo al mínimo saludable de $minimum kcal.';
}

abstract final class CalorieTargetRules {
  /// Equivalente energético de 1 kg de grasa.
  static const double kcalPerKgOfFat = 7700;

  /// Tope de ritmo: 1 kg por semana (RN-13). No hay opción "agresiva".
  static const double maxRateKgPerWeek = 1.0;

  static const int absoluteMin = 800;
  static const int absoluteMax = 6000;

  /// Mínimos de RN-12 por sexo del perfil.
  static int minimumFor(BiologicalSex sex) => switch (sex) {
    BiologicalSex.female => 1200,
    BiologicalSex.male => 1500,
    BiologicalSex.unspecified => 1350,
  };

  /// Ajuste calórico diario de un ritmo semanal.
  static double dailyAdjustment(double rateKgPerWeek) =>
      rateKgPerWeek * kcalPerKgOfFat / 7;
}

/// ```
/// objetivoBase(lose)        = tdee − ajusteDiario
/// objetivoBase(gain)        = tdee + ajusteDiario × 0,5   (superávit conservador, D-04)
/// objetivoBase(gain_muscle) = tdee + ajusteDiario
/// objetivoBase(maintain)    = tdee
/// ```
///
/// `gain_muscle` usa el superávit completo y no la mitad: el recorte de D-04
/// existe para que subir de peso no sea subir grasa, y ahí el freno lo pone el
/// ritmo, que por defecto es 0,25 kg/semana (≈ 275 kcal). Recortarlo otra vez
/// dejaría un superávit tan chico que no alcanza para construir tejido.
CalorieTargetResult calorieTarget({
  required int tdee,
  required GoalType goalType,
  required double rateKgPerWeek,
  required BiologicalSex sex,
}) {
  if (tdee <= 0) {
    throw const CalculationError(
      'calorieTarget',
      'tdee',
      'debe ser mayor que cero',
    );
  }
  if (rateKgPerWeek < 0 || rateKgPerWeek > CalorieTargetRules.maxRateKgPerWeek) {
    throw const CalculationError(
      'calorieTarget',
      'rateKgPerWeek',
      'debe estar entre 0 y 1 kg por semana (RN-13)',
    );
  }

  final adjustment = CalorieTargetRules.dailyAdjustment(rateKgPerWeek);
  final raw = switch (goalType) {
    GoalType.lose => tdee - adjustment,
    // Medio superávit: un superávit completo se traduce mayormente en grasa (D-04).
    GoalType.gain => tdee + adjustment * 0.5,
    GoalType.gainMuscle => tdee + adjustment,
    GoalType.maintain => tdee.toDouble(),
  };

  final uncapped = roundHalfUp(raw);
  final minimum = CalorieTargetRules.minimumFor(sex);

  var target = uncapped;
  var clamped = false;
  if (target < minimum) {
    target = minimum;
    clamped = true;
  }
  if (target > CalorieTargetRules.absoluteMax) {
    target = CalorieTargetRules.absoluteMax;
    clamped = true;
  }

  return CalorieTargetResult(
    target: target,
    clamped: clamped,
    uncappedTarget: uncapped,
    minimum: minimum,
  );
}

/// Fecha estimada de llegada al peso objetivo con el ritmo elegido.
/// Devuelve `null` si el ritmo es 0 o el objetivo ya se alcanzó.
DateTime? estimatedArrivalDate({
  required double currentWeightKg,
  required double targetWeightKg,
  required double rateKgPerWeek,
  DateTime? from,
}) {
  if (rateKgPerWeek <= 0) return null;
  final delta = (currentWeightKg - targetWeightKg).abs();
  if (delta < 0.1) return null;
  final weeks = delta / rateKgPerWeek;
  final start = from ?? DateTime.now();
  return start.add(Duration(days: (weeks * 7).ceil()));
}
