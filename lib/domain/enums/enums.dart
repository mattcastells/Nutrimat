// Enums del contrato canónico (10-types-and-interfaces.ts).
//
// Los identificadores van en inglés; las etiquetas visibles en español
// rioplatense (D-19).

enum BiologicalSex {
  male('male', 'Masculino'),
  female('female', 'Femenino'),
  unspecified('unspecified', 'Prefiero no decirlo');

  const BiologicalSex(this.wire, this.label);
  final String wire;
  final String label;

  static BiologicalSex fromWire(String w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => unspecified);
}

enum ActivityLevel {
  sedentary(
    'sedentary',
    1.200,
    'Sedentario',
    'Trabajo de oficina, poco movimiento',
  ),
  light(
    'light',
    1.375,
    'Ligero',
    'Camina bastante o entrena 1–2 veces por semana',
  ),
  moderate('moderate', 1.550, 'Moderado', 'Entrena 3–4 veces por semana'),
  high('high', 1.725, 'Alto', 'Entrena 5–6 veces por semana'),
  veryHigh(
    'very_high',
    1.900,
    'Muy alto',
    'Trabajo físico o entrenamiento diario intenso',
  );

  const ActivityLevel(this.wire, this.factor, this.label, this.description);
  final String wire;

  /// El factor **ya incluye** la actividad habitual: por eso el crédito de
  /// ejercicio por defecto es 0 % (D-02).
  final double factor;
  final String label;
  final String description;

  static ActivityLevel fromWire(String w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => moderate);
}

enum UnitSystem {
  metric('metric', 'Métrico (kg · cm · km)'),
  imperial('imperial', 'Imperial (lb · ft · mi)');

  const UnitSystem(this.wire, this.label);
  final String wire;
  final String label;
}

enum ThemeModeSetting {
  light('light', 'Claro'),
  dark('dark', 'Oscuro'),
  system('system', 'Según el sistema');

  const ThemeModeSetting(this.wire, this.label);
  final String wire;
  final String label;
}

enum GoalType {
  lose('lose', 'Bajar de peso'),
  maintain('maintain', 'Mantener'),
  gain('gain', 'Subir de peso'),
  // Subir de peso y ganar músculo comparten la dirección pero no el plan: el
  // superávit es igual de chico, la proteína sube a 2 g/kg y el objetivo de
  // actividad pasa a contar entrenamientos de fuerza.
  gainMuscle('gain_muscle', 'Ganar músculo');

  const GoalType(this.wire, this.label);
  final String wire;
  final String label;

  /// Los dos objetivos que suman peso, para las reglas que no distinguen.
  bool get isSurplus => this == gain || this == gainMuscle;

  static GoalType fromWire(String w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => maintain);
}

enum TargetMethod {
  calculated('calculated', 'Calculado'),
  manual('manual', 'Ingresado a mano');

  const TargetMethod(this.wire, this.label);
  final String wire;
  final String label;
}

enum MealSlot {
  breakfast('breakfast', 'Desayuno'),
  lunch('lunch', 'Almuerzo'),
  dinner('dinner', 'Cena'),
  snack('snack', 'Snacks');

  const MealSlot(this.wire, this.label);
  final String wire;
  final String label;

  static MealSlot fromWire(String w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => snack);

  /// Slot sugerido según la hora, para precargar el selector (F-06 paso 5).
  static MealSlot forHour(int hour) {
    if (hour < 11) return breakfast;
    if (hour < 16) return lunch;
    if (hour < 22) return dinner;
    return snack;
  }
}

enum MealSource {
  manual('manual', 'Manual'),
  aiPhoto('ai_photo', 'Estimado por IA'),
  // Misma estimación, sin foto: sale de una descripción escrita. Se distingue
  // de `aiPhoto` porque no hay imagen que adjuntar ni que volver a mirar.
  aiText('ai_text', 'Estimado por IA'),
  barcode('barcode', 'Código de barras'),
  duplicate('duplicate', 'Duplicado');

  const MealSource(this.wire, this.label);
  final String wire;
  final String label;

  bool get isAi => this == aiPhoto || this == aiText;
}

enum FoodSource {
  user('user', 'Tuyo'),
  // Tabla de Composición de Alimentos Argentinos (UNLu, proyecto INFOODS de
  // FAO). Es la referencia local: cortes de carne argentinos, aceites de acá,
  // frutas de estación. Viaja dentro del APK, así que anda sin conexión.
  argenfoods('argenfoods', 'ARGENFOODS'),
  usda('usda', 'USDA'),
  off('off', 'Open Food Facts'),
  ai('ai', 'Estimado por IA');

  const FoodSource(this.wire, this.label);
  final String wire;
  final String label;

