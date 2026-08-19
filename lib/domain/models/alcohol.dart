import '../../core/utils/dates.dart';
import '../calculations/alcohol.dart';
import '../enums/enums.dart';

/// Un consumo de alcohol.
///
/// Una fila por consumo y no una por día: "dos copas de vino y una cerveza" es
/// un sábado normal, y un solo renglón por día obliga a elegir cuál de los dos
/// tipos se guarda. Agrupar por día después es una línea; separar lo que se
/// guardó junto no se puede.
///
/// El volumen y la graduación quedan **en la fila** y no se leen del preset al
/// mostrar: si mañana se corrige el preset de "chopp", el sábado pasado sigue
/// siendo lo que se tomó. Es el mismo criterio con el que el agua guarda vasos
/// y no mililitros.
class AlcoholLog {
  const AlcoholLog({
    required this.id,
    required this.localDate,
    required this.type,
    required this.quantity,
    required this.volumeMl,
    required this.abvPct,
    required this.loggedAt,
    required this.updatedAt,
    this.note,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
  });

  final String id;
  final DateTime localDate;
  final DrinkType type;

  /// Cuántas unidades de esa bebida. Decimal porque media copa existe.
  final double quantity;

  /// El volumen y la graduación de **una** unidad.
  final int volumeMl;
  final double abvPct;

  final String? note;
  final DateTime loggedAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  static const int maxNoteLength = 500;
  static const double maxQuantity = 30;

  /// Unidades de bebida estándar del consumo entero.
  ///
  /// Es lo único con lo que se pueden sumar una cerveza y un whisky, y por eso
  /// es lo que grafica el panel: en mililitros, media botella de vino y una
  /// lata de cerveza se ven parecidas y no lo son.
  double get standardDrinksTotal =>
      standardDrinks(volumeMl: volumeMl, abvPct: abvPct) * quantity;

  /// Las calorías del consumo entero: etanol más los hidratos de la bebida.
  ///
  /// Es una **estimación** y se muestra como tal, igual que el gasto por MET.
  int get kcal =>
      (alcoholKcal(volumeMl: volumeMl, abvPct: abvPct, type: type) * quantity)
          .round();

  /// "2 copas de vino" · "1 lata de cerveza".
  String get label {
    final n = quantity == quantity.roundToDouble()
        ? quantity.round().toString()
        : quantity.toStringAsFixed(1).replaceAll('.', ',');
    return '$n × ${type.label} ($volumeMl ml)';
  }

  AlcoholLog copyWith({
    DrinkType? type,
    double? quantity,
    int? volumeMl,
    double? abvPct,
    String? note,
    DateTime? deletedAt,
    bool clearNote = false,
    bool clearDeletedAt = false,
  }) => AlcoholLog(
    id: id,
    localDate: localDate,
    type: type ?? this.type,
    quantity: (quantity ?? this.quantity).clamp(0.1, maxQuantity),
    volumeMl: volumeMl ?? this.volumeMl,
    abvPct: abvPct ?? this.abvPct,
    note: clearNote ? null : (note ?? this.note),
    loggedAt: loggedAt,
    updatedAt: DateTime.now(),
    syncStatus: SyncStatus.pending,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'localDate': isoDate(localDate),
    'type': type.wire,
    'quantity': quantity,
    'volumeMl': volumeMl,
    'abvPct': abvPct,
    'note': note,
    'loggedAt': loggedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncStatus': syncStatus.wire,
    'deletedAt': deletedAt?.toIso8601String(),
  };

  static AlcoholLog fromJson(Map<String, dynamic> j) => AlcoholLog(
    id: j['id'] as String,
    localDate: DateTime.parse(j['localDate'] as String),
    type: DrinkType.fromWire(j['type'] as String?),
    quantity: (j['quantity'] as num?)?.toDouble() ?? 1,
    volumeMl: (j['volumeMl'] as num?)?.toInt() ?? 0,
    abvPct: (j['abvPct'] as num?)?.toDouble() ?? 0,
    note: j['note'] as String?,
    loggedAt: DateTime.parse(j['loggedAt'] as String),
    updatedAt: DateTime.parse(
      (j['updatedAt'] ?? j['loggedAt']) as String,
    ),
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.wire == j['syncStatus'],
      orElse: () => SyncStatus.pending,
    ),
    deletedAt: j['deletedAt'] == null
        ? null
        : DateTime.tryParse(j['deletedAt'] as String),
  );
}

/// Lo que se tomó en un día, ya sumado.
///
/// Existe porque todas las pantallas preguntan lo mismo —cuántas UBE y cuántas
/// calorías fue ese día— y sumarlo en cada una es donde aparecen los tres
/// totales que no coinciden.
class AlcoholDay {
  const AlcoholDay({
    required this.date,
    required this.standardDrinks,
    required this.kcal,
    required this.entries,
  });

  final DateTime date;
  final double standardDrinks;
  final int kcal;
  final List<AlcoholLog> entries;

  bool get isEmpty => entries.isEmpty;

  static List<AlcoholDay> group(Iterable<AlcoholLog> logs) {
    final porDia = <String, List<AlcoholLog>>{};
    for (final l in logs) {
      if (l.isDeleted) continue;
      (porDia[isoDate(l.localDate)] ??= <AlcoholLog>[]).add(l);
    }

    final out = <AlcoholDay>[
      for (final e in porDia.entries)
        AlcoholDay(
          date: e.value.first.localDate,
          standardDrinks: e.value.fold(
            0.0,
            (acc, l) => acc + l.standardDrinksTotal,
          ),
          kcal: e.value.fold(0, (acc, l) => acc + l.kcal),
          entries: e.value,
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    return out;
  }
}
