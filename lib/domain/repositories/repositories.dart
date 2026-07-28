// ignore: unused_import
import '../../core/error/app_error.dart';
import '../calculations/duplicate_score.dart';
import '../enums/enums.dart';
import '../models/activity.dart';
import '../models/ai_analysis.dart';
import '../models/body.dart';
import '../models/food.dart';
import '../models/goal.dart';
import '../models/meal.dart';
import '../models/summaries.dart';
import '../models/user_profile.dart';
import '../models/water.dart';

/// Interfaces de la capa de datos. La presentación depende **solo** de esto;
/// las implementaciones viven en `data/repositories/` (19-project-structure §3).
///
/// Los repositorios son local-first: leen de la base local y escriben local
/// encolando la sincronización (13-state-management.md §5).

/// Borrador de una actividad en edición (S-10).
class ActivityDraft {
  const ActivityDraft({
    required this.activityTypeId,
    required this.startedAt,
    required this.durationMinutes,
    required this.intensity,
    this.id,
    this.customName,
    this.distanceMeters,
    this.steps,
    this.averageHeartRate,
    this.maximumHeartRate,
    this.notes,
    this.overrideCalories,
    this.overrideReason,
    this.usePaceEstimate = false,
    this.isFavorite = false,
  });

  final String? id;
  final String activityTypeId;
  final String? customName;
  final DateTime startedAt;
  final int durationMinutes;
  final Intensity intensity;
  final int? distanceMeters;
  final int? steps;
  final int? averageHeartRate;
  final int? maximumHeartRate;
  final String? notes;
  final int? overrideCalories;
  final String? overrideReason;
  final bool usePaceEstimate;
  final bool isFavorite;
}

/// Resultado de una sincronización de salud (F-09).
class HealthSyncResult {
  const HealthSyncResult({
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.duplicates,
  });

  final int imported;
  final int updated;
  final int skipped;
  final List<DuplicateCandidate> duplicates;
}

/// Par de actividades a resolver por la persona (nunca se resuelve solo, D-07).
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.incoming,
    required this.existing,
    required this.score,
  });

  final Activity incoming;
  final Activity existing;
  final DuplicateScore score;
}

enum DuplicateResolution { keepIncoming, keepExisting, keepBoth, defer }

/// Todas las superficies de datos juntas. Existe para que la presentación
/// pueda inyectar un único objeto sin conocer la implementación concreta.
abstract interface class NutrimatRepositories
    implements
        ProfileRepository,
        GoalRepository,
        MealRepository,
        ActivityRepository,
        FoodRepository,
        BodyRepository,
        WaterRepository,
        SummaryRepository,
        HealthRepository,
        AiPhotoRepository,
        BackupRepository,
        ConnectivityRepository {}

abstract interface class ProfileRepository {
  UserProfile? get profileOrNull;
  UserProfile get profile;
  bool get hasSession;
  Future<void> updateProfile(UserProfile profile);
  Future<void> setExerciseCredit({
    required int percentage,
    required bool enabled,
  });
  /// Modo demo sin cuenta: usuario local anónimo (D-15).
  Future<void> startDemoSession({required bool seeded});
  Future<void> signIn(String email);
  Future<void> signOut();
  Future<void> setThemeMode(ThemeModeSetting mode);
  Future<void> setUnitSystem(UnitSystem units);
  Future<void> setShowNetCalories(bool value);
}

abstract interface class GoalRepository {
  Goal? get currentGoalOrNull;
  Goal goalFor(DateTime date);
  Future<void> saveGoal(Goal goal);
}

abstract interface class MealRepository {
  List<Meal> mealsOn(DateTime date);
  Meal? mealById(String id);
  Future<Meal> saveMeal(Meal meal);
  Future<void> deleteMeal(String id);
  Future<void> restoreMeal(String id);
  Future<Meal> duplicateMeal(String id, DateTime date, MealSlot slot);
  Future<void> toggleMealFavorite(String id);
  List<Meal> favoriteMeals();
}

abstract interface class ActivityRepository {
  List<ActivityType> get types;
  ActivityType? typeById(String id);
  ActivityType? typeBySlug(String slug);
  Future<ActivityType> createCustomType(ActivityType type);

  List<Activity> activitiesOn(DateTime date);
  Activity? activityById(String id);
  List<Activity> recentActivities({int limit = 5});
  List<Activity> favoriteActivities();

  /// Calcula el gasto estimado de un borrador sin persistirlo (S-10).
  ActivityEstimate estimate(ActivityDraft draft);

  Future<Activity> saveActivity(ActivityDraft draft);
  Future<void> deleteActivity(String id);
  Future<void> restoreActivity(String id);
  Future<Activity> duplicateActivity(String id, DateTime date);
  Future<void> toggleFavorite(String id);
  Future<void> overrideCalories(String id, int calories, String? reason);
  Future<void> restoreCalculatedCalories(String id);

  /// Solapamientos con lo ya registrado, para la advertencia de F-08.
  List<DuplicateCandidate> checkOverlap(ActivityDraft draft);

  List<ExerciseTemplate> get templates;
  Future<void> saveTemplate(ExerciseTemplate template);
  Future<void> deleteTemplate(String id);

