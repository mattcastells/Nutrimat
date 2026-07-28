import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/dates.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/body.dart';
import '../../domain/models/food.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/meal.dart';
import '../../domain/models/user_profile.dart';
import '../mock/seed.dart';

/// Base local: la fuente de verdad para la UI (13-state-management.md).
///
/// En esta etapa el almacenamiento es un documento JSON en preferencias, con
/// la misma forma que va a tener el esquema de Drift/SQLite. La red todavía no
/// participa: cada escritura queda `synced` salvo que el modo sin conexión
/// esté activo, en cuyo caso queda `pending` y suma a la cola.
class LocalStore {
  LocalStore._();

  static const String _prefsKey = 'nutrimat.local_store.v1';

  static Future<LocalStore> open() async {
    final store = LocalStore._();
    await store._loadCatalogs();
    await store._loadOrSeed();
    return store;
  }

  SharedPreferences? _prefs;

  // Catálogos de solo lectura.
  List<ActivityType> activityTypes = <ActivityType>[];
  List<Food> catalogFoods = <Food>[];

  // Datos del usuario.
  UserProfile? profile;
  List<Goal> goals = <Goal>[];
  List<Meal> meals = <Meal>[];
  List<Activity> activities = <Activity>[];
  List<WeightLog> weightLogs = <WeightLog>[];
  List<BodyMeasurement> measurements = <BodyMeasurement>[];
  List<ActivityGoal> activityGoals = <ActivityGoal>[];
  List<ExerciseTemplate> templates = <ExerciseTemplate>[];
  List<Food> userFoods = <Food>[];

  /// Espejo de `foods_cache`: lo que se trajo del catálogo externo queda
  /// guardado para que la búsqueda siga andando sin conexión (13-state §4).
  List<Food> cachedFoods = <Food>[];
  List<String> recentFoodIds = <String>[];

  static const int _maxCachedFoods = 500;
  Set<String> restDays = <String>{};
  List<ActivityType> customTypes = <ActivityType>[];
  HealthIntegration integration = const HealthIntegration(
    id: 'health-connect',
    provider: HealthProvider.healthConnect,
    status: IntegrationStatus.notConnected,
  );

  /// Modo sin conexión simulado: las escrituras quedan `pending` y se muestran
  /// el banner y los badges de F-07/F-08.
  bool offline = false;

  /// Filtros de Historial recordados en preferencias (S-21).
  Map<String, dynamic> historyFilters = <String, dynamic>{};

  int get pendingCount =>
      meals.where((m) => m.syncStatus == SyncStatus.pending).length +
      activities.where((a) => a.syncStatus == SyncStatus.pending).length +
      weightLogs.where((w) => w.syncStatus == SyncStatus.pending).length;

  SyncStatus get writeStatus =>
      offline ? SyncStatus.pending : SyncStatus.synced;

  List<Food> get allFoods => <Food>[
    ...userFoods,
    ...cachedFoods,
    ...catalogFoods,
  ];

  /// Guarda lo consultado en el catálogo externo, sin duplicar por id.
  void cacheFoods(List<Food> foods) {
    final byId = <String, Food>{
      for (final food in cachedFoods) food.id: food,
      for (final food in foods) food.id: food,
    };
    final merged = byId.values.toList();
    cachedFoods = merged.length <= _maxCachedFoods
        ? merged
        : merged.sublist(merged.length - _maxCachedFoods);
  }

  List<ActivityType> get allTypes => <ActivityType>[
    ...activityTypes,
    ...customTypes,
  ];

