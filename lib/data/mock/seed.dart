import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../core/utils/dates.dart';
import '../../domain/calculations/bmr.dart';
import '../../domain/calculations/calorie_target.dart';
import '../../domain/calculations/exercise_credit.dart';
import '../../domain/calculations/macros.dart';
import '../../domain/calculations/met_calories.dart';
import '../../domain/calculations/tdee.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/body.dart';
import '../../domain/models/food.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/meal.dart';
import '../../domain/models/user_profile.dart';

/// Datos simulados realistas (fase `mock` del roadmap, `data/mock/`).
///
/// El día en curso trae 3 comidas y 2 actividades; hacia atrás se generan 30
/// días de historial con una semilla fija, para que la app se vea igual en
/// cada arranque y los goldens sean estables.
class SeedData {
  const SeedData({
    required this.profile,
    required this.goal,
    required this.meals,
    required this.activities,
    required this.weightLogs,
    required this.measurements,
    required this.activityGoals,
    required this.templates,
    required this.restDays,
    required this.userFoods,
  });

  final UserProfile profile;
  final Goal goal;
  final List<Meal> meals;
  final List<Activity> activities;
  final List<WeightLog> weightLogs;
  final List<BodyMeasurement> measurements;
  final List<ActivityGoal> activityGoals;
  final List<ExerciseTemplate> templates;
  final Set<String> restDays;
  final List<Food> userFoods;
}

const _uuid = Uuid();

/// El id del perfil sembrado.
///
/// Es la marca que deja la siembra en el documento guardado, y por eso es una
/// constante y no un literal suelto: un teléfono que ya tiene estos datos de
/// otra versión se reconoce por acá y se limpia al arrancar
/// (`LocalStore._loadOrSeed`).
const String demoProfileId = 'demo-user';

/// Peso de referencia del perfil sembrado: 100 kg, el del ejemplo canónico de
/// MET del brief (caminata moderada 30 min → 184 kcal).
const double _seedWeightKg = 100.0;
const double _seedHeightCm = 178;

