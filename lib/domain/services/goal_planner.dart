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
  ///
  /// [pace] pisa el ritmo del preset. El preset es el punto de partida, no la
  /// única opción: quien eligió "De a poco" en el alta tiene que terminar con
  /// ese ritmo guardado y no con el "Sostenido" de la tarjeta.
  ///
  /// El ritmo es una fracción del gasto, así que los kilos por semana que
  /// quedan guardados **salen de los datos de la persona**: el mismo "De a
  /// poco" es 0,22 kg/semana para un gasto de 2.400 y 0,14 para uno de 1.550.
  /// Sin datos corporales no hay gasto del que sacar una fracción, y ahí el
  /// único ritmo posible es el de referencia del preset.
  ///
  /// [manualTarget] pisa el resultado de la fórmula. El BMR y el TDEE se
  /// guardan igual: son hechos que salen de los datos del cuerpo, y sirven para
  /// explicar después de dónde se apartó el número elegido. [manualMethod]
  /// distingue quién lo escribió — la persona o la IA (S-05).
  static Goal build({
    required GoalPreset preset,
    required UserProfile profile,
    required double? weightKg,
    required Goal? current,
    GoalPace? pace,
    int? manualTarget,
    TargetMethod manualMethod = TargetMethod.manual,
  }) {
    final canCalculate = profile.hasBodyData && weightKg != null;

    // Mantener no tiene ritmo. Aceptar uno acá dejaría un objetivo que dice
    // "mantener" y resta calorías.
    var rate = preset.goalType == GoalType.maintain
        ? 0.0
        : preset.rateKgPerWeek;

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
      final planned = calorieTargetForPace(
        tdee: tdeeValue,
        goalType: preset.goalType,
        fractionOfTdee: (pace ?? preset.defaultPace).fractionFor(
          preset.goalType,
        ),
        sex: profile.biologicalSex,
      );
      target = planned.target.target;
      rate = planned.rateKgPerWeek;
      method = TargetMethod.calculated;
    }

    if (manualTarget != null) {
      target = manualTarget;
      method = manualMethod;
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
      rateKgPerWeek: rate,
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
