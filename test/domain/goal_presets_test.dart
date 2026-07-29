import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:nutrimat/domain/calculations/calorie_target.dart';
import 'package:nutrimat/domain/calculations/goal_presets.dart';
import 'package:nutrimat/domain/calculations/macros.dart';
import 'package:nutrimat/domain/enums/enums.dart';
import 'package:nutrimat/domain/models/activity.dart';
import 'package:nutrimat/domain/models/user_profile.dart';
import 'package:nutrimat/domain/services/goal_planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Perfil con lo justo para que Mifflin-St Jeor tenga con qué trabajar.
UserProfile _profileConDatos() => UserProfile.empty('u1').copyWith(
  biologicalSex: BiologicalSex.male,
  birthDate: DateTime(1990, 1, 1),
  heightCm: 178,
  activityLevel: ActivityLevel.moderate,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('presets', () {
    test('cada tipo de objetivo tiene el suyo y ninguno se repite', () {
      expect(GoalPreset.all, hasLength(GoalType.values.length));
      for (final type in GoalType.values) {
        expect(GoalPreset.of(type).goalType, type);
      }
    });

    test('ningún ritmo supera el tope de 1 kg por semana (RN-13)', () {
      for (final preset in GoalPreset.all) {
        expect(
          preset.rateKgPerWeek,
          lessThanOrEqualTo(CalorieTargetRules.maxRateKgPerWeek),
        );
      }
    });

    test('mantener no tiene ritmo', () {
      expect(GoalPreset.maintain.rateKgPerWeek, 0);
    });

    test('bajar y ganar músculo piden más proteína', () {
      expect(GoalPreset.lose.proteinGPerKg, 2.0);
      expect(GoalPreset.gainMuscle.proteinGPerKg, 2.0);
      expect(GoalPreset.maintain.proteinGPerKg, 1.6);
      expect(GoalPreset.gain.proteinGPerKg, 1.6);
    });

    test('los macros usan el mismo g/kg que el preset', () {
      for (final preset in GoalPreset.all) {
        final macros = macroTargets(
          targetKcal: 2400,
          weightKg: 80,
          goalType: preset.goalType,
        );
        expect(macros.proteinG, preset.proteinTargetG(80));
      }
    });
  });

  group('objetivo calórico por tipo', () {
    const tdeeValue = 2500;

    int targetOf(GoalType type) {
      final preset = GoalPreset.of(type);
      return calorieTarget(
        tdee: tdeeValue,
        goalType: type,
        rateKgPerWeek: preset.rateKgPerWeek,
        sex: BiologicalSex.male,
      ).target;
    }

    test('bajar resta el ajuste completo', () {
      expect(targetOf(GoalType.lose), tdeeValue - 550);
    });

    test('mantener deja el gasto tal cual', () {
      expect(targetOf(GoalType.maintain), tdeeValue);
    });

    test('subir de peso aplica medio superávit (D-04)', () {
      // 0,25 kg/semana ≈ 275 kcal, la mitad ≈ 138.
      expect(targetOf(GoalType.gain), tdeeValue + 138);
    });

    test('ganar músculo aplica el superávit entero', () {
      expect(targetOf(GoalType.gainMuscle), tdeeValue + 275);
    });

    test('ganar músculo queda por encima de subir de peso', () {
      expect(targetOf(GoalType.gainMuscle), greaterThan(targetOf(GoalType.gain)));
    });
  });

  group('GoalPlanner', () {
    test('con datos corporales el objetivo queda calculado', () {
      final goal = GoalPlanner.build(
        preset: GoalPreset.lose,
        profile: _profileConDatos(),
        weightKg: 82,
        current: null,
      );

      expect(goal.goalType, GoalType.lose);
      expect(goal.rateKgPerWeek, 0.5);
      expect(goal.targetMethod, TargetMethod.calculated);
      expect(goal.bmrKcal, isNotNull);
      expect(goal.tdeeKcal, isNotNull);
      expect(goal.baseCalorieTarget, goal.tdeeKcal! - 550);
      expect(goal.startsOn, today());
    });

    test('sin datos corporales conserva el número y lo marca manual (RN-03)', () {
      final planned = GoalPlanner.build(
        preset: GoalPreset.gainMuscle,
        profile: UserProfile.empty('u1'),
        weightKg: null,
        current: null,
      );

      expect(planned.targetMethod, TargetMethod.manual);
      expect(planned.bmrKcal, isNull);
      // El tipo y el ritmo sí se guardan: es lo que se pudo saber.
      expect(planned.goalType, GoalType.gainMuscle);
      expect(planned.rateKgPerWeek, 0.25);
    });

    test('el objetivo nunca baja del mínimo saludable (RN-12)', () {
      final goal = GoalPlanner.build(
        preset: GoalPreset.lose,
        profile: _profileConDatos().copyWith(
          biologicalSex: BiologicalSex.female,
          activityLevel: ActivityLevel.sedentary,
          heightCm: 150,
        ),
        weightKg: 45,
        current: null,
      );

      expect(
        goal.baseCalorieTarget,
        greaterThanOrEqualTo(
          CalorieTargetRules.minimumFor(BiologicalSex.female),
        ),
      );
    });

    test('los objetivos de actividad salen del preset y no se duplican', () {
      final goals = GoalPlanner.activityGoals(
        GoalPreset.gainMuscle,
        existing: const <ActivityGoal>[],
      );

      expect(goals, hasLength(2));
      expect(
        goals.firstWhere((g) => g.goalType == ActivityGoalType.activeMinutes)
            .targetValue,
        150,
      );
      expect(
        goals
            .firstWhere((g) => g.goalType == ActivityGoalType.strengthSessions)
            .targetValue,
        4,
      );
      expect(goals.every((g) => g.period == GoalPeriod.week), isTrue);
    });

    test('reusa el id del objetivo de actividad que ya existía', () {
      final previos = GoalPlanner.activityGoals(
        GoalPreset.maintain,
        existing: const <ActivityGoal>[],
      );
      final nuevos = GoalPlanner.activityGoals(
        GoalPreset.lose,
        existing: previos,
      );

      expect(
        nuevos.map((g) => g.id).toSet(),
        previos.map((g) => g.id).toSet(),
      );
      expect(
        nuevos.firstWhere((g) => g.goalType == ActivityGoalType.activeMinutes)
            .targetValue,
        200,
      );
    });
  });

  group('guardar el objetivo', () {
    late LocalRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await LocalStore.open();
      repo = LocalRepository(store, onChanged: () {});
      await repo.signIn('yo@nutrimat.test');
    });

    test('cambiar de objetivo cierra el anterior y deja uno solo vigente',
        () async {
      await repo.saveGoal(
        GoalPlanner.build(
          preset: GoalPreset.lose,
          profile: _profileConDatos(),
          weightKg: 82,
          current: repo.currentGoalOrNull,
        ),
      );
      await repo.saveGoal(
        GoalPlanner.build(
          preset: GoalPreset.gainMuscle,
          profile: _profileConDatos(),
          weightKg: 82,
          current: repo.currentGoalOrNull,
        ),
      );

      expect(repo.currentGoalOrNull?.goalType, GoalType.gainMuscle);
      expect(repo.goalFor(today()).goalType, GoalType.gainMuscle);
    });
  });
}