SeedData buildSeed({
  required List<ActivityType> types,
  required List<Food> catalog,
}) {
  final rnd = math.Random(42);
  final now = DateTime.now();
  final todayDate = dateOnly(now);
  final birthDate = DateTime(now.year - 36, 4, 12);

  final profile = UserProfile(
    id: demoProfileId,
    displayName: 'Camila',
    biologicalSex: BiologicalSex.male,
    birthDate: birthDate,
    heightCm: _seedHeightCm,
    activityLevel: ActivityLevel.light,
    timezone: 'America/Argentina/Buenos_Aires',
    unitSystem: UnitSystem.metric,
    themeMode: ThemeModeSetting.system,
    locale: 'es',
    // 0 % por defecto: el ejercicio no suma al presupuesto (D-02).
    exerciseCreditPercentage: ExerciseCreditOptions.defaultPercentage,
    exerciseCreditEnabled: true,
    showNetCalories: false,
    isDemo: true,
    createdAt: todayDate.subtract(const Duration(days: 30)),
    updatedAt: now,
  );

  final bmr = bmrMifflinStJeor(
    weightKg: _seedWeightKg,
    heightCm: _seedHeightCm,
    ageYears: ageFromBirthDate(birthDate, on: now),
    sex: profile.biologicalSex,
  );
  final tdeeValue = tdee(bmr: bmr, activityLevel: profile.activityLevel);
  final target = calorieTarget(
    tdee: tdeeValue,
    goalType: GoalType.lose,
    rateKgPerWeek: 0.5,
    sex: profile.biologicalSex,
  );
  final macros = macroTargets(
    targetKcal: target.target,
    weightKg: _seedWeightKg,
    goalType: GoalType.lose,
  );

  final goal = Goal(
    id: _uuid.v4(),
    goalType: GoalType.lose,
    rateKgPerWeek: 0.5,
    targetWeightKg: 92,
    baseCalorieTarget: target.target,
    targetMethod: TargetMethod.calculated,
    bmrKcal: bmr,
    tdeeKcal: tdeeValue,
    proteinG: macros.proteinG,
    carbsG: macros.carbsG,
    fatG: macros.fatG,
    macroMethod: 'default',
    startsOn: todayDate.subtract(const Duration(days: 30)),
  );

  Food food(String id) => catalog.firstWhere((f) => f.id == id);
  ActivityType type(String slug) => types.firstWhere((t) => t.slug == slug);

  final meals = <Meal>[];
  final activities = <Activity>[];
  final weightLogs = <WeightLog>[];

  // ── El día en curso ────────────────────────────────────────────────────
  meals
    ..add(
      _meal(
        slot: MealSlot.breakfast,
        at: DateTime(now.year, now.month, now.day, 8, 20),
        items: <MealItem>[
          _item(food('usda:1750351'), 1, '1 taza', 0),
          _item(food('usda:1750340'), 1, '1 porción', 1),
          _item(food('usda:1750341'), 1, '1 unidad mediana', 2),
        ],
      ),
    )
    ..add(
      _meal(
        slot: MealSlot.lunch,
        at: DateTime(now.year, now.month, now.day, 13, 5),
        items: <MealItem>[
          _item(food('usda:1750347'), 1, '1 unidad', 0),
          _item(food('usda:1750348'), 1, '1 porción', 1),
          _item(food('usda:1750349'), 1, '1 plato', 2),
        ],
      ),
    )
    ..add(
      _meal(
        slot: MealSlot.snack,
        at: DateTime(now.year, now.month, now.day, 17, 30),
        items: <MealItem>[
          _item(food('off:7790070410016'), 1, '1 pote', 0),
          _item(food('usda:1750353'), 1, '1 puñado', 1),
        ],
      ),
    );

  activities
    ..add(
      _activity(
        type: type('walking'),
        startedAt: DateTime(now.year, now.month, now.day, 7, 30),
        durationMinutes: 30,
        intensity: Intensity.moderate,
        creditPercentage: profile.effectiveCreditPercentage,
        distanceMeters: 2600,
        steps: 3480,
      ),
    )
    ..add(
      _activity(
        type: type('strength_training'),
        startedAt: DateTime(now.year, now.month, now.day, 19, 0),
        durationMinutes: 25,
        intensity: Intensity.moderate,
        creditPercentage: profile.effectiveCreditPercentage,
        customName: 'Tren superior',
      ),
    );

  // ── 30 días de historial ───────────────────────────────────────────────
  const breakfastPool = <String>[
    'usda:1750351',
    'usda:1750340',
    'usda:1750341',
    'usda:1750345',
    'off:7790070410016',
  ];
  const lunchPool = <String>[
    'usda:1750342',
    'usda:1750343',
    'usda:1750349',
    'usda:1750355',
    'usda:1750356',
    'usda:1750357',
    'usda:1750358',
  ];
  const dinnerPool = <String>[
    'usda:1750359',
    'usda:1750354',
    'usda:1750346',
    'usda:1750344',
    'usda:1750349',
  ];
  const snackPool = <String>[
    'usda:1750352',
    'usda:1750353',
    'off:7790895000997',
    'off:7790040999008',
    'off:7622210449283',
  ];

  final restDays = <String>{};
  var weight = 101.6;

  for (var back = 30; back >= 1; back--) {
    final day = todayDate.subtract(Duration(days: back));

    // Un día sin registro cada tanto: el historial real tiene huecos.
    final skipped = rnd.nextInt(10) == 0;
    if (!skipped) {
      meals
        ..add(
          _meal(
            slot: MealSlot.breakfast,
            at: DateTime(day.year, day.month, day.day, 8, 15),
            items: _pick(rnd, breakfastPool, catalog, 2),
          ),
        )
        ..add(
          _meal(
            slot: MealSlot.lunch,
            at: DateTime(day.year, day.month, day.day, 13, 0),
            items: _pick(rnd, lunchPool, catalog, 3),
          ),
        )
        ..add(
          _meal(
            slot: MealSlot.dinner,
            at: DateTime(day.year, day.month, day.day, 21, 15),
            items: _pick(rnd, dinnerPool, catalog, 2),
          ),
        );
      if (rnd.nextBool()) {
        meals.add(
          _meal(
            slot: MealSlot.snack,
            at: DateTime(day.year, day.month, day.day, 17, 0),
            items: _pick(rnd, snackPool, catalog, 1),
          ),
        );
      }
    }

    // Actividad: 4 de cada 7 días, con algún descanso planificado.
    final roll = rnd.nextInt(10);
    if (roll < 5 && !skipped) {
      final slug = const <String>[
        'walking',
        'running',
        'cycling',
        'strength_training',
        'yoga',
        'sports',
      ][rnd.nextInt(6)];
      final t = type(slug);
      final duration = <int>[20, 30, 35, 45, 50, 60][rnd.nextInt(6)];
      final intensity =
          Intensity.values[rnd.nextInt(Intensity.values.length)];
      activities.add(
        _activity(
          type: t,
          startedAt: DateTime(day.year, day.month, day.day, 7 + rnd.nextInt(12)),
          durationMinutes: duration,
          intensity: intensity,
          creditPercentage: profile.effectiveCreditPercentage,
          distanceMeters: t.supportsDistance
              ? (duration * (60 + rnd.nextInt(180)))
              : null,
          steps: t.supportsSteps ? duration * (95 + rnd.nextInt(40)) : null,
        ),
      );
    } else if (roll == 9) {
      restDays.add(isoDate(day));
    }

    // Peso: tendencia a la baja con ruido; no todos los días hay registro.
    weight -= 0.055;
    if (back % 2 == 0 || rnd.nextInt(3) == 0) {
      weightLogs.add(
        WeightLog(
          id: _uuid.v4(),
          weightKg: double.parse(
            (weight + (rnd.nextDouble() - 0.5) * 0.6).toStringAsFixed(1),
          ),
          localDate: day,
          loggedAt: DateTime(day.year, day.month, day.day, 7, 40),
        ),
      );
    }
  }

  weightLogs.add(
    WeightLog(
      id: _uuid.v4(),
      weightKg: _seedWeightKg,
      localDate: todayDate,
      loggedAt: DateTime(now.year, now.month, now.day, 7, 35),
    ),
  );

  final measurements = <BodyMeasurement>[
    for (var i = 4; i >= 0; i--)
      BodyMeasurement(
        id: _uuid.v4(),
        metric: MeasurementMetric.waist,
        value: 98.5 - i * 0.6,
        localDate: todayDate.subtract(Duration(days: i * 7)),
      ),
  ];

  final activityGoals = <ActivityGoal>[
    ActivityGoal(
      id: _uuid.v4(),
      goalType: ActivityGoalType.activeMinutes,
      targetValue: 150,
      period: GoalPeriod.week,
      startDate: todayDate.subtract(const Duration(days: 30)),
    ),
    ActivityGoal(
      id: _uuid.v4(),
      goalType: ActivityGoalType.sessions,
      targetValue: 4,
      period: GoalPeriod.week,
      startDate: todayDate.subtract(const Duration(days: 30)),
    ),
  ];

  final templates = <ExerciseTemplate>[
    ExerciseTemplate(
      id: _uuid.v4(),
      name: 'Caminata al parque',
      activityTypeId: type('walking').id,
      defaultDurationMinutes: 45,
      defaultIntensity: Intensity.moderate,
      defaultDistanceMeters: 4000,
      useCount: 6,
    ),
    ExerciseTemplate(
      id: _uuid.v4(),
      name: 'Full body en el gimnasio',
      activityTypeId: type('strength_training').id,
      defaultDurationMinutes: 50,
      defaultIntensity: Intensity.vigorous,
      useCount: 3,
    ),
  ];

  final userFoods = <Food>[
    const Food(
      id: 'user-tarta-verdura',
      userId: demoProfileId,
      name: 'Tarta de verdura casera',
      source: FoodSource.user,
      servingSize: 1,
      servingUnit: 'porción',
      kcal: 265,
      proteinG: 11.5,
      carbsG: 24.0,
      fatG: 13.5,
      portions: <FoodPortion>[FoodPortion(label: '1 porción', grams: 180)],
    ),
    const Food(
      id: 'user-licuado',
      userId: demoProfileId,
      name: 'Licuado de banana y avena',
      source: FoodSource.user,
      servingSize: 350,
      servingUnit: 'ml',
      kcal: 310,
      proteinG: 12.0,
      carbsG: 52.0,
      fatG: 6.0,
      isFavorite: true,
      portions: <FoodPortion>[FoodPortion(label: '1 vaso', grams: 350)],
    ),
  ];

  return SeedData(
    profile: profile,
    goal: goal,
    meals: meals,
    activities: activities,
    weightLogs: weightLogs,
    measurements: measurements,
    activityGoals: activityGoals,
    templates: templates,
    restDays: restDays,
    userFoods: userFoods,
  );
}

