import '../../core/utils/dates.dart';
import '../enums/enums.dart';

/// Objetivo calórico vigente o histórico (10-types §Goal).
///
/// Cambiar el objetivo cierra la fila vigente (`endsOn = ayer`) e inserta una
/// nueva desde hoy: el historial conserva los objetivos viejos (F-13).
class Goal {
  const Goal({
    required this.id,
    required this.goalType,
    required this.rateKgPerWeek,
    required this.baseCalorieTarget,
    required this.targetMethod,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.macroMethod,
    required this.startsOn,
    this.targetWeightKg,
    this.bmrKcal,
    this.tdeeKcal,
    this.endsOn,
  });

  final String id;
  final GoalType goalType;
  final double rateKgPerWeek;
  final double? targetWeightKg;
  final int baseCalorieTarget;
  final TargetMethod targetMethod;
  final int? bmrKcal;
  final int? tdeeKcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final String macroMethod;
  final DateTime startsOn;

  /// `null` = vigente.
  final DateTime? endsOn;

  bool get isCurrent => endsOn == null;

  Goal copyWith({
    GoalType? goalType,
    double? rateKgPerWeek,
    double? targetWeightKg,
    int? baseCalorieTarget,
    TargetMethod? targetMethod,
    int? bmrKcal,
    int? tdeeKcal,
    int? proteinG,
    int? carbsG,
    int? fatG,
    String? macroMethod,
    DateTime? startsOn,
    DateTime? endsOn,
  }) => Goal(
    id: id,
    goalType: goalType ?? this.goalType,
    rateKgPerWeek: rateKgPerWeek ?? this.rateKgPerWeek,
    targetWeightKg: targetWeightKg ?? this.targetWeightKg,
    baseCalorieTarget: baseCalorieTarget ?? this.baseCalorieTarget,
    targetMethod: targetMethod ?? this.targetMethod,
    bmrKcal: bmrKcal ?? this.bmrKcal,
    tdeeKcal: tdeeKcal ?? this.tdeeKcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    macroMethod: macroMethod ?? this.macroMethod,
    startsOn: startsOn ?? this.startsOn,
    endsOn: endsOn ?? this.endsOn,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'goalType': goalType.wire,
    'rateKgPerWeek': rateKgPerWeek,
    'targetWeightKg': targetWeightKg,
    'baseCalorieTarget': baseCalorieTarget,
    'targetMethod': targetMethod.wire,
    'bmrKcal': bmrKcal,
    'tdeeKcal': tdeeKcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'macroMethod': macroMethod,
    'startsOn': isoDate(startsOn),
    'endsOn': endsOn == null ? null : isoDate(endsOn!),
  };

  static Goal fromJson(Map<String, dynamic> j) => Goal(
    id: j['id'] as String,
    goalType: GoalType.fromWire(j['goalType'] as String),
    rateKgPerWeek: (j['rateKgPerWeek'] as num).toDouble(),
    targetWeightKg: (j['targetWeightKg'] as num?)?.toDouble(),
    baseCalorieTarget: j['baseCalorieTarget'] as int,
    targetMethod: TargetMethod.values.firstWhere(
      (e) => e.wire == j['targetMethod'],
      orElse: () => TargetMethod.calculated,
    ),
    bmrKcal: j['bmrKcal'] as int?,
    tdeeKcal: j['tdeeKcal'] as int?,
    proteinG: j['proteinG'] as int,
    carbsG: j['carbsG'] as int,
    fatG: j['fatG'] as int,
    macroMethod: j['macroMethod'] as String,
    startsOn: DateTime.parse(j['startsOn'] as String),
    endsOn: j['endsOn'] == null
        ? null
        : DateTime.parse(j['endsOn'] as String),
  );
}
