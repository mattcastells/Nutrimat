/// Los dos recordatorios que existen. No hay más, y no hay ninguno de
/// marketing: la app avisa de lo que la persona pidió que le recuerden.
enum ReminderKind {
  water(
    'water',
    'Tomar agua',
    'Recordá tomar agua',
    'Un vaso ahora y seguís en camino.',
    <int>[10, 14, 18],
  ),
  meals(
    'meals',
    'Cargar lo que comiste',
    'Recordá cargar lo que comiste',
    '¿Registraste todo lo de hoy?',
    <int>[21],
  );

  const ReminderKind(
    this.wire,
    this.label,
    this.title,
    this.body,
    this.defaultHours,
  );

  final String wire;

  /// Cómo se llama en Ajustes.
  final String label;

  /// Título de la notificación.
  final String title;
  final String body;

  /// Horas por defecto. El agua repite porque un solo aviso al día no sirve
  /// para algo que se hace de a poco; la comida alcanza con uno a la noche.
  final List<int> defaultHours;

  static ReminderKind fromWire(String? w) => ReminderKind.values.firstWhere(
    (k) => k.wire == w,
    orElse: () => ReminderKind.water,
  );
}

/// Hora del día en la que suena un recordatorio.
class ReminderTime implements Comparable<ReminderTime> {
  const ReminderTime(this.hour, this.minute);

  final int hour;
  final int minute;

  /// Id estable para el sistema: cada notificación programada necesita uno, y
  /// tiene que repetirse entre arranques para poder reprogramarla o cancelarla.
  int idFor(ReminderKind kind) =>
      kind.index * 1000 + hour * 60 + minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(ReminderTime other) =>
      (hour * 60 + minute).compareTo(other.hour * 60 + other.minute);

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'hour': hour, 'minute': minute};

  static ReminderTime fromJson(Map<String, dynamic> j) => ReminderTime(
    (j['hour'] as num).toInt(),
    (j['minute'] as num).toInt(),
  );
}

/// Un recordatorio configurado: si está prendido y a qué horas suena.
class Reminder {
  const Reminder({
    required this.kind,
    required this.enabled,
    required this.times,
  });

  factory Reminder.byDefault(ReminderKind kind) => Reminder(
    kind: kind,
    // Apagado hasta que alguien lo prenda: una app que empieza a notificar
    // sola es una app que se desinstala.
    enabled: false,
    times: kind.defaultHours.map((h) => ReminderTime(h, 0)).toList(),
  );

  final ReminderKind kind;
  final bool enabled;
  final List<ReminderTime> times;

  /// Más de esto es ruido, no un recordatorio.
  static const int maxTimes = 8;

  Reminder copyWith({bool? enabled, List<ReminderTime>? times}) => Reminder(
    kind: kind,
    enabled: enabled ?? this.enabled,
    times: times ?? this.times,
  );

  Reminder withTimeAdded(ReminderTime time) {
    if (times.contains(time) || times.length >= maxTimes) return this;
    return copyWith(times: <ReminderTime>[...times, time]..sort());
  }

  Reminder withTimeRemoved(ReminderTime time) =>
      copyWith(times: times.where((t) => t != time).toList());

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.wire,
    'enabled': enabled,
    'times': times.map((t) => t.toJson()).toList(),
  };

  static Reminder fromJson(Map<String, dynamic> j) {
    final kind = ReminderKind.fromWire(j['kind'] as String?);
    return Reminder(
      kind: kind,
      enabled: j['enabled'] as bool? ?? false,
      times:
          (j['times'] as List<dynamic>? ?? <dynamic>[])
              .map((raw) => ReminderTime.fromJson(raw as Map<String, dynamic>))
              .toList()
            ..sort(),
    );
  }
}