List<MealItem> _pick(
  math.Random rnd,
  List<String> pool,
  List<Food> catalog,
  int count,
) {
  final ids = <String>{};
  while (ids.length < count && ids.length < pool.length) {
    ids.add(pool[rnd.nextInt(pool.length)]);
  }
  var position = 0;
  return ids.map((id) {
    final f = catalog.firstWhere((e) => e.id == id);
    return _item(f, 1, f.portions.isEmpty ? f.servingUnit : f.portions.first.label, position++);
  }).toList();
}

MealItem _item(Food food, double quantity, String unit, int position) =>
    MealItem(
      id: _uuid.v4(),
      foodId: food.id,
      name: food.name,
      quantity: quantity,
      unit: unit,
      kcal: (food.kcal * quantity).round(),
      proteinG: food.proteinG * quantity,
      carbsG: food.carbsG * quantity,
      fatG: food.fatG * quantity,
      position: position,
    );

Meal _meal({
  required MealSlot slot,
  required DateTime at,
  required List<MealItem> items,
}) => Meal(
  id: _uuid.v4(),
  slot: slot,
  loggedAt: at,
  localDate: dateOnly(at),
  items: items,
  source: MealSource.manual,
  createdAt: at,
  updatedAt: at,
);

Activity _activity({
  required ActivityType type,
  required DateTime startedAt,
  required int durationMinutes,
  required Intensity intensity,
  required int creditPercentage,
  String? customName,
  int? distanceMeters,
  int? steps,
}) {
  final met = type.metFor(intensity);
  final kcal = calculateCaloriesFromMet(
    met: met,
    weightKg: _seedWeightKg,
    durationMinutes: durationMinutes,
  );
  return Activity(
    id: _uuid.v4(),
    activityTypeId: type.id,
    activityType: type,
    customName: customName,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(minutes: durationMinutes)),
    localDate: dateOnly(startedAt),
    durationMinutes: durationMinutes,
    intensity: intensity,
    distanceMeters: distanceMeters,
    steps: steps,
    estimatedCalories: kcal,
    appliedCalories: calculateAppliedExerciseCalories(
      estimatedCalories: kcal,
      creditPercentage: creditPercentage,
    ),
    exerciseCreditPercentage: creditPercentage,
    estimationMethod: EstimationMethod.met,
    metValue: met,
    weightKgUsed: _seedWeightKg,
    sourceType: ActivitySourceType.manual,
    createdAt: startedAt,
    updatedAt: startedAt,
  );
}
