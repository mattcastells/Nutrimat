import '../../core/utils/dates.dart';
import '../enums/enums.dart';

/// Qué clase de día fue.
///
/// Los dos casos son la misma forma —una fecha que queda calificada, sin
/// magnitud que medir— y por eso comparten tabla y modelo. Sumar una etiqueta
/// (vacaciones, viaje) es agregar un valor acá y otro al `check` de la
/// migración, no una entidad nueva. Ver `docs/contexto-diario.md`.
enum DayMarkerKind {
  rest('rest', 'Descanso'),
  sick('sick', 'Enfermedad');

  const DayMarkerKind(this.wire, this.label);

  final String wire;
  final String label;

  static DayMarkerKind fromWire(String? w) => DayMarkerKind.values.firstWhere(
    (k) => k.wire == w,
    orElse: () => DayMarkerKind.rest,
  );
}

/// Cuánto afectó. Solo para [DayMarkerKind.sick].
///
/// Tres niveles y no diez por lo mismo que el sueño tiene cinco: nadie
/// distingue un 6 de un 7 de su propio malestar, y una escala falsamente
/// precisa invita a leer tendencias que no existen.
enum SickSeverity {
  mild(1, 'Leve', 'Seguí con el día casi normal'),
  moderate(2, 'Moderada', 'Bajaste el ritmo'),
  severe(3, 'Fuerte', 'No pudiste hacer la rutina');

  const SickSeverity(this.level, this.label, this.hint);

  final int level;
  final String label;
  final String hint;

  static SickSeverity? fromLevel(int? level) {
    if (level == null) return null;
    for (final s in SickSeverity.values) {
      if (s.level == level) return s;
    }
    return null;
  }
}

/// Una marca sobre un día.
///
/// **No cambia ningún cálculo.** Un día de enfermedad no baja el objetivo, no
/// se saltea del promedio ni se descuenta de la adherencia: lo que hace es
/// **dar contexto**, para que un hueco en el gráfico de actividad se pueda leer
/// como lo que fue y no como abandono. Que la persona decida después qué hacer
/// con esa información es otra conversación, y meterla acá sería que la app
/// opine sobre una semana que no vio.
class DayMarker {
  const DayMarker({
    required this.id,
    required this.localDate,
    required this.kind,
    required this.updatedAt,
    this.severity,
    this.note,
    this.tags = const <String>[],
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
  });

  final String id;
  final DateTime localDate;
  final DayMarkerKind kind;

  /// Solo tiene sentido con [DayMarkerKind.sick]; en el resto es `null`, y la
  /// base lo hace cumplir con un `check`.
  final SickSeverity? severity;

  final String? note;

  /// Los síntomas del futuro entran acá sin tocar el esquema.
  final List<String> tags;

  final DateTime updatedAt;
  final SyncStatus syncStatus;

  /// La lápida. Va como en el sueño y el peso: sin ella, desmarcar un día lo
  /// sacaba de este teléfono y lo dejaba vivo en la tabla, así que volvía solo
  /// en la reconciliación siguiente.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  static const int maxNoteLength = 500;
  static const int maxTags = 16;

  DayMarker copyWith({
    SickSeverity? severity,
    String? note,
    List<String>? tags,
    DateTime? deletedAt,
    bool clearSeverity = false,
    bool clearNote = false,
    bool clearDeletedAt = false,
  }) => DayMarker(
    id: id,
    localDate: localDate,
    kind: kind,
    severity: clearSeverity ? null : (severity ?? this.severity),
    note: clearNote ? null : (note ?? this.note),
    tags: tags ?? this.tags,
    updatedAt: DateTime.now(),
    syncStatus: SyncStatus.pending,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'localDate': isoDate(localDate),
    'kind': kind.wire,
    'severity': severity?.level,
    'note': note,
    'tags': tags,
    'updatedAt': updatedAt.toIso8601String(),
    'syncStatus': syncStatus.wire,
    'deletedAt': deletedAt?.toIso8601String(),
  };

  static DayMarker fromJson(Map<String, dynamic> j) {
    final kind = DayMarkerKind.fromWire(j['kind'] as String?);
    return DayMarker(
      id: j['id'] as String,
      localDate: DateTime.parse(j['localDate'] as String),
      kind: kind,
      // La severidad solo sobrevive en los días de enfermedad: una fila con
      // `kind = rest` y severidad cargada es un dato corrupto que la base ya
      // rechaza, y el modelo no lo deja entrar por la otra puerta.
      severity: kind == DayMarkerKind.sick
          ? SickSeverity.fromLevel((j['severity'] as num?)?.toInt())
          : null,
      note: j['note'] as String?,
      tags: <String>[
        for (final t in (j['tags'] as List<dynamic>? ?? <dynamic>[]))
          t.toString(),
      ],
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.wire == j['syncStatus'],
        orElse: () => SyncStatus.pending,
      ),
      deletedAt: j['deletedAt'] == null
          ? null
          : DateTime.tryParse(j['deletedAt'] as String),
    );
  }
}