  List<ActivityGoal> get activityGoals;
  Future<void> saveActivityGoal(ActivityGoal goal);
  Future<void> deleteActivityGoal(String id);
}

/// Lo que `ExerciseCaloriesEstimate` necesita para explicarse (RN-03).
class ActivityEstimate {
  const ActivityEstimate({
    required this.calories,
    required this.method,
    this.metValue,
    this.weightKg,
    this.durationMinutes,
    this.unavailableReason,
  });

  final int calories;
  final EstimationMethod method;
  final double? metValue;
  final double? weightKg;
  final int? durationMinutes;

  /// "Necesitamos tu peso para estimar" cuando falta un insumo.
  final String? unavailableReason;

  bool get isAvailable => unavailableReason == null;
}

abstract interface class FoodRepository {
  /// Búsqueda local inmediata: alimentos propios y catálogo ya cacheado.
  List<Food> search(String query);

  /// Búsqueda en el catálogo externo (Open Food Facts). Lanza [AppError]
  /// si el proveedor falla o se pasa del timeout; la UI degrada a lo local
  /// con un banner de reintento (F-04).
  Future<List<Food>> searchOnline(String query);

  /// Consulta por código de barras en el catálogo externo.
  Future<Food?> lookupBarcode(String ean);

  List<Food> recent();
  List<Food> favorites();
  List<Food> ownFoods();
  Food? byId(String id);
  Food? byBarcode(String ean);
  Future<Food> createOwnFood(Food food);
  Future<void> toggleFoodFavorite(String id);
  Future<void> deleteOwnFood(String id);
  Future<void> markUsed(String foodId);
}

abstract interface class WaterRepository {
  /// Vasos de hoy o del día pedido. Devuelve 0 si nunca se registró nada.
  int glassesOn(DateTime date);

  List<WaterLog> get waterLogs;

  /// Suma o resta vasos. Nunca baja de 0 ni sube de [WaterLog.maxGlasses].
  Future<void> addGlasses(DateTime date, int delta);

  Future<void> setWaterGoal({required int glasses, required int glassSizeMl});
}

abstract interface class BodyRepository {
  List<WeightLog> get weightLogs;
  WeightLog? weightOn(DateTime date);
  double? get currentWeightKg;
  Future<WeightLog> logWeight({
    required double weightKg,
    required DateTime date,
    String? notes,
  });
  Future<void> deleteWeight(String id);

  List<BodyMeasurement> measurements(MeasurementMetric metric);
  Future<void> logMeasurement({
    required MeasurementMetric metric,
    required double value,
    required DateTime date,
  });
  Future<void> deleteMeasurement(String id);
}

abstract interface class SummaryRepository {
  DailySummary daily(DateTime date);
  List<HistoryDay> history({required DateTime from, required DateTime to});
  ProgressSummary progress({required DateTime from, required DateTime to});
  bool isRestDay(DateTime date);
  Future<void> setRestDay(DateTime date, bool isRest);

  /// Días con al menos un registro, para la densidad del selector de fecha.
  Set<String> get daysWithRecords;
}

abstract interface class HealthRepository {
  HealthIntegration get integration;

  /// Solo se muestra en Android (D-21).
  bool get isPlatformSupported;
  Future<void> connect();
  Future<void> disconnect();
  Future<HealthSyncResult> sync();
  Future<void> deleteImported();
  Future<void> resolveDuplicate(
    DuplicateCandidate candidate,
    DuplicateResolution resolution,
  );
  List<DuplicateCandidate> get pendingReviews;
}

abstract interface class AiPhotoRepository {
  /// Cuota diaria de análisis (D-18).
  int get quotaLimit;
  int get quotaUsed;
  Future<AiAnalysis> analyze({required String photoPath});
}

/// Qué trajo un archivo de respaldo, para poder contarlo antes y después.
class BackupSummary {
  const BackupSummary({
    required this.meals,
    required this.activities,
    required this.weights,
    required this.measurements,
  });

  final int meals;
  final int activities;
  final int weights;
  final int measurements;

  String get description =>
      '$meals ${meals == 1 ? 'comida' : 'comidas'}, '
      '$activities ${activities == 1 ? 'actividad' : 'actividades'}, '
      '$weights ${weights == 1 ? 'peso' : 'pesos'} y '
      '$measurements ${measurements == 1 ? 'medida' : 'medidas'}';
}

/// Respaldo manual mientras no exista la nube (Supabase).
///
/// Es la única red de seguridad hoy: sin esto, perder el teléfono es perder
/// todo el historial.
abstract interface class BackupRepository {
  /// Documento JSON con todo lo del usuario.
  String exportJson();

  /// Lee un respaldo **sin aplicarlo**, para poder mostrar qué contiene antes
  /// de reemplazar lo que hay.
  BackupSummary inspectBackup(String json);

  /// Reemplaza el contenido local por el del respaldo.
  Future<BackupSummary> importJson(String json);
}

abstract interface class ConnectivityRepository {
  bool get isOffline;
  int get pendingCount;
  Future<void> setOffline(bool value);

  /// Vacía la cola: todo lo pendiente pasa a sincronizado.
  Future<void> flushQueue();
}
