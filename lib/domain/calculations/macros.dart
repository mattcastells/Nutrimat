import '../../core/error/app_error.dart';
import '../enums/enums.dart';
import 'rounding.dart';

/// Objetivos de macronutrientes en gramos.
class MacroTargets {
  const MacroTargets({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final int proteinG;
  final int carbsG;
  final int fatG;

  int get kcal => proteinG * 4 + carbsG * 4 + fatG * 9;
}

/// Calorías a partir de gramos de macronutriente (§4).
///
/// `kcal = proteína × 4 + carbohidrato × 4 + grasa × 9 (+ fibra × 2 + alcohol × 7)`
int kcalFromMacros({
  required double proteinG,
  required double carbsG,
  required double fatG,
  double? fiberG,
  double? alcoholG,
}) {
  final value =
      proteinG * 4 +
      carbsG * 4 +
      fatG * 9 +
      (fiberG ?? 0) * 2 +
      (alcoholG ?? 0) * 7;
  return roundHalfUp(value);
}

/// Consistencia macros ↔ calorías (§5). No bloquea el guardado.
///
/// `inconsistente = delta > 30 AND delta > kcalDeclaradas × 0,20`
bool macrosAreInconsistent({
  required int declaredKcal,
  required double proteinG,
  required double carbsG,
  required double fatG,
}) {
  final computed = kcalFromMacros(
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
  );
  final delta = (declaredKcal - computed).abs();
  return delta > 30 && delta > declaredKcal * 0.20;
}

/// Objetivos de macros por defecto (§19).
///
/// ```
/// proteínaG = round(1,6 × pesoKg)     (2,0 si goalType = 'lose')
/// grasaG    = round(objetivoKcal × 0,25 ÷ 9)
/// carbosG   = round((objetivoKcal − proteínaG×4 − grasaG×9) ÷ 4)
/// ```
/// Si `carbosG < 50`, se baja la proteína a 1,6 g/kg y se recalcula; si aún así
/// queda por debajo, se fija en 50 y se reduce la grasa. Nunca devuelve un
/// macro negativo.
MacroTargets macroTargets({
  required int targetKcal,
  required double weightKg,
  required GoalType goalType,
}) {
  if (targetKcal <= 0) {
    throw const CalculationError(
      'macroTargets',
      'targetKcal',
      'debe ser mayor que cero',
    );
  }
  if (weightKg <= 0) {
    throw const CalculationError(
      'macroTargets',
      'weightKg',
      'debe ser mayor que cero',
    );
  }

  final proteinPerKg = goalType == GoalType.lose ? 2.0 : 1.6;

  MacroTargets attempt(double gramsPerKg) {
    final protein = roundHalfUp(gramsPerKg * weightKg);
    final fat = roundHalfUp(targetKcal * 0.25 / 9);
    final carbs = roundHalfUp((targetKcal - protein * 4 - fat * 9) / 4);
    return MacroTargets(proteinG: protein, carbsG: carbs, fatG: fat);
  }

  var result = attempt(proteinPerKg);
  if (result.carbsG >= 50) return result;

  if (proteinPerKg != 1.6) {
    result = attempt(1.6);
    if (result.carbsG >= 50) return result;
  }

  // Último recurso: carbos fijos en 50 g, se reduce la grasa.
  const carbs = 50;
  final protein = result.proteinG;
  final remaining = targetKcal - protein * 4 - carbs * 4;
  final fat = remaining > 0 ? roundHalfUp(remaining / 9) : 0;
  return MacroTargets(proteinG: protein, carbsG: carbs, fatG: fat);
}
