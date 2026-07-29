import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';

import '../../core/config/feature_flags.dart';
import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../domain/calculations/duplicate_score.dart';
import '../../domain/calculations/exercise_credit.dart';
import '../../domain/calculations/met_calories.dart';
import '../../domain/calculations/pace_met.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/ai_analysis.dart';
import '../../domain/models/body.dart';
import '../../domain/models/food.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/meal.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/sleep.dart';
import '../../domain/models/summaries.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/water.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/photo_sync_service.dart';
import '../../domain/services/summary_builder.dart';
import '../local/local_store.dart';
import '../remote/gemini_analysis_client.dart';
import '../remote/open_food_facts_client.dart';
import '../remote/photo_storage_client.dart';

const _uuid = Uuid();

/// Implementación local-first de todos los repositorios sobre [LocalStore].
///
/// Cada mutación: escribe en la base local, deja `sync_status` según el estado
/// de conexión y avisa por [onChanged] para que la UI se actualice de
/// inmediato (escritura optimista, D-08).
class LocalRepository
    implements
        NutrimatRepositories,
        ProfileRepository,
        GoalRepository,
        MealRepository,
        ActivityRepository,
        FoodRepository,
        BodyRepository,
        WaterRepository,
        ReminderRepository,
        SleepRepository,
        SummaryRepository,
        HealthRepository,
        AiPhotoRepository,
        BackupRepository,
        ConnectivityRepository {
  LocalRepository(
    this.store, {
    required this.onChanged,
    OpenFoodFactsClient? foodCatalog,
    this.photos,
    this.aiAnalysis,
  }) : _foodCatalog = foodCatalog ?? OpenFoodFactsClient();

  final LocalStore store;
  final void Function() onChanged;
  final OpenFoodFactsClient _foodCatalog;

  /// Sube al bucket las fotos que quedan en el teléfono. Null sin servidor.
  final PhotoSyncService? photos;

  /// Análisis de foto por la Edge Function. Null sin servidor.
  final GeminiAnalysisClient? aiAnalysis;

  Future<void> _commit() async {
    await store.persist();
    onChanged();
  }

  // ── Perfil ─────────────────────────────────────────────────────────────

  @override
  UserProfile? get profileOrNull => store.profile;

  @override
  UserProfile get profile =>
      store.profile ?? UserProfile.empty('anonymous');

  @override
  bool get hasSession => store.profile != null;

  @override
  Future<void> updateProfile(UserProfile updated) async {
    store.profile = updated;
    await _commit();
  }

  @override
  Future<void> setThemeMode(ThemeModeSetting mode) =>
      updateProfile(profile.copyWith(themeMode: mode));

  @override
  Future<void> setUnitSystem(UnitSystem units) =>
      updateProfile(profile.copyWith(unitSystem: units));

  @override
  Future<void> setShowNetCalories(bool value) =>
      updateProfile(profile.copyWith(showNetCalories: value));

  /// Cambiar el crédito recalcula **solo** el día en curso y los futuros; los
  /// días cerrados conservan su porcentaje congelado (D-05, F-13).
  @override
  Future<void> setExerciseCredit({
    required int percentage,
    required bool enabled,
  }) async {
    store.profile = profile.copyWith(
      exerciseCreditPercentage: percentage,
      exerciseCreditEnabled: enabled,
    );
    final from = today();
    store.activities = store.activities.map((a) {
      if (a.localDate.isBefore(from)) return a;
      final applied = calculateAppliedExerciseCalories(
        estimatedCalories: a.estimatedCalories,
        creditPercentage: percentage,
        creditEnabled: enabled,
      );
      return a.copyWith(
        appliedCalories: applied,
        exerciseCreditPercentage: percentage,
      );
    }).toList();
    await _commit();
  }

  /// Deja el perfil en condiciones de usar la app sin pasar por ningún
  /// asistente: sin datos corporales todavía, pero con un objetivo con el que
  /// arrancar.
  ///
  /// El objetivo inicial es **manual**, no calculado. Sin sexo, altura, edad y
  /// peso no hay Mifflin-St Jeor, y presentar un número inventado como si
  /// fuera el resultado de una fórmula es exactamente lo que el producto no
  /// hace (RN-03). Se marca `targetMethod: manual` para que la pantalla de
  /// objetivo lo muestre como lo que es: un punto de partida a ajustar.
  Future<void> _ensureUsableProfile(UserProfile profile) async {
    store.profile = profile;
    if (store.goals.isEmpty) {
      store.goals = <Goal>[
        Goal(
          id: _uuid.v4(),
          goalType: GoalType.maintain,
          rateKgPerWeek: 0,
          baseCalorieTarget: defaultCalorieTarget,
          targetMethod: TargetMethod.manual,
          proteinG: 120,
          carbsG: 220,
          fatG: 65,
          macroMethod: 'default',
          startsOn: today(),
        ),
      ];
    }
    await _commit();
  }

  /// Punto de partida hasta que se carguen los datos corporales. Es un valor
  /// de referencia, no una estimación: la app lo dice en pantalla.
  static const int defaultCalorieTarget = 2000;

  @override
  Future<void> startDemoSession({required bool seeded}) async {
    if (seeded) {
      store.seed();
      await _commit();
      return;
    }
    store.reset(
      newProfile: UserProfile.empty(_uuid.v4()).copyWith(isDemo: true),
    );
    await _ensureUsableProfile(store.profile!);
  }

  @override
  Future<void> signIn(String email) async {
    final base = store.profile ?? UserProfile.empty(_uuid.v4());
    await _ensureUsableProfile(base.copyWith(email: email, isDemo: false));
  }

  @override
  Future<void> signOut() async {
    store.reset(newProfile: UserProfile.empty(_uuid.v4()));
    store.profile = null;
    await _commit();
  }

  // ── Objetivo ───────────────────────────────────────────────────────────

  @override
  Goal? get currentGoalOrNull => store.currentGoal;

  @override
  Goal goalFor(DateTime date) =>
      store.goalForDate(date) ??
      store.currentGoal ??
      Goal(
        id: 'fallback',
        goalType: GoalType.maintain,
        rateKgPerWeek: 0,
        baseCalorieTarget: 2000,
        targetMethod: TargetMethod.calculated,
        proteinG: 110,
        carbsG: 220,
        fatG: 60,
        macroMethod: 'default',
        startsOn: today(),
      );

  /// Guardar cierra la fila vigente (`endsOn = ayer`) e inserta la nueva desde
  /// hoy: el historial no se reescribe (F-13, AC-16).
  @override
  Future<void> saveGoal(Goal goal) async {
    final yesterday = today().subtract(const Duration(days: 1));
    store.goals = <Goal>[
      ...store.goals.map(
        (g) => g.isCurrent ? g.copyWith(endsOn: yesterday) : g,
      ),
      goal,
    ];
    await _commit();
  }

  // ── Comidas ────────────────────────────────────────────────────────────

  @override
  List<Meal> mealsOn(DateTime date) =>
      SummaryBuilder.mealsOn(store.meals, date);

  @override
  Meal? mealById(String id) {
    for (final m in store.meals) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<Meal> saveMeal(Meal meal) async {
    // La foto se sube antes de guardar para que en `photo_path` quede la ruta
    // del bucket y no una del teléfono, que en otro dispositivo no existiría.
    // Si la subida falla queda la local y se reintenta al volver a guardar.
    final photoPath = await photos?.ensureUploaded(
      bucket: PhotoBucket.meal,
      recordId: meal.id,
      localPath: meal.photoPath,
    );

    final withStatus = meal.copyWith(
      syncStatus: store.writeStatus,
      photoPath: photoPath ?? meal.photoPath,
    );
    final index = store.meals.indexWhere((m) => m.id == meal.id);
    if (index >= 0) {
      store.meals[index] = withStatus;
    } else {
      store.meals.add(withStatus);
    }
    for (final item in meal.items) {
      final foodId = item.foodId;
      if (foodId != null) await _touchRecent(foodId);
    }
    await _commit();
    return withStatus;
  }

  /// Borrado suave con ventana de deshacer de 8 s (RN-16).
  @override
  Future<void> deleteMeal(String id) async {
    store.meals = store.meals
        .map((m) => m.id == id ? m.copyWith(deletedAt: DateTime.now()) : m)
        .toList();
    await _commit();
  }

  @override
  Future<void> restoreMeal(String id) async {
    store.meals = store.meals
        .map((m) => m.id == id ? m.copyWith(clearDeletedAt: true) : m)
        .toList();
    await _commit();
  }

  @override
  Future<Meal> duplicateMeal(String id, DateTime date, MealSlot slot) async {
    final source = mealById(id);
    if (source == null) throw StateError('La comida ya no existe');
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      source.loggedAt.hour,
      source.loggedAt.minute,
    );
    final copy = Meal(
      id: _uuid.v4(),
      slot: slot,
      loggedAt: at,
      localDate: dateOnly(date),
      name: source.name,
      items: source.items
          .map((i) => i.copyWith())
          .map(
            (i) => MealItem(
              id: _uuid.v4(),
              foodId: i.foodId,
              name: i.name,
              quantity: i.quantity,
              unit: i.unit,
              kcal: i.kcal,
              proteinG: i.proteinG,
              carbsG: i.carbsG,
              fatG: i.fatG,
              position: i.position,
            ),
          )
          .toList(),
      source: MealSource.duplicate,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: store.writeStatus,
    );
    store.meals.add(copy);
    await _commit();
    return copy;
  }

  @override
  Future<void> toggleMealFavorite(String id) async {
    store.meals = store.meals
        .map((m) => m.id == id ? m.copyWith(isFavorite: !m.isFavorite) : m)
        .toList();
    await _commit();
  }

  @override
  List<Meal> favoriteMeals() =>
      store.meals.where((m) => m.isFavorite && !m.isDeleted).toList();

  // ── Actividad ──────────────────────────────────────────────────────────

  @override
  List<ActivityType> get types => store.allTypes;

  @override
  ActivityType? typeById(String id) => store.typeById(id);

  @override
  ActivityType? typeBySlug(String slug) => store.typeBySlug(slug);

  @override
  Future<ActivityType> createCustomType(ActivityType type) async {
    store.customTypes.add(type);
    await _commit();
    return type;
  }

  @override
  List<Activity> activitiesOn(DateTime date) =>
      SummaryBuilder.activitiesOn(store.activities, date);

  @override
  Activity? activityById(String id) {
    for (final a in store.activities) {
      if (a.id == id) return a.copyWith(activityType: typeById(a.activityTypeId));
    }
    return null;
  }

  @override
  List<Activity> recentActivities({int limit = 5}) {
    final seen = <String>{};
    final sorted = <Activity>[...store.activities.where((a) => !a.isDeleted)]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final out = <Activity>[];
    for (final a in sorted) {
      if (seen.add(a.activityTypeId)) out.add(a);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  List<Activity> favoriteActivities() =>
      store.activities.where((a) => a.isFavorite && !a.isDeleted).toList();

  @override
  ActivityEstimate estimate(ActivityDraft draft) {
    final override = draft.overrideCalories;
    final weightKg = store.currentWeightKg;
    final type = typeById(draft.activityTypeId);

    if (override != null) {
      return ActivityEstimate(
        calories: override,
        method: EstimationMethod.userOverride,
        durationMinutes: draft.durationMinutes,
      );
    }
    if (weightKg == null) {
      return const ActivityEstimate(
        calories: 0,
        method: EstimationMethod.met,
        unavailableReason: 'Necesitamos tu peso para estimar',
      );
    }
    if (type == null) {
      return const ActivityEstimate(
        calories: 0,
        method: EstimationMethod.met,
        unavailableReason: 'Elegí un tipo de actividad',
      );
    }

    var met = type.metFor(draft.intensity);
    var method = EstimationMethod.met;

    if (draft.usePaceEstimate &&
        draft.distanceMeters != null &&
        draft.distanceMeters! > 0) {
      final paceMet = estimateMetFromPace(
        distanceMeters: draft.distanceMeters!,
        durationMinutes: draft.durationMinutes,
        typeSlug: type.slug,
      );
      if (paceMet != null) {
        met = paceMet;
        method = EstimationMethod.pace;
      }
    }

    return ActivityEstimate(
      calories: calculateCaloriesFromMet(
        met: met,
        weightKg: weightKg,
        durationMinutes: draft.durationMinutes,
      ),
      method: method,
      metValue: met,
      weightKg: weightKg,
      durationMinutes: draft.durationMinutes,
    );
  }

  @override
  Future<Activity> saveActivity(ActivityDraft draft) async {
    final estimated = estimate(draft);
    final credit = profile.effectiveCreditPercentage;
    final enabled = profile.exerciseCreditEnabled;
    final existing = draft.id == null ? null : activityById(draft.id!);

    final calories = estimated.calories;
    final applied = calculateAppliedExerciseCalories(
      estimatedCalories: calories,
      creditPercentage: credit,
      creditEnabled: enabled,
    );

    final activity = Activity(
      id: draft.id ?? _uuid.v4(),
      activityTypeId: draft.activityTypeId,
      activityType: typeById(draft.activityTypeId),
      customName: draft.customName,
      startedAt: draft.startedAt,
      endedAt: draft.startedAt.add(Duration(minutes: draft.durationMinutes)),
      localDate: dateOnly(draft.startedAt),
      durationMinutes: draft.durationMinutes,
      intensity: draft.intensity,
      distanceMeters: draft.distanceMeters,
      steps: draft.steps,
      averageHeartRate: draft.averageHeartRate,
      maximumHeartRate: draft.maximumHeartRate,
      estimatedCalories: calories,
      // El valor calculado nunca se pierde ante un override (RN-04).
      originalCalories: draft.overrideCalories == null
          ? existing?.originalCalories
          : (existing?.originalCalories ??
                estimate(
                  ActivityDraft(
                    activityTypeId: draft.activityTypeId,
                    startedAt: draft.startedAt,
                    durationMinutes: draft.durationMinutes,
                    intensity: draft.intensity,
                    distanceMeters: draft.distanceMeters,
                    usePaceEstimate: draft.usePaceEstimate,
                  ),
                ).calories),
      appliedCalories: applied,
      exerciseCreditPercentage: credit,
      estimationMethod: estimated.method,
      metValue: estimated.metValue,
      weightKgUsed: estimated.weightKg,
      overrideReason: draft.overrideReason,
      sourceType: existing?.sourceType ?? ActivitySourceType.manual,
      userEdited: existing != null || draft.overrideCalories != null,
      notes: draft.notes,
      isFavorite: draft.isFavorite,
      syncStatus: store.writeStatus,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final index = store.activities.indexWhere((a) => a.id == activity.id);
    if (index >= 0) {
      store.activities[index] = activity;
    } else {
      store.activities.add(activity);
    }
    await _commit();
    return activity;
  }

  @override
  Future<void> deleteActivity(String id) async {
    store.activities = store.activities
        .map((a) => a.id == id ? a.copyWith(deletedAt: DateTime.now()) : a)
        .toList();
    await _commit();
  }

  @override
  Future<void> restoreActivity(String id) async {
    store.activities = store.activities
        .map((a) => a.id == id ? a.copyWith(clearDeletedAt: true) : a)
        .toList();
    await _commit();
  }

  @override
  Future<Activity> duplicateActivity(String id, DateTime date) async {
    final source = activityById(id);
    if (source == null) throw StateError('La actividad ya no existe');
    final startedAt = DateTime(
      date.year,
      date.month,
      date.day,
      source.startedAt.hour,
      source.startedAt.minute,
    );
    return saveActivity(
      ActivityDraft(
        activityTypeId: source.activityTypeId,
        customName: source.customName,
        startedAt: startedAt,
        durationMinutes: source.durationMinutes,
        intensity: source.intensity,
        distanceMeters: source.distanceMeters,
        steps: source.steps,
        notes: source.notes,
      ),
    );
  }

  @override
  Future<void> toggleFavorite(String id) async {
    store.activities = store.activities
        .map((a) => a.id == id ? a.copyWith(isFavorite: !a.isFavorite) : a)
        .toList();
    await _commit();
  }

  /// RN-04: se conserva `original_calories`, se marca `user_override`.
  @override
  Future<void> overrideCalories(String id, int calories, String? reason) async {
    store.activities = store.activities.map((a) {
      if (a.id != id) return a;
      final applied = calculateAppliedExerciseCalories(
        estimatedCalories: calories,
        creditPercentage: a.exerciseCreditPercentage,
        creditEnabled: profile.exerciseCreditEnabled,
      );
      return a.copyWith(
        originalCalories: a.originalCalories ?? a.estimatedCalories,
        estimatedCalories: calories,
        appliedCalories: applied,
        estimationMethod: EstimationMethod.userOverride,
        overrideReason: reason,
        userEdited: true,
      );
    }).toList();
    await _commit();
  }

  @override
  Future<void> restoreCalculatedCalories(String id) async {
    store.activities = store.activities.map((a) {
      if (a.id != id) return a;
      final original = a.originalCalories ?? a.estimatedCalories;
      final applied = calculateAppliedExerciseCalories(
        estimatedCalories: original,
        creditPercentage: a.exerciseCreditPercentage,
        creditEnabled: profile.exerciseCreditEnabled,
      );
      return a.copyWith(
        estimatedCalories: original,
        appliedCalories: applied,
        estimationMethod: a.metValue == null
            ? EstimationMethod.met
            : EstimationMethod.met,
        clearOverride: true,
      );
    }).toList();
    await _commit();
  }

  @override
  List<DuplicateCandidate> checkOverlap(ActivityDraft draft) {
    final incoming = DuplicateInput(
      activityTypeId: draft.activityTypeId,
      startedAt: draft.startedAt,
      durationMinutes: draft.durationMinutes,
      estimatedCalories: estimate(draft).calories,
      distanceMeters: draft.distanceMeters,
    );

    final out = <DuplicateCandidate>[];
    for (final a in store.activities) {
      if (a.isDeleted || a.id == draft.id) continue;
      final score = duplicateScore(
        incoming,
        DuplicateInput(
          activityTypeId: a.activityTypeId,
          startedAt: a.startedAt,
          durationMinutes: a.durationMinutes,
          estimatedCalories: a.estimatedCalories,
          distanceMeters: a.distanceMeters,
        ),
      );
      if (score.score >= DuplicateThresholds.suspicious) {
        out.add(
          DuplicateCandidate(
            incoming: _draftToActivity(draft, incoming.estimatedCalories),
            existing: a,
            score: score,
          ),
        );
      }
    }
    return out;
  }

  Activity _draftToActivity(ActivityDraft draft, int calories) => Activity(
    id: draft.id ?? 'draft',
    activityTypeId: draft.activityTypeId,
    activityType: typeById(draft.activityTypeId),
    customName: draft.customName,
    startedAt: draft.startedAt,
    endedAt: draft.startedAt.add(Duration(minutes: draft.durationMinutes)),
    localDate: dateOnly(draft.startedAt),
    durationMinutes: draft.durationMinutes,
    intensity: draft.intensity,
    distanceMeters: draft.distanceMeters,
    steps: draft.steps,
    estimatedCalories: calories,
    appliedCalories: 0,
    exerciseCreditPercentage: profile.effectiveCreditPercentage,
    estimationMethod: EstimationMethod.met,
    sourceType: ActivitySourceType.manual,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  @override
  List<ExerciseTemplate> get templates => store.templates;

  @override
  Future<void> saveTemplate(ExerciseTemplate template) async {
    final index = store.templates.indexWhere((t) => t.id == template.id);
    if (index >= 0) {
      store.templates[index] = template;
    } else {
      store.templates.add(template);
    }
    await _commit();
  }

  @override
  Future<void> deleteTemplate(String id) async {
    store.templates.removeWhere((t) => t.id == id);
    await _commit();
  }

  @override
  List<ActivityGoal> get activityGoals => store.activityGoals;

  @override
  Future<void> saveActivityGoal(ActivityGoal goal) async {
    final index = store.activityGoals.indexWhere((g) => g.id == goal.id);
    if (index >= 0) {
      store.activityGoals[index] = goal;
    } else {
      store.activityGoals.add(goal);
    }
    await _commit();
  }

  @override
  Future<void> deleteActivityGoal(String id) async {
    store.activityGoals.removeWhere((g) => g.id == id);
    await _commit();
  }

  // ── Alimentos ──────────────────────────────────────────────────────────

  @override
  List<Food> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return recent();
    final matches = store.allFoods.where((f) {
      final haystack = '${f.name} ${f.brand ?? ''}'.toLowerCase();
      return haystack.contains(q);
    }).toList();
    // "Tuyos" primero, después marcas, después genéricos (F-04 paso 4).
    matches.sort((a, b) {
      int rank(Food f) => switch (f.source) {
        FoodSource.user => 0,
        FoodSource.off => 1,
        _ => 2,
      };
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });
    return matches;
  }

  /// Consulta el catálogo externo y cachea lo que trae, para que la próxima
  /// búsqueda —y el modo sin conexión— lo encuentren local.
  @override
  Future<List<Food>> searchOnline(String query) async {
    if (!FeatureFlags.onlineFoodCatalog || store.offline) {
      return const <Food>[];
    }
    if (query.trim().length < 2) return const <Food>[];

    final results = await _foodCatalog.search(query);
    if (results.isEmpty) return results;

    store.cacheFoods(results);
    await store.persist();
    return results;
  }

  @override
  Future<Food?> lookupBarcode(String ean) async {
    final local = byBarcode(ean);
    if (local != null) return local;
    if (!FeatureFlags.onlineFoodCatalog || store.offline) {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Sin conexión no podemos buscar el código en el catálogo.',
      );
    }

    final found = await _foodCatalog.byBarcode(ean);
    if (found == null) return null;

    store.cacheFoods(<Food>[found]);
    await _commit();
    return found;
  }

  @override
  List<Food> recent() {
    final out = <Food>[];
    for (final id in store.recentFoodIds) {
      final food = byId(id);
      if (food != null) out.add(food);
    }
    return out;
  }

  @override
  List<Food> favorites() => store.allFoods.where((f) => f.isFavorite).toList();

  @override
  List<Food> ownFoods() => store.userFoods;

  @override
  Food? byId(String id) {
    for (final f in store.allFoods) {
      if (f.id == id) return f;
    }
    return null;
  }

  @override
  Food? byBarcode(String ean) {
    for (final f in store.allFoods) {
      if (f.barcode == ean) return f;
    }
    return null;
  }

  @override
  Future<Food> createOwnFood(Food food) async {
    store.userFoods.add(food);
    await _commit();
    return food;
  }

  @override
  Future<void> toggleFoodFavorite(String id) async {
    // Las tres listas, no dos: lo que viene de Open Food Facts queda en
    // `cachedFoods`, y saltearla hacía que marcar un producto del catálogo
    // externo no tuviera ningún efecto.
    //
    // El valor nuevo se calcula una sola vez y se aplica a todas: si un id
    // estuviera en más de una lista, invertir cada una por separado lo dejaría
    // marcado en unas y desmarcado en otras.
    final current = byId(id)?.isFavorite ?? false;
    final next = !current;

    List<Food> apply(List<Food> foods) => foods
        .map((f) => f.id == id ? f.copyWith(isFavorite: next) : f)
        .toList();

    store.userFoods = apply(store.userFoods);
    store.catalogFoods = apply(store.catalogFoods);
    store.cachedFoods = apply(store.cachedFoods);
    await _commit();
  }

  @override
  Future<void> deleteOwnFood(String id) async {
    store.userFoods.removeWhere((f) => f.id == id);
    await _commit();
  }

  @override
  Future<void> markUsed(String foodId) => _touchRecent(foodId);

  Future<void> _touchRecent(String foodId) async {
    store.recentFoodIds
      ..remove(foodId)
      ..insert(0, foodId);
    if (store.recentFoodIds.length > 20) {
      store.recentFoodIds = store.recentFoodIds.sublist(0, 20);
    }
  }

  // ── Cuerpo ─────────────────────────────────────────────────────────────

  @override
  List<WeightLog> get weightLogs =>
      <WeightLog>[...store.weightLogs]
        ..sort((a, b) => b.localDate.compareTo(a.localDate));

  @override
  WeightLog? weightOn(DateTime date) {
    for (final w in store.weightLogs) {
      if (isSameDay(w.localDate, date)) return w;
    }
    return null;
  }

  @override
  double? get currentWeightKg => store.currentWeightKg;

  /// Un peso por día: registrar de nuevo actualiza el existente (D-16).
  @override
  Future<WeightLog> logWeight({
    required double weightKg,
    required DateTime date,
    String? notes,
  }) async {
    final existing = weightOn(date);
    final log = WeightLog(
      id: existing?.id ?? _uuid.v4(),
      weightKg: weightKg,
      localDate: dateOnly(date),
      loggedAt: DateTime.now(),
      notes: notes,
      syncStatus: store.writeStatus,
    );
    store.weightLogs = <WeightLog>[
      ...store.weightLogs.where((w) => !isSameDay(w.localDate, date)),
      log,
    ];
    await _commit();
    return log;
  }

  @override
  Future<void> deleteWeight(String id) async {
    store.weightLogs.removeWhere((w) => w.id == id);
    await _commit();
  }

  // ── Sueño ──────────────────────────────────────────────────────────────

  @override
  List<SleepLog> get sleepLogs => <SleepLog>[...store.sleepLogs]
    ..sort((a, b) => a.localDate.compareTo(b.localDate));

  @override
  SleepLog? sleepOn(DateTime date) {
    final day = dateOnly(date);
    for (final log in store.sleepLogs) {
      if (isSameDay(log.localDate, day)) return log;
    }
    return null;
  }

  @override
  Future<void> logSleep({
    required DateTime date,
    required int minutes,
    required SleepQuality quality,
    String? notes,
  }) async {
    final day = dateOnly(date);
    final index = store.sleepLogs.indexWhere(
      (s) => isSameDay(s.localDate, day),
    );
    final entry = SleepLog(
      id: index >= 0 ? store.sleepLogs[index].id : _uuid.v4(),
      localDate: day,
      minutes: SleepLog.clampMinutes(minutes),
      quality: quality,
      loggedAt: DateTime.now(),
      notes: notes,
      syncStatus: store.writeStatus,
    );
    if (index >= 0) {
      store.sleepLogs[index] = entry;
    } else {
      store.sleepLogs.add(entry);
    }
    await _commit();
  }

  @override
  Future<void> deleteSleep(String id) async {
    store.sleepLogs.removeWhere((s) => s.id == id);
    await _commit();
  }

  // ── Recordatorios ──────────────────────────────────────────────────────

  @override
  List<Reminder> get reminders => store.reminders;

  @override
  Reminder reminderFor(ReminderKind kind) => store.reminders.firstWhere(
    (r) => r.kind == kind,
    orElse: () => Reminder.byDefault(kind),
  );

  @override
  Future<void> saveReminder(Reminder reminder) async {
    store.reminders = <Reminder>[
      for (final r in store.reminders)
        if (r.kind == reminder.kind) reminder else r,
    ];
    await _commit();
  }

  // ── Agua ───────────────────────────────────────────────────────────────

  @override
  List<WaterLog> get waterLogs =>
      <WaterLog>[...store.waterLogs]
        ..sort((a, b) => a.localDate.compareTo(b.localDate));

  @override
  int glassesOn(DateTime date) {
    final day = dateOnly(date);
    for (final log in store.waterLogs) {
      if (isSameDay(log.localDate, day)) return log.glasses;
    }
    return 0;
  }

  @override
  Future<void> addGlasses(DateTime date, int delta) async {
    final day = dateOnly(date);
    final index = store.waterLogs.indexWhere(
      (w) => isSameDay(w.localDate, day),
    );

    if (index >= 0) {
      final current = store.waterLogs[index];
      final next = (current.glasses + delta).clamp(0, WaterLog.maxGlasses);
      store.waterLogs[index] = current.copyWith(
        glasses: next,
        updatedAt: DateTime.now(),
      );
    } else {
      // Restar cuando no hay registro no crea uno en cero: no aporta nada y
      // ensucia el historial con días vacíos.
      if (delta <= 0) return;
      store.waterLogs.add(
        WaterLog(
          id: _uuid.v4(),
          localDate: day,
          glasses: delta.clamp(0, WaterLog.maxGlasses),
          updatedAt: DateTime.now(),
        ),
      );
    }
    await _commit();
  }

  @override
  Future<void> setWaterGoal({
    required int glasses,
    required int glassSizeMl,
  }) => updateProfile(
    profile.copyWith(
      waterGoalGlasses: glasses.clamp(1, WaterLog.maxGlasses),
      glassSizeMl: glassSizeMl.clamp(50, 1000),
    ),
  );

  @override
  List<BodyMeasurement> measurements(MeasurementMetric metric) =>
      store.measurements.where((m) => m.metric == metric).toList()
        ..sort((a, b) => a.localDate.compareTo(b.localDate));

  @override
  Map<MeasurementMetric, BodyMeasurement> measurementsOn(DateTime date) =>
      <MeasurementMetric, BodyMeasurement>{
        for (final m in store.measurements)
          if (isSameDay(m.localDate, date)) m.metric: m,
      };

  @override
  Future<void> logMeasurement({
    required MeasurementMetric metric,
    required double value,
    required DateTime date,
  }) async {
    store.measurements = <BodyMeasurement>[
      ...store.measurements.where(
        (m) => !(m.metric == metric && isSameDay(m.localDate, date)),
      ),
      BodyMeasurement(
        id: _uuid.v4(),
        metric: metric,
        value: value,
        localDate: dateOnly(date),
      ),
    ];
    await _commit();
  }

  @override
  Future<void> deleteMeasurement(String id) async {
    store.measurements.removeWhere((m) => m.id == id);
    await _commit();
  }

  // ── Agregados ──────────────────────────────────────────────────────────

  @override
  DailySummary daily(DateTime date) => SummaryBuilder.daily(
    date: date,
    goal: goalFor(date),
    allMeals: store.meals,
    allActivities: store.activities,
    weightLogs: store.weightLogs,
    creditPercentage: profile.exerciseCreditPercentage,
    creditEnabled: profile.exerciseCreditEnabled,
    isRestDay: isRestDay(date),
  );

  @override
  List<HistoryDay> history({required DateTime from, required DateTime to}) =>
      SummaryBuilder.history(
        from: from,
        to: to,
        allMeals: store.meals,
        allActivities: store.activities,
        goalFor: goalFor,
        isRestDay: isRestDay,
        creditEnabled: profile.exerciseCreditEnabled,
      );

  @override
  ProgressSummary progress({required DateTime from, required DateTime to}) =>
      SummaryBuilder.progress(
        from: from,
        to: to,
        allMeals: store.meals,
        allActivities: store.activities,
        weightLogs: store.weightLogs,
        activityGoals: store.activityGoals,
        goalFor: goalFor,
        isRestDay: isRestDay,
        creditEnabled: profile.exerciseCreditEnabled,
      );

  @override
  bool isRestDay(DateTime date) => store.isRestDay(date);

  @override
  Future<void> setRestDay(DateTime date, bool isRest) async {
    final key = isoDate(date);
    if (isRest) {
      store.restDays.add(key);
    } else {
      store.restDays.remove(key);
    }
    await _commit();
  }

  @override
  Set<String> get daysWithRecords => <String>{
    ...store.meals.where((m) => !m.isDeleted).map((m) => isoDate(m.localDate)),
    ...store.activities
        .where((a) => !a.isDeleted)
        .map((a) => isoDate(a.localDate)),
  };

  // ── Salud ──────────────────────────────────────────────────────────────

  @override
  HealthIntegration get integration => store.integration;

  /// La pantalla de integraciones solo existe en Android (D-21).
  @override
  bool get isPlatformSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> connect() async {
    store.integration = store.integration.copyWith(
      status: IntegrationStatus.connected,
      connectedAt: DateTime.now(),
      permissions: const <String>[
        'ExerciseSession',
        'ActiveCaloriesBurned',
        'Steps',
        'Distance',
        'HeartRate',
      ],
      clearError: true,
    );
    await _commit();
  }

  @override
  Future<void> disconnect() async {
    store.integration = store.integration.copyWith(
      status: IntegrationStatus.notConnected,
      permissions: const <String>[],
    );
    await _commit();
  }

  /// Importación simulada: trae 3 sesiones, una de ellas solapada con un
  /// registro manual, para ejercitar el diálogo de duplicado (D-07).
  @override
  Future<HealthSyncResult> sync() async {
    final walking = typeBySlug('walking');
    final cycling = typeBySlug('cycling');
    if (walking == null || cycling == null) {
      return const HealthSyncResult(
        imported: 0,
        updated: 0,
        skipped: 0,
        duplicates: <DuplicateCandidate>[],
      );
    }

    final now = DateTime.now();
    final weight = store.currentWeightKg ?? 70;
    final credit = profile.effectiveCreditPercentage;
    final enabled = profile.exerciseCreditEnabled;

    Activity imported({
      required ActivityType type,
      required DateTime startedAt,
      required int minutes,
      required int calories,
      required String externalId,
      SyncStatus status = SyncStatus.synced,
      int? steps,
      int? distanceMeters,
    }) {
      final valid = providerCaloriesAreValid(
        activeCalories: calories,
        durationMinutes: minutes,
      );
      final kcal = valid
          ? calories
          : calculateCaloriesFromMet(
              met: type.metFor(Intensity.moderate),
              weightKg: weight,
              durationMinutes: minutes,
            );
      return Activity(
        id: _uuid.v4(),
        activityTypeId: type.id,
        activityType: type,
        startedAt: startedAt,
        endedAt: startedAt.add(Duration(minutes: minutes)),
        localDate: dateOnly(startedAt),
        durationMinutes: minutes,
        intensity: Intensity.moderate,
        distanceMeters: distanceMeters,
        steps: steps,
        estimatedCalories: kcal,
        appliedCalories: calculateAppliedExerciseCalories(
          estimatedCalories: kcal,
          creditPercentage: credit,
          creditEnabled: enabled,
        ),
        exerciseCreditPercentage: credit,
        // Se usa ActiveCaloriesBurned; si es inválido se recalcula (D-12, RN-05).
        estimationMethod: valid
            ? EstimationMethod.provider
            : EstimationMethod.metRecalculated,
        metValue: valid ? null : type.metFor(Intensity.moderate),
        weightKgUsed: valid ? null : weight,
        sourceType: ActivitySourceType.imported,
        externalSource: HealthProvider.healthConnect.wire,
        externalId: externalId,
        sourceUpdatedAt: now,
        deviceName: 'Pixel Watch',
        syncStatus: status,
        createdAt: now,
        updatedAt: now,
      );
    }

    final existingIds = store.activities
        .map((a) => a.externalId)
        .whereType<String>()
        .toSet();

    final candidates = <Activity>[
      imported(
        type: cycling,
        startedAt: DateTime(now.year, now.month, now.day, 6, 40),
        minutes: 40,
        calories: 355,
        externalId: 'hc-ride-01',
        distanceMeters: 12400,
      ),
      imported(
        type: walking,
        startedAt: DateTime(now.year, now.month, now.day, 12, 15),
        minutes: 18,
        calories: 74,
        externalId: 'hc-walk-02',
        steps: 2140,
        distanceMeters: 1600,
      ),
      // Esta se solapa con la caminata manual de las 7:30 del seed.
      imported(
        type: walking,
        startedAt: DateTime(now.year, now.month, now.day, 7, 35),
        minutes: 28,
        calories: 176,
        externalId: 'hc-walk-03',
        steps: 3310,
        distanceMeters: 2500,
        status: SyncStatus.needsReview,
      ),
    ].where((a) => !existingIds.contains(a.externalId)).toList();

    final duplicates = <DuplicateCandidate>[];
    for (final candidate in candidates) {
      final incoming = DuplicateInput(
        activityTypeId: candidate.activityTypeId,
        startedAt: candidate.startedAt,
        durationMinutes: candidate.durationMinutes,
        estimatedCalories: candidate.estimatedCalories,
        distanceMeters: candidate.distanceMeters,
        externalSource: candidate.externalSource,
        externalId: candidate.externalId,
      );
      for (final existing in store.activities) {
        if (existing.isDeleted ||
            existing.sourceType == ActivitySourceType.imported) {
          continue;
        }
        final score = duplicateScore(
          incoming,
          DuplicateInput(
            activityTypeId: existing.activityTypeId,
            startedAt: existing.startedAt,
            durationMinutes: existing.durationMinutes,
            estimatedCalories: existing.estimatedCalories,
            distanceMeters: existing.distanceMeters,
          ),
        );
        if (score.score >= DuplicateThresholds.suspicious) {
          duplicates.add(
            DuplicateCandidate(
              incoming: candidate,
              existing: existing,
              score: score,
            ),
          );
        }
      }
      store.activities.add(candidate);
    }

    store.integration = store.integration.copyWith(
      status: IntegrationStatus.connected,
      lastSyncAt: now,
      importedCount: store.integration.importedCount + candidates.length,
      clearError: true,
    );
    await _commit();

    return HealthSyncResult(
      imported: candidates.length,
      updated: 0,
      skipped: 0,
      duplicates: duplicates,
    );
  }

  @override
  Future<void> deleteImported() async {
    final removed = store.activities
        .where((a) => a.sourceType == ActivitySourceType.imported)
        .length;
    store.activities.removeWhere(
      (a) => a.sourceType == ActivitySourceType.imported,
    );
    store.integration = store.integration.copyWith(
      importedCount:
          (store.integration.importedCount - removed).clamp(0, 1 << 31),
    );
    await _commit();
  }

  /// La descartada pasa a `deleted_at` con motivo `duplicate_merge`; sin
  /// acción del usuario queda `needs_review` (S-14).
  @override
  Future<void> resolveDuplicate(
    DuplicateCandidate candidate,
    DuplicateResolution resolution,
  ) async {
    switch (resolution) {
      case DuplicateResolution.keepIncoming:
        await deleteActivity(candidate.existing.id);
        _markReviewed(candidate.incoming.id);
      case DuplicateResolution.keepExisting:
        await deleteActivity(candidate.incoming.id);
      case DuplicateResolution.keepBoth:
        _markReviewed(candidate.incoming.id);
      case DuplicateResolution.defer:
        break;
    }
    await _commit();
  }

  void _markReviewed(String id) {
    store.activities = store.activities
        .map(
          (a) => a.id == id && a.syncStatus == SyncStatus.needsReview
              ? a.copyWith(syncStatus: SyncStatus.synced)
              : a,
        )
        .toList();
  }

  @override
  List<DuplicateCandidate> get pendingReviews {
    final out = <DuplicateCandidate>[];
    final needsReview = store.activities.where(
      (a) => !a.isDeleted && a.syncStatus == SyncStatus.needsReview,
    );
    for (final incoming in needsReview) {
      for (final existing in store.activities) {
        if (existing.id == incoming.id ||
            existing.isDeleted ||
            existing.sourceType == ActivitySourceType.imported) {
          continue;
        }
        final score = duplicateScore(
          DuplicateInput(
            activityTypeId: incoming.activityTypeId,
            startedAt: incoming.startedAt,
            durationMinutes: incoming.durationMinutes,
            estimatedCalories: incoming.estimatedCalories,
            distanceMeters: incoming.distanceMeters,
          ),
          DuplicateInput(
            activityTypeId: existing.activityTypeId,
            startedAt: existing.startedAt,
            durationMinutes: existing.durationMinutes,
            estimatedCalories: existing.estimatedCalories,
            distanceMeters: existing.distanceMeters,
          ),
        );
        if (score.score >= DuplicateThresholds.suspicious) {
          out.add(
            DuplicateCandidate(
              incoming: incoming,
              existing: existing,
              score: score,
            ),
          );
        }
      }
    }
    return out;
  }

  // ── Análisis de foto ───────────────────────────────────────────────────

  /// Cuota de 20 análisis por día (D-18).
  @override
  int get quotaLimit => 20;

  int _quotaUsed = 0;

  @override
  int get quotaUsed => _quotaUsed;

  @override
  Future<AiAnalysis> analyze({required String photoPath}) async {
    final client = aiAnalysis;
    if (client != null) {
      // La foto tiene que estar en el bucket antes: la función la descarga de
      // ahí. Si la subida falló, esto devuelve la ruta local y la función
      // responde "no encontramos esa foto", que es correcto y se muestra tal
      // cual.
      final remotePath =
          await photos?.ensureUploaded(
            bucket: PhotoBucket.meal,
            recordId: _uuid.v4(),
            localPath: photoPath,
          ) ??
          photoPath;

      final analysis = await client.analyze(photoPath: remotePath);
      _quotaUsed++;
      return analysis;
    }

    // Sin servidor: resultado fijo. Solo se llega acá con `NM_AI_PHOTO`
    // encendido a mano en una compilación sin Supabase.
    _quotaUsed++;
    final now = DateTime.now();
    return AiAnalysis(
      id: _uuid.v4(),
      photoPath: photoPath,
      status: AiAnalysisStatus.completed,
      model: 'gemini-2.5-flash',
      promptVersion: 'v1',
      latencyMs: 1200,
      createdAt: now,
      items: const <AiAnalysisItem>[
        AiAnalysisItem(
          name: 'Milanesa de carne',
          quantity: 1,
          unit: 'unidad',
          kcal: 289,
          proteinG: 23,
          carbsG: 14,
          fatG: 15,
          confidence: 0.82,
        ),
        AiAnalysisItem(
          name: 'Puré de papas',
          quantity: 200,
          unit: 'g',
          kcal: 174,
          proteinG: 3.6,
          carbsG: 29,
          fatG: 5,
          confidence: 0.64,
        ),
        AiAnalysisItem(
          name: 'Ensalada de tomate',
          quantity: 120,
          unit: 'g',
          kcal: 38,
          proteinG: 1.4,
          carbsG: 5.6,
          fatG: 0.5,
          confidence: 0.41,
        ),
      ],
    );
  }

  // ── Respaldo ───────────────────────────────────────────────────────────

  @override
  bool get hasUserData =>
      store.meals.isNotEmpty ||
      store.activities.isNotEmpty ||
      store.weightLogs.isNotEmpty ||
      store.measurements.isNotEmpty ||
      store.waterLogs.isNotEmpty ||
      store.sleepLogs.isNotEmpty ||
      store.userFoods.isNotEmpty;

  @override
  String exportJson() {
    final document = store.toDocument();
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'app': 'Nutrimat',
      'exportedAt': DateTime.now().toIso8601String(),
      ...document,
    });
  }

  @override
  BackupSummary inspectBackup(String json) {
    final document = _parseBackup(json);
    int count(String key) => (document[key] as List<dynamic>?)?.length ?? 0;
    return BackupSummary(
      meals: count('meals'),
      activities: count('activities'),
      weights: count('weightLogs'),
      measurements: count('measurements'),
    );
  }

  @override
  Future<BackupSummary> importJson(String json) async {
    final document = _parseBackup(json);
    final summary = inspectBackup(json);
    store.restoreDocument(document);
    await _commit();
    return summary;
  }

  Map<String, dynamic> _parseBackup(String json) {
    Map<String, dynamic> document;
    try {
      document = jsonDecode(json) as Map<String, dynamic>;
    } on Object {
      throw const AppError(
        code: ApiErrorCode.validation,
        message: 'Ese archivo no es un respaldo de Nutrimat.',
      );
    }

    // Un archivo de otra app puede ser JSON válido: se exige el perfil, que
    // es lo mínimo que todo respaldo nuestro tiene.
    if (!document.containsKey('profile')) {
      throw const AppError(
        code: ApiErrorCode.validation,
        message: 'Ese archivo no es un respaldo de Nutrimat.',
      );
    }

    final version = document['schemaVersion'] as int? ?? 1;
    if (version > LocalStore.schemaVersion) {
      throw const AppError(
        code: ApiErrorCode.validation,
        message: 'Ese respaldo viene de una versión más nueva de la app. '
            'Actualizá Nutrimat antes de importarlo.',
      );
    }
    return document;
  }

  // ── Conectividad ───────────────────────────────────────────────────────

  @override
  bool get isOffline => store.offline;

  @override
  int get pendingCount => store.pendingCount;

  @override
  Future<void> setOffline(bool value) async {
    store.offline = value;
    if (!value) await flushQueue();
    await _commit();
  }

  @override
  Future<void> flushQueue() async {
    store.meals = store.meals
        .map(
          (m) => m.syncStatus == SyncStatus.pending
              ? m.copyWith(syncStatus: SyncStatus.synced)
              : m,
        )
        .toList();
    store.activities = store.activities
        .map(
          (a) => a.syncStatus == SyncStatus.pending
              ? a.copyWith(syncStatus: SyncStatus.synced)
              : a,
        )
        .toList();
    store.weightLogs = store.weightLogs
        .map(
          (w) => w.syncStatus == SyncStatus.pending
              ? w.copyWith(syncStatus: SyncStatus.synced)
              : w,
        )
        .toList();
    await _commit();
  }
}
