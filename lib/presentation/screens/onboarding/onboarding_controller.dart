import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/calculations/bmr.dart';
import '../../../domain/calculations/calorie_target.dart';
import '../../../domain/calculations/macros.dart';
import '../../../domain/calculations/tdee.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/repositories/repositories.dart';

/// Los 6 pasos del onboarding (F-02). El wizard es lineal; cada paso puede
/// omitirse con "Después" salvo `body`, que es necesario para el BMR.
enum OnboardingStep {
  goal('goal', 'Tu objetivo'),
  body('body', 'Tus datos'),
  activityLevel('activity-level', 'Tu nivel de actividad'),
  target('target', 'Tu objetivo calórico'),
  exerciseCredit('exercise-credit', 'El ejercicio y tu presupuesto'),
  summary('summary', 'Todo listo');

  const OnboardingStep(this.slug, this.title);

  final String slug;
  final String title;

  int get number => index + 1;

  static OnboardingStep fromSlug(String? slug) =>
      values.firstWhere((s) => s.slug == slug, orElse: () => goal);

  OnboardingStep? get next =>
      index + 1 < values.length ? values[index + 1] : null;

  OnboardingStep? get previous => index > 0 ? values[index - 1] : null;
}

/// El cálculo en vivo que ve la persona en los pasos 4 y 6.
class OnboardingPreview {
  const OnboardingPreview({
    required this.bmr,
    required this.tdee,
    required this.target,
    required this.macros,
    required this.clamped,
    required this.minimum,
  });

  final int? bmr;
  final int? tdee;
  final int target;
  final MacroTargets macros;
  final bool clamped;
  final int minimum;
}

class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  void setGoalType(GoalType type) => state = state.copyWith(goalType: type);

  void setBody({
    BiologicalSex? sex,
    DateTime? birthDate,
    double? heightCm,
    double? weightKg,
  }) => state = state.copyWith(
    biologicalSex: sex,
    birthDate: birthDate,
    heightCm: heightCm,
    weightKg: weightKg,
  );

  void setActivityLevel(ActivityLevel level) =>
      state = state.copyWith(activityLevel: level);

  void setRate(double rate) => state = state.copyWith(rateKgPerWeek: rate);

  void setTargetMethod(TargetMethod method) =>
      state = state.copyWith(targetMethod: method);

  void setManualTarget(int? value) => state = value == null
      ? state.copyWith(clearManualTarget: true)
      : state.copyWith(manualTarget: value);

  void setCredit(int percentage) =>
      state = state.copyWith(exerciseCreditPercentage: percentage);

  void setTargetWeight(double? kg) =>
      state = state.copyWith(targetWeightKg: kg);

  /// Recalcula BMR → TDEE → objetivo → macros con lo cargado hasta ahora.
  OnboardingPreview preview() {
    final draft = state;
    final weightKg = draft.weightKg ?? 70;
    final goalType = draft.goalType ?? GoalType.maintain;
    final sex = draft.biologicalSex ?? BiologicalSex.unspecified;

    int? bmrValue;
    int? tdeeValue;
    var target = draft.manualTarget ?? 2000;
    var clamped = false;
    final minimum = CalorieTargetRules.minimumFor(sex);

    if (draft.hasBody) {
      bmrValue = bmrMifflinStJeor(
        weightKg: weightKg,
        heightCm: draft.heightCm!,
        ageYears: ageFromBirthDate(draft.birthDate!),
        sex: sex,
      );
      tdeeValue = tdee(
        bmr: bmrValue,
        activityLevel: draft.activityLevel ?? ActivityLevel.moderate,
      );
      if (draft.targetMethod == TargetMethod.calculated) {
        final result = calorieTarget(
          tdee: tdeeValue,
          goalType: goalType,
          rateKgPerWeek: goalType == GoalType.maintain
              ? 0
              : draft.rateKgPerWeek,
          sex: sex,
        );
        target = result.target;
        clamped = result.clamped;
      }
    }

    return OnboardingPreview(
      bmr: bmrValue,
      tdee: tdeeValue,
      target: target,
      macros: macroTargets(
        targetKcal: target,
        weightKg: weightKg,
        goalType: goalType,
      ),
      clamped: clamped,
      minimum: minimum,
    );
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingController, OnboardingDraft>(
      OnboardingController.new,
    );