  /// De dónde salen los números, para mostrarlo sin abreviaturas crípticas.
  String get attribution => switch (this) {
    FoodSource.argenfoods => 'Tabla de composición de alimentos argentinos '
        '(ARGENFOODS, UNLu)',
    FoodSource.usda => 'USDA FoodData Central',
    FoodSource.off => 'Open Food Facts',
    FoodSource.ai => 'Estimado por IA',
    FoodSource.user => 'Cargado por vos',
  };
}

enum ActivityCategory {
  cardio('cardio', 'Cardio'),
  strength('strength', 'Fuerza'),
  mobility('mobility', 'Movilidad'),
  sports('sports', 'Deportes'),
  other('other', 'Otras');

  const ActivityCategory(this.wire, this.label);
  final String wire;
  final String label;

  static ActivityCategory fromWire(String w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => other);
}

enum Intensity {
  light('light', 'Suave'),
  moderate('moderate', 'Moderada'),
  vigorous('vigorous', 'Intensa');

  const Intensity(this.wire, this.label);
  final String wire;
  final String label;

  static Intensity fromWire(String w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => moderate);
}

enum EstimationMethod {
  met('met'),
  provider('provider'),
  userOverride('user_override'),
  metRecalculated('met_recalculated'),
  pace('pace');

  const EstimationMethod(this.wire);
  final String wire;

  static EstimationMethod fromWire(String w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => met);
}

enum ActivitySourceType {
  manual('manual', 'Manual'),
  imported('imported', 'Importado'),
  template('template', 'Plantilla'),
  duplicated('duplicated', 'Duplicado');

  const ActivitySourceType(this.wire, this.label);
  final String wire;
  final String label;
}

/// Health Connect es la única integración de salud del MVP (D-21).
enum HealthProvider {
  healthConnect('health_connect', 'Health Connect');

  const HealthProvider(this.wire, this.label);
  final String wire;
  final String label;
}

enum IntegrationStatus {
  notConnected('not_connected', 'Sin conectar'),
  connecting('connecting', 'Conectando'),
  connected('connected', 'Conectada'),
  syncing('syncing', 'Sincronizando'),
  permissionDenied('permission_denied', 'Permisos denegados'),
  providerUnavailable('provider_unavailable', 'No disponible'),
  error('error', 'Con error');

  const IntegrationStatus(this.wire, this.label);
  final String wire;
  final String label;
}

enum SyncStatus {
  synced('synced', 'Sincronizado'),
  pending('pending', 'Pendiente'),
  syncing('syncing', 'Sincronizando'),
  error('error', 'Sin sincronizar'),
  needsReview('needs_review', 'Revisar');

  const SyncStatus(this.wire, this.label);
  final String wire;
  final String label;
}

enum ActivityGoalType {
  activeMinutes('active_minutes', 'Minutos activos', 'minutes'),
  sessions('sessions', 'Sesiones', 'count'),
  steps('steps', 'Pasos', 'steps'),
  distance('distance', 'Distancia', 'meters'),
  strengthSessions('strength_sessions', 'Entrenamientos de fuerza', 'count'),
  activeDays('active_days', 'Días activos', 'days');

  const ActivityGoalType(this.wire, this.label, this.unit);
  final String wire;
  final String label;
  final String unit;
}

enum GoalPeriod {
  day('day', 'por día'),
  week('week', 'por semana');

  const GoalPeriod(this.wire, this.label);
  final String wire;
  final String label;
}

/// Cómo se agrupan las medidas corporales en pantalla.
///
/// Son tres cosas distintas que se toman con instrumentos distintos: la cinta
/// métrica, el plicómetro y la balanza de bioimpedancia. Mezclarlas en una sola
/// lista de veinte chips no se puede usar.
enum MeasurementGroup {
  perimeters('Perímetros', 'Con cinta métrica, en centímetros'),
  skinfolds(
    'Pliegues cutáneos',
    'Con plicómetro, en milímetros. Siempre del mismo lado y con la misma '
        'técnica: comparar contra vos mismo es lo único que tiene sentido.',
  ),
  composition(
    'Bioimpedancia',
    'Lo que devuelve la balanza. Es una estimación indirecta: cambia con la '
        'hidratación y con la hora del día.',
  );

  const MeasurementGroup(this.label, this.help);
  final String label;
  final String help;
}

