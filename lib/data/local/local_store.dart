import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/feature_flags.dart';
import '../../core/utils/dates.dart';
import '../../domain/enums/enums.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/body.dart';
import '../../domain/models/food.dart';
import '../../domain/models/goal.dart';
import '../../domain/models/meal.dart';
import '../../domain/models/reminder.dart';
import '../../domain/models/restore_outcome.dart';
import '../../domain/models/sleep.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/water.dart';
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
  List<WaterLog> waterLogs = <WaterLog>[];
  List<SleepLog> sleepLogs = <SleepLog>[];
  List<Reminder> reminders = <Reminder>[
    for (final k in ReminderKind.values) Reminder.byDefault(k),
  ];
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

  /// ⚠️ Siempre `false`: no hay detección real de conectividad (ver el
  /// doc de `LocalRepository.isOffline`, que es la puerta de entrada real).
  /// El interruptor de desarrollo que antes lo ponía en `true` se sacó de la
  /// interfaz por ser una herramienta peligrosa en manos de quien usa la app.
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
    final live = weightLogs.where((w) => !w.isDeleted);
    if (live.isEmpty) return null;
    final sorted = <WeightLog>[...live]
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
    final semilla = (jsonDecode(foodsRaw) as List<dynamic>)
        .map((e) => Food.fromJson(e as Map<String, dynamic>))
        .toList();

    // La tabla de composición de alimentos argentinos viaja adentro del APK.
    //
    // Es una referencia estática y pública: no cambia entre usuarios, no
    // necesita cuenta y no tiene por qué salir a la red. Al estar acá, buscar
    // "milanesa" o "arroz" anda sin conexión y al instante, que es justo lo
    // que Open Food Facts no puede dar — su base son productos envasados con
    // código de barras, y casi nada de lo que se cocina en una casa tiene uno.
    //
    // Un registro que no se pueda leer no puede tumbar el catálogo entero.
    final argentinos = <Food>[];
    try {
      final raw = await rootBundle.loadString('assets/data/argenfoods.json');
      for (final entry in jsonDecode(raw) as List<dynamic>) {
        try {
          argentinos.add(Food.fromJson(entry as Map<String, dynamic>));
        } on Object {
          continue;
        }
      }
    } on Object {
      // Sin la tabla local la app sigue andando con el resto de las fuentes.
    }

    catalogFoods = <Food>[...semilla, ...argentinos];
  }

  /// Copia intacta del documento cuando no se pudo leer del todo.
  ///
  /// Existe porque la versión anterior hacía `remove()` sobre el documento que
  /// no había podido interpretar: un solo registro raro y se borraba **todo**,
  /// sin copia y sin aviso. Ahora nunca se borra nada; lo que no se entiende se
  /// aparta acá y se puede recuperar a mano.
  static const String _quarantineKey = 'nutrimat.local_store.v1.quarantine';

  /// Cómo salió la última lectura. La UI lo usa para avisar en vez de fingir
  /// que el teléfono estaba vacío.
  RestoreOutcome lastRestore = const RestoreOutcome.clean();

  Future<void> _loadOrSeed() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw == null) return;

    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      decoded = null;
    }

    if (decoded == null) {
      // JSON ilegible. No se borra: se aparta la copia tal cual vino y se
      // arranca vacío, para que la app abra y se pueda restaurar de la nube.
      await _prefs!.setString(_quarantineKey, raw);
      lastRestore = const RestoreOutcome(
        unreadableDocument: true,
        quarantined: true,
      );
      profile = null;
      return;
    }

    lastRestore = _restore(decoded);

    // Un teléfono que ya tiene los datos sembrados de una versión anterior.
    //
    // Que la siembra esté apagada no alcanza: los 30 días de "Camila" ya están
    // escritos en el documento de este teléfono, y en cuanto se abra sesión se
    // reconcilian contra las tablas y suben a una cuenta de verdad. Se
    // reconocen por el id del perfil —es lo único que la siembra deja marcado— y
    // se van enteros, porque no hay nada ahí que sea de nadie.
    if (profile?.id == demoProfileId && !FeatureFlags.seededDemoData) {
      reset(newProfile: UserProfile.empty(profile!.id));
      profile = null;
      await _prefs!.remove(_prefsKey);
      lastRestore = const RestoreOutcome.clean();
      return;
    }

    // Se guardó algo que no entendimos entero: la copia original queda
    // apartada antes de que la primera escritura la pise.
    if (!lastRestore.isClean) {
      await _prefs!.setString(_quarantineKey, raw);
      lastRestore = lastRestore.copyWithQuarantined();
    }
  }

  /// El documento que no se pudo leer, si hubo uno. Para recuperarlo a mano.
  String? get quarantinedDocument => _prefs?.getString(_quarantineKey);

  Future<void> clearQuarantine() async => _prefs?.remove(_quarantineKey);

  /// Siembra los datos simulados (modo demo, D-15).
  ///
  /// **No hace nada salvo mientras se desarrolla sin servidor**
  /// ([FeatureFlags.seededDemoData]). El guardia está acá y no solo en quien
  /// llama porque el daño no lo hace la pantalla que siembra: lo hace la sesión
  /// que se abre después, que se lleva estos 30 días inventados a las tablas de
  /// una cuenta real y ahí ya no se distinguen de los verdaderos.
  void seed() {
    if (!FeatureFlags.seededDemoData) return;
    final data = buildSeed(types: activityTypes, catalog: catalogFoods);
    profile = data.profile;
    goals = <Goal>[data.goal];
    meals = data.meals;
    activities = data.activities;
    weightLogs = data.weightLogs;
    waterLogs = <WaterLog>[];
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
    waterLogs = <WaterLog>[];
    sleepLogs = <SleepLog>[];
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

  /// Lee el documento **sin propagar excepciones**.
  ///
  /// Antes cualquier registro con un campo raro tiraba y se perdía el
  /// documento entero: una comida mal formada se llevaba puestos el peso, las
  /// medidas y el historial. Ahora cada registro se lee por separado y lo que
  /// no se entiende se saltea y se cuenta. Perder una comida es un problema;
  /// perder el año entero es otra cosa.
  RestoreOutcome _restore(Map<String, dynamic> j) {
    final skipped = <String, int>{};

    List<T> list<T>(String key, T Function(Map<String, dynamic>) fromJson) {
      final raw = j[key];
      if (raw is! List) return <T>[];
      final out = <T>[];
      var bad = 0;
      for (final e in raw) {
        try {
          out.add(fromJson(e as Map<String, dynamic>));
        } on Object {
          bad++;
        }
      }
      if (bad > 0) skipped[key] = bad;
      return out;
    }

    // El perfil aparte: es lo único cuya ausencia cambia a dónde arranca la
    // app, así que si falla se dice, no se finge que nunca hubo cuenta.
    var profileFailed = false;
    try {
      profile = j['profile'] == null
          ? null
          : UserProfile.fromJson(j['profile'] as Map<String, dynamic>);
    } on Object {
      profile = null;
      profileFailed = true;
    }

    goals = list('goals', Goal.fromJson);
    meals = list('meals', Meal.fromJson);
    activities = list('activities', Activity.fromJson);
    weightLogs = list('weightLogs', WeightLog.fromJson);
    waterLogs = list('waterLogs', WaterLog.fromJson);
    sleepLogs = list('sleepLogs', SleepLog.fromJson);
    final storedReminders = list('reminders', Reminder.fromJson);
    // Si falta alguno —porque el respaldo es de una versión anterior— se
    // completa con el que corresponde apagado.
    reminders = <Reminder>[
      for (final k in ReminderKind.values)
        storedReminders.firstWhere(
          (r) => r.kind == k,
          orElse: () => Reminder.byDefault(k),
        ),
    ];
    measurements = list('measurements', BodyMeasurement.fromJson);
    activityGoals = list('activityGoals', ActivityGoal.fromJson);
    templates = list('templates', ExerciseTemplate.fromJson);
    userFoods = list('userFoods', Food.fromJson);
    cachedFoods = list('cachedFoods', Food.fromJson);
    customTypes = list('customTypes', ActivityType.fromJson);

    recentFoodIds = <String>[
      for (final e in (j['recentFoodIds'] as List<dynamic>? ?? <dynamic>[]))
        if (e is String) e,
    ];
    restDays = <String>{
      for (final e in (j['restDays'] as List<dynamic>? ?? <dynamic>[]))
        if (e is String) e,
    };

    try {
      if (j['integration'] != null) {
        integration = HealthIntegration.fromJson(
          j['integration'] as Map<String, dynamic>,
        );
      }
    } on Object {
      // El estado de una integración no conectada no vale perder nada.
    }

    offline = j['offline'] as bool? ?? false;
    historyFilters =
        (j['historyFilters'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    hydrateActivities();

    return RestoreOutcome(
      profileFailed: profileFailed,
      skippedBySection: skipped,
    );
  }

  /// El documento completo del usuario. Es lo que se persiste y también lo
  /// que viaja en el archivo de respaldo.
  Map<String, dynamic> toDocument() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'profile': profile?.toJson(),
    'goals': goals.map((e) => e.toJson()).toList(),
    'meals': meals.map((e) => e.toJson()).toList(),
    'activities': activities.map((e) => e.toJson()).toList(),
    'weightLogs': weightLogs.map((e) => e.toJson()).toList(),
    'waterLogs': waterLogs.map((e) => e.toJson()).toList(),
    'reminders': reminders.map((e) => e.toJson()).toList(),
    'sleepLogs': sleepLogs.map((e) => e.toJson()).toList(),
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
  RestoreOutcome restoreDocument(Map<String, dynamic> document) {
    lastRestore = _restore(document);
    return lastRestore;
  }

  /// Si hay algo cargado por la persona. Es la condición que decide si se
  /// puede pisar el respaldo remoto, así que vive acá y no en la UI.
  bool get hasUserData =>
      meals.isNotEmpty ||
      activities.isNotEmpty ||
      weightLogs.isNotEmpty ||
      measurements.isNotEmpty ||
      waterLogs.isNotEmpty ||
      sleepLogs.isNotEmpty ||
      userFoods.isNotEmpty;

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
