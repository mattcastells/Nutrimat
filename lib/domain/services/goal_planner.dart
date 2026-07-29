import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/dates.dart';
import '../calculations/bmr.dart';
import '../calculations/calorie_target.dart';
import '../calculations/goal_presets.dart';
import '../calculations/macros.dart';
import '../calculations/tdee.dart';
import '../enums/enums.dart';
import '../models/activity.dart';
import '../models/goal.dart';
import '../models/user_profile.dart';

const _uuid = Uuid();

/// Traduce "quiero bajar de peso" a la configuración concreta de la app.
///
/// Elegir un objetivo no cambia una etiqueta: fija el ritmo, recalcula las
/// calorías y los macros, y deja puestos los objetivos de actividad semanal.
/// Todo eso queda editable después; esto es el punto de partida.
abstract final class GoalPlanner {
  /// El objetivo calórico que corresponde a [preset].
  ///
  /// Con datos corporales sale de Mifflin-St Jeor → TDEE → ajuste por ritmo.
  /// Sin ellos no hay fórmula posible: se conserva el número que ya había y se
  /// marca `manual`, porque presentar un valor inventado como si fuera el
  /// resultado de un cálculo es exactamente lo que el producto no hace (RN-03).
  static Goal build({
    required GoalPreset preset,
    required UserProfile profile,
    required double? weightKg,
    required Goal? current,
  }) {
    final canCalculate = profile.hasBodyData && weightKg != null;

    int? bmrValue;
    int? tdeeValue;
    var target = current?.baseCalorieTarget ?? 2000;
    var method = TargetMethod.manual;

    if (canCalculate) {
      bmrValue = bmrMifflinStJeor(
        weightKg: weightKg,
        heightCm: profile.heightCm!,
        ageYears: ageFromBirthDate(profile.birthDate!),
        sex: profile.biologicalSex,
      );
      tdeeValue = tdee(bmr: bmrValue, activityLevel: profile.activityLevel);
      target = calorieTarget(
        tdee: tdeeValue,
        goalType: preset.goalType,
        rateKgPerWeek: preset.rateKgPerWeek,
        sex: profile.biologicalSex,
      ).target;
      method = TargetMethod.calculated;
    }

    // Los macros necesitan un peso; sin registro se usa el de referencia solo
    // para repartir el objetivo, no para mostrarlo como dato de nadie.
    final macros = macroTargets(
      targetKcal: target,
      weightKg: weightKg ?? 70,
      goalType: preset.goalType,
    );

    return Goal(
      id: _uuid.v4(),
      goalType: preset.goalType,
      rateKgPerWeek: preset.rateKgPerWeek,
      targetWeightKg: current?.targetWeightKg,
      baseCalorieTarget: target,
      targetMethod: method,
      bmrKcal: bmrValue,
      tdeeKcal: tdeeValue,
      proteinG: macros.proteinG,
      carbsG: macros.carbsG,
      fatG: macros.fatG,
      macroMethod: 'default',
      startsOn: today(),
    );
  }

  /// Objetivos de actividad del preset, respetando los ids ya existentes para
  /// no dejar duplicados del mismo tipo.
  static List<ActivityGoal> activityGoals(
    GoalPreset preset, {
    required List<ActivityGoal> existing,
  }) {
    ActivityGoal upsert(ActivityGoalType type, int value) {
      final match = existing.where((g) => g.goalType == type).firstOrNull;
      return match == null
          ? ActivityGoal(
              id: _uuid.v4(),
              goalType: type,
              targetValue: value,
              period: GoalPeriod.week,
              startDate: today(),
            )
          : match.copyWith(
              targetValue: value,
              period: GoalPeriod.week,
              enabled: true,
            );
    }

    return <ActivityGoal>[
      upsert(ActivityGoalType.activeMinutes, preset.activeMinutesPerWeek),
      upsert(
        ActivityGoalType.strengthSessions,
        preset.strengthSessionsPerWeek,
      ),
    ];
  }
}