/// Medidas corporales, en el orden de la planilla que entrega una nutricionista
/// (perímetros → pliegues → bioimpedancia).
///
/// El peso y la talla **no** están acá: el peso tiene su propio registro diario
/// (uno por día, D-16) y la altura vive en el perfil corporal, porque alimenta
/// el cálculo de BMR. Duplicarlos daría dos números que se contradicen.
enum MeasurementMetric {
  // ── Perímetros (cm) ────────────────────────────────────────────────────
  arm(
    'arm',
    'Brazo relajado',
    'cm',
    MeasurementGroup.perimeters,
    min: 10,
    max: 100,
  ),
  armFlexed(
    'arm_flexed',
    'Brazo flexionado',
    'cm',
    MeasurementGroup.perimeters,
    min: 10,
    max: 100,
  ),
  chest('chest', 'Pecho', 'cm', MeasurementGroup.perimeters, min: 40, max: 200),
  waist(
    'waist',
    'Cintura (mínima)',
    'cm',
    MeasurementGroup.perimeters,
    min: 40,
    max: 200,
  ),
  hip(
    'hip',
    'Cadera (máxima)',
    'cm',
    MeasurementGroup.perimeters,
    min: 40,
    max: 200,
  ),
  thigh(
    'thigh',
    'Muslo',
    'cm',
    MeasurementGroup.perimeters,
    min: 20,
    max: 120,
  ),
  calf(
    'calf',
    'Pantorrilla (máxima)',
    'cm',
    MeasurementGroup.perimeters,
    min: 15,
    max: 80,
  ),
  neck('neck', 'Cuello', 'cm', MeasurementGroup.perimeters, min: 20, max: 80),

  // ── Pliegues cutáneos (mm) ─────────────────────────────────────────────
  tricepsFold(
    'triceps_fold',
    'Tríceps',
    'mm',
    MeasurementGroup.skinfolds,
    min: 1,
    max: 80,
  ),
  subscapularFold(
    'subscapular_fold',
    'Subescapular',
    'mm',
    MeasurementGroup.skinfolds,
    min: 1,
    max: 80,
  ),
  bicepsFold(
    'biceps_fold',
    'Bíceps',
    'mm',
    MeasurementGroup.skinfolds,
    min: 1,
    max: 80,
  ),
  iliacCrestFold(
    'iliac_crest_fold',
    'Cresta ilíaca',
    'mm',
    MeasurementGroup.skinfolds,
    min: 1,
    max: 80,
  ),
  supraspinaleFold(
    'supraspinale_fold',
    'Supraespinal',
    'mm',
    MeasurementGroup.skinfolds,
    min: 1,
    max: 80,
  ),
  abdominalFold(
    'abdominal_fold',
    'Abdominal',
    'mm',
    MeasurementGroup.skinfolds,
    min: 1,
    max: 80,
  ),
  thighFold(
    'thigh_fold',
    'Muslo medial',
    'mm',
    MeasurementGroup.skinfolds,
    min: 1,
    max: 80,
  ),

  // ── Bioimpedancia ──────────────────────────────────────────────────────
  bodyFatPct(
    'body_fat_pct',
    'Grasa corporal',
    'pct',
    MeasurementGroup.composition,
    min: 3,
    max: 70,
  ),
  musclePct(
    'muscle_pct',
    'Músculo',
    'pct',
    MeasurementGroup.composition,
    min: 10,
    max: 70,
  ),
  muscleKg(
    'muscle_kg',
    'Músculo',
    'kg',
    MeasurementGroup.composition,
    min: 5,
    max: 120,
  ),
  visceralFat(
    'visceral_fat',
    'Grasa visceral',
    'index',
    MeasurementGroup.composition,
    min: 1,
    max: 60,
  );

  const MeasurementMetric(
    this.wire,
    this.label,
    this.unit,
    this.group, {
    required this.min,
    required this.max,
  });

  final String wire;
  final String label;

  /// Unidad de almacenamiento: `cm`, `mm`, `kg`, `pct` o `index`.
  final String unit;
  final MeasurementGroup group;

  /// Rango aceptado. No es una regla clínica: es el filtro para atajar un cero
  /// de más al tipear.
  final double min;
  final double max;

  /// Cómo se muestra la unidad.
  String get unitLabel => switch (unit) {
    'pct' => '%',
    'index' => '',
    final u => u,
  };

  /// Dos metros con el mismo nombre en distinta unidad ("Músculo" en % y en
  /// kg) necesitan desambiguarse en las listas.
  String get longLabel =>
      unitLabel.isEmpty ? label : '$label ($unitLabel)';

  static MeasurementMetric fromWire(String w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => waist);

  static List<MeasurementMetric> inGroup(MeasurementGroup group) =>
      values.where((m) => m.group == group).toList();

  /// Los pliegues que entran en la sumatoria.
  static List<MeasurementMetric> get folds => inGroup(MeasurementGroup.skinfolds);
}

enum AiAnalysisStatus {
  pending('pending'),
  completed('completed'),
  failed('failed'),
  accepted('accepted'),
  discarded('discarded');

  const AiAnalysisStatus(this.wire);
  final String wire;
}

/// Origen visible de un dato: `DataOriginBadge` (05-component-library §1).
enum DataOrigin {
  manual('Manual'),
  imported('Importado'),
  ai('Estimado por IA');

  const DataOrigin(this.label);
  final String label;
}

/// Modos de la pantalla de registro de actividad (`/activity/new?mode=…`).
enum ActivityFormMode {
  duration('duration'),
  distance('distance'),
  walkRun('walk_run'),
  strength('strength'),
  custom('custom');

  const ActivityFormMode(this.wire);
  final String wire;

  static ActivityFormMode fromWire(String? w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => duration);
}
