import 'exercise_credit.dart';

/// Balance calórico del día (§13). ★
///
/// El objetivo base **nunca** se modifica por el ejercicio (RN-01): el ajuste
/// produce un `adjustedTarget` derivado que se muestra junto al base.
class DailyBalance {
  const DailyBalance({
    required this.baseTarget,
    required this.consumedKcal,
    required this.exerciseEstimatedKcal,
    required this.exerciseAppliedKcal,
    required this.creditPercentage,
    required this.creditEnabled,
  });

  final int baseTarget;
  final int consumedKcal;
  final int exerciseEstimatedKcal;
  final int exerciseAppliedKcal;
  final int creditPercentage;
  final bool creditEnabled;

  /// `objetivoAjustado = objetivoBase + caloríasEjercicioAplicadas`
  int get adjustedTarget => baseTarget + exerciseAppliedKcal;

  /// `caloríasRestantes = objetivoAjustado − caloríasConsumidas`.
  /// Puede ser negativo: "Te pasaste por N kcal" (nunca en rojo, D-17).
  int get remainingKcal => adjustedTarget - consumedKcal;

  /// `caloríasNetas = consumidas − aplicadas`. Solo se muestra donde
  /// autoriza RN-11 (Progreso y detalle del día).
  int get netKcal => consumedKcal - exerciseAppliedKcal;

  bool get isOverBudget => remainingKcal < 0;

  int get overBudgetKcal => isOverBudget ? -remainingKcal : 0;

  /// Fracción consumida del objetivo ajustado, sin tope (puede pasar de 1).
  double get consumedFraction =>
      adjustedTarget <= 0 ? 0 : consumedKcal / adjustedTarget;

  /// La fila "Ajuste aplicado" se oculta con crédito 0 % o desactivado (D-02).
  bool get showsAdjustmentRow => creditEnabled && creditPercentage > 0;
}

/// Construye el balance aplicando el crédito vigente.
DailyBalance computeDailyBalance({
  required int baseTarget,
  required int consumedKcal,
  required int exerciseEstimatedKcal,
  required int creditPercentage,
  required bool creditEnabled,
  int? preAppliedKcal,
}) {
  // Las actividades ya guardan sus `applied_calories` con el porcentaje
  // congelado (D-05); si vienen sumadas, se respetan.
  final applied =
      preAppliedKcal ??
      calculateAppliedExerciseCalories(
        estimatedCalories: exerciseEstimatedKcal,
        creditPercentage: creditPercentage,
        creditEnabled: creditEnabled,
      );

  return DailyBalance(
    baseTarget: baseTarget,
    consumedKcal: consumedKcal,
    exerciseEstimatedKcal: exerciseEstimatedKcal,
    exerciseAppliedKcal: creditEnabled ? applied : 0,
    creditPercentage: creditPercentage,
    creditEnabled: creditEnabled,
  );
}

/// `objetivoAjustado = base + aplicadas` (expuesto suelto para los tests).
int calculateAdjustedCalorieTarget({
  required int baseTarget,
  required int appliedExerciseCalories,
}) => baseTarget + appliedExerciseCalories;

/// `restantes = objetivoAjustado − consumidas`.
int calculateRemainingCalories({
  required int adjustedTarget,
  required int consumedKcal,
}) => adjustedTarget - consumedKcal;

/// `netas = consumidas − aplicadas` (RN-11).
int calculateNetCalories({
  required int consumedKcal,
  required int appliedExerciseCalories,
}) => consumedKcal - appliedExerciseCalories;
