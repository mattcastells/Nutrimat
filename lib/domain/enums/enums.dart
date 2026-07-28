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
  gain('gain', 'Subir de peso');

  const GoalType(this.wire, this.label);
  final String wire;
  final String label;

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
  barcode('barcode', 'Código de barras'),
  duplicate('duplicate', 'Duplicado');

  const MealSource(this.wire, this.label);
  final String wire;
  final String label;
}

enum FoodSource {
  user('user', 'Tuyo'),
  usda('usda', 'USDA'),
  off('off', 'Open Food Facts'),
  ai('ai', 'Estimado por IA');

  const FoodSource(this.wire, this.label);
  final String wire;
  final String label;
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

enum MeasurementMetric {
  waist('waist', 'Cintura', 'cm'),
  hip('hip', 'Cadera', 'cm'),
  chest('chest', 'Pecho', 'cm'),
  arm('arm', 'Brazo', 'cm'),
  thigh('thigh', 'Muslo', 'cm'),
  neck('neck', 'Cuello', 'cm'),
  bodyFatPct('body_fat_pct', 'Grasa corporal', 'pct');

  const MeasurementMetric(this.wire, this.label, this.unit);
  final String wire;
  final String label;
  final String unit;
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