  ActivityType? typeById(String id) {
    for (final t in allTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  ActivityType? typeBySlug(String slug) {
    for (final t in allTypes) {
      if (t.slug == slug) return t;
    }
    return null;
  }

  /// Peso usado por las fórmulas MET: el último registro; si no hay ninguno,
  /// el del perfil (S-07 del PRD).
  double? get currentWeightKg {
    if (weightLogs.isEmpty) return null;
    final sorted = <WeightLog>[...weightLogs]
      ..sort((a, b) => b.localDate.compareTo(a.localDate));
    return sorted.first.weightKg;
  }

  Goal? goalForDate(DateTime date) {
    final d = dateOnly(date);
    for (final g in goals) {
      final startsOk = !g.startsOn.isAfter(d);
      final endsOk = g.endsOn == null || !g.endsOn!.isBefore(d);
      if (startsOk && endsOk) return g;
    }
    return goals.isEmpty ? null : goals.last;
  }

  Goal? get currentGoal {
    for (final g in goals) {
      if (g.isCurrent) return g;
    }
    return goals.isEmpty ? null : goals.last;
  }

  bool isRestDay(DateTime date) => restDays.contains(isoDate(date));

  // ── Carga ──────────────────────────────────────────────────────────────

  Future<void> _loadCatalogs() async {
    // Los valores MET viven fuera del código (D-06): este archivo es el seed
    // de `activity_types` y se reemplaza por la tabla al conectar la base.
    final metRaw = await rootBundle.loadString('assets/mock/met_catalog.json');
    activityTypes = (jsonDecode(metRaw) as List<dynamic>)
        .map((e) => ActivityType.fromJson(e as Map<String, dynamic>))
        .toList();

    final foodsRaw = await rootBundle.loadString('assets/mock/foods.json');
    catalogFoods = (jsonDecode(foodsRaw) as List<dynamic>)
        .map((e) => Food.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadOrSeed() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw == null) return;

    try {
      _restore(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Un documento corrupto no puede dejar la app sin arrancar: se descarta
      // y se vuelve a empezar desde la bienvenida.
      await _prefs!.remove(_prefsKey);
      profile = null;
    }
  }

  /// Siembra los datos simulados (modo demo, D-15).
  void seed() {
    final data = buildSeed(types: activityTypes, catalog: catalogFoods);
    profile = data.profile;
    goals = <Goal>[data.goal];
    meals = data.meals;
    activities = data.activities;
    weightLogs = data.weightLogs;
    measurements = data.measurements;
    activityGoals = data.activityGoals;
    templates = data.templates;
    restDays = data.restDays;
    userFoods = data.userFoods;
    recentFoodIds = <String>[
      'usda:1750340',
      'usda:1750347',
      'off:7790070410016',
      'usda:1750341',
    ];
    hydrateActivities();
  }

  /// Arranca vacío: es lo que ve alguien que recién crea su cuenta.
  void reset({required UserProfile newProfile}) {
    profile = newProfile;
    goals = <Goal>[];
    meals = <Meal>[];
    activities = <Activity>[];
    weightLogs = <WeightLog>[];
    measurements = <BodyMeasurement>[];
    activityGoals = <ActivityGoal>[];
    templates = <ExerciseTemplate>[];
    restDays = <String>{};
    userFoods = <Food>[];
    recentFoodIds = <String>[];
    customTypes = <ActivityType>[];
    integration = const HealthIntegration(
      id: 'health-connect',
      provider: HealthProvider.healthConnect,
      status: IntegrationStatus.notConnected,
    );
  }

  /// Rellena `activityType` en cada actividad (hidratación de lectura).
  void hydrateActivities() {
    activities = activities
        .map(
          (a) => a.activityType != null
              ? a
              : a.copyWith(activityType: typeById(a.activityTypeId)),
        )
        .toList();
  }

  void _restore(Map<String, dynamic> j) {
    profile = j['profile'] == null
        ? null
        : UserProfile.fromJson(j['profile'] as Map<String, dynamic>);
    goals = _list(j['goals'], Goal.fromJson);
    meals = _list(j['meals'], Meal.fromJson);
    activities = _list(j['activities'], Activity.fromJson);
    weightLogs = _list(j['weightLogs'], WeightLog.fromJson);
    measurements = _list(j['measurements'], BodyMeasurement.fromJson);
    activityGoals = _list(j['activityGoals'], ActivityGoal.fromJson);
    templates = _list(j['templates'], ExerciseTemplate.fromJson);
    userFoods = _list(j['userFoods'], Food.fromJson);
    cachedFoods = _list(j['cachedFoods'], Food.fromJson);
    customTypes = _list(j['customTypes'], ActivityType.fromJson);
    recentFoodIds = (j['recentFoodIds'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => e as String)
        .toList();
    restDays = (j['restDays'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => e as String)
        .toSet();
    if (j['integration'] != null) {
      integration = HealthIntegration.fromJson(
        j['integration'] as Map<String, dynamic>,
      );
    }
    offline = j['offline'] as bool? ?? false;
    historyFilters =
        (j['historyFilters'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    hydrateActivities();
  }

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) => (raw as List<dynamic>? ?? <dynamic>[])
      .map((e) => fromJson(e as Map<String, dynamic>))
      .toList();

  /// El documento completo del usuario. Es lo que se persiste y también lo
  /// que viaja en el archivo de respaldo.
  Map<String, dynamic> toDocument() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'profile': profile?.toJson(),
    'goals': goals.map((e) => e.toJson()).toList(),
    'meals': meals.map((e) => e.toJson()).toList(),
    'activities': activities.map((e) => e.toJson()).toList(),
    'weightLogs': weightLogs.map((e) => e.toJson()).toList(),
    'measurements': measurements.map((e) => e.toJson()).toList(),
    'activityGoals': activityGoals.map((e) => e.toJson()).toList(),
    'templates': templates.map((e) => e.toJson()).toList(),
    'userFoods': userFoods.map((e) => e.toJson()).toList(),
    'cachedFoods': cachedFoods.map((e) => e.toJson()).toList(),
    'customTypes': customTypes.map((e) => e.toJson()).toList(),
    'recentFoodIds': recentFoodIds,
    'restDays': restDays.toList(),
    'integration': integration.toJson(),
    'offline': offline,
    'historyFilters': historyFilters,
  };

  /// Reemplaza todo el contenido local por el de un documento.
  void restoreDocument(Map<String, dynamic> document) => _restore(document);

  /// Versión del formato del documento. Sube cuando cambie de forma y haya que
  /// migrar un respaldo viejo.
  static const int schemaVersion = 1;

  /// Persiste el documento completo. Es barato para el volumen del MVP y se
  /// reemplaza por escrituras por tabla cuando entre Drift.
  Future<void> persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_prefsKey, jsonEncode(toDocument()));
  }
}
