import '../enums/enums.dart';

enum PalStatus {
  pending('pending'),
  accepted('accepted'),
  blocked('blocked');

  const PalStatus(this.wire);

  final String wire;

  static PalStatus fromWire(String? w) => PalStatus.values.firstWhere(
    (s) => s.wire == w,
    orElse: () => PalStatus.pending,
  );
}

/// Un vínculo con otra persona, visto desde quien mira.
class Pal {
  const Pal({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.isIncoming,
  });

  final String id;

  /// Id de la otra persona, no el propio.
  final String userId;

  /// Puede venir vacío: el nombre es opcional en el perfil.
  final String displayName;
  final PalStatus status;

  /// `true` cuando la solicitud la mandó la otra persona y falta responderla.
  final bool isIncoming;

  String get label => displayName.trim().isEmpty ? 'Sin nombre' : displayName;
}

/// Una comida tal como la ve un pal: cuándo, qué y cuánto. Sin los ítems.
class PalMeal {
  const PalMeal({required this.slot, required this.name, required this.kcal});

  final MealSlot slot;
  final String name;
  final int kcal;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'slot': slot.wire,
    'name': name,
    'kcal': kcal,
  };

  static PalMeal fromJson(Map<String, dynamic> j) => PalMeal(
    slot: MealSlot.values.firstWhere(
      (s) => s.wire == j['slot'],
      orElse: () => MealSlot.snack,
    ),
    name: j['name'] as String? ?? '',
    kcal: (j['kcal'] as num?)?.toInt() ?? 0,
  );
}

/// El día de alguien, con lo único que se publica.
class PalDay {
  const PalDay({
    required this.userId,
    required this.date,
    required this.meals,
    required this.activityMinutes,
    required this.activityCount,
  });

  final String userId;
  final DateTime date;
  final List<PalMeal> meals;
  final int activityMinutes;
  final int activityCount;

  bool get isEmpty => meals.isEmpty && activityCount == 0;

  int get totalKcal => meals.fold(0, (acc, m) => acc + m.kcal);

  List<PalMeal> mealsIn(MealSlot slot) =>
      meals.where((m) => m.slot == slot).toList();

  static PalDay fromRow(Map<String, dynamic> row) => PalDay(
    userId: row['user_id'] as String,
    date: DateTime.parse(row['local_date'] as String),
    meals: (row['meals'] as List<dynamic>? ?? <dynamic>[])
        .map((raw) => PalMeal.fromJson(raw as Map<String, dynamic>))
        .toList(),
    activityMinutes: (row['activity_minutes'] as num?)?.toInt() ?? 0,
    activityCount: (row['activity_count'] as num?)?.toInt() ?? 0,
  );
}
