import '../../core/utils/dates.dart';
import '../enums/enums.dart';

/// Cómo se durmió, en palabras.
///
/// Cinco niveles y no una nota del 1 al 10: nadie distingue un 6 de un 7 de su
/// propio sueño, y una escala falsamente precisa invita a leer tendencias que
/// no existen.
enum SleepQuality {
  bad('bad', 'Mal', 1),
  poor('poor', 'Regular', 2),
  ok('ok', 'Normal', 3),
  good('good', 'Bien', 4),
  great('great', 'Muy bien', 5);

  const SleepQuality(this.wire, this.label, this.score);

  final String wire;
  final String label;

  /// 1–5, solo para promediar en Progreso.
  final int score;

  static SleepQuality fromWire(String? w) => SleepQuality.values.firstWhere(
    (q) => q.wire == w,
    orElse: () => SleepQuality.ok,
  );
}

/// Una noche. Se registra sobre el día en que **se despertó**, que es como la
/// gente lo cuenta: "anoche dormí seis horas" se anota en el día de hoy.
class SleepLog {
  const SleepLog({
    required this.id,
    required this.localDate,
    required this.minutes,
    required this.quality,
    required this.loggedAt,
    this.notes,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
  });

  final String id;
  final DateTime localDate;

  /// Duración en minutos. Se guarda así y no en horas decimales para que
  /// "7 h 30" no se convierta en 7,5 y de vuelta con error de redondeo.
  final int minutes;

  final SleepQuality quality;
  final DateTime loggedAt;
  final String? notes;
  final SyncStatus syncStatus;

  /// La lápida. Sin ella, borrar una noche la sacaba de este teléfono y la
  /// dejaba viva en la tabla, así que volvía sola en la reconciliación
  /// siguiente. `loggedAt` se reescribe al borrar para que la lápida le gane
  /// al registro del servidor, que es como desempata esta colección.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// Dormir menos de 1 h o más de 16 es un error de carga, no una noche.
  static const int minMinutes = 60;
  static const int maxMinutes = 16 * 60;

  static int clampMinutes(int value) =>
      value.clamp(minMinutes, maxMinutes);

  double get hours => minutes / 60;

  /// "7 h 30" / "8 h".
  String get label {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m';
  }

  SleepLog copyWith({
    int? minutes,
    SleepQuality? quality,
    String? notes,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => SleepLog(
    id: id,
    localDate: localDate,
    minutes: minutes == null ? this.minutes : clampMinutes(minutes),
    quality: quality ?? this.quality,
    loggedAt: DateTime.now(),
    notes: notes ?? this.notes,
    syncStatus: SyncStatus.pending,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'localDate': isoDate(localDate),
    'minutes': minutes,
    'quality': quality.wire,
    'loggedAt': loggedAt.toIso8601String(),
    'notes': notes,
    'syncStatus': syncStatus.wire,
    'deletedAt': deletedAt?.toIso8601String(),
  };

  static SleepLog fromJson(Map<String, dynamic> j) => SleepLog(
    id: j['id'] as String,
    localDate: DateTime.parse(j['localDate'] as String),
    minutes: clampMinutes((j['minutes'] as num).toInt()),
    quality: SleepQuality.fromWire(j['quality'] as String?),
    loggedAt: DateTime.parse(j['loggedAt'] as String),
    notes: j['notes'] as String?,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.wire == j['syncStatus'],
      orElse: () => SyncStatus.pending,
    ),
    deletedAt: j['deletedAt'] == null
        ? null
        : DateTime.tryParse(j['deletedAt'] as String),
  );
}
