import '../calculations/daily_balance.dart';
import '../enums/enums.dart';
import 'activity.dart';
import 'meal.dart';

class MacroProgress {
  const MacroProgress({required this.current, required this.target});

  final double current;
  final int target;

  double get fraction => target <= 0 ? 0 : current / target;
}

class MacroSet {
  const MacroSet({
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final MacroProgress protein;
  final MacroProgress carbs;
  final MacroProgress fat;
}

class ActivityTotals {
  const ActivityTotals({
    required this.minutes,
    required this.sessions,
    this.steps,
  });

  final int minutes;
  final int sessions;

  /// `null` si no hay ninguna fuente de pasos: `StepsSummaryCard` se oculta
  /// por completo en vez de mostrar 0 (05-component-library §1).
  final int? steps;
}

class WeightSnapshot {
  const WeightSnapshot({required this.weightKg, required this.deltaKg});

  final double weightKg;
  final double deltaKg;
}

/// El agregado que alimenta Inicio (S-06) y el detalle del día (S-22).
class DailySummary {
  const DailySummary({
    required this.date,
    required this.baseTarget,
    required this.consumedKcal,
    required this.exerciseEstimatedKcal,
    required this.exerciseAppliedKcal,
    required this.creditPercentage,
    required this.creditEnabled,
    required this.macros,
    required this.meals,
    required this.activities,
    required this.activityTotals,
    required this.isRestDay,
    this.weight,
  });

  final DateTime date;
  final int baseTarget;
  final int consumedKcal;
  final int exerciseEstimatedKcal;
  final int exerciseAppliedKcal;
  final int creditPercentage;
  final bool creditEnabled;
  final MacroSet macros;
  final List<Meal> meals;
  final List<Activity> activities;
  final ActivityTotals activityTotals;
  final WeightSnapshot? weight;
  final bool isRestDay;

  DailyBalance get balance => DailyBalance(
    baseTarget: baseTarget,
    consumedKcal: consumedKcal,
    exerciseEstimatedKcal: exerciseEstimatedKcal,
    exerciseAppliedKcal: exerciseAppliedKcal,
    creditPercentage: creditPercentage,
    creditEnabled: creditEnabled,
  );

  int get adjustedTarget => balance.adjustedTarget;
  int get remainingKcal => balance.remainingKcal;
  int get netKcal => balance.netKcal;

  List<Meal> mealsFor(MealSlot slot) =>
      meals.where((m) => m.slot == slot).toList();

  int kcalFor(MealSlot slot) =>
      mealsFor(slot).fold(0, (acc, m) => acc + m.totalKcal);

  bool get hasRecords => meals.isNotEmpty || activities.isNotEmpty;

  bool get isEmpty => !hasRecords && weight == null;
}

/// Una fila-día del Historial (S-21).
class HistoryDay {
  const HistoryDay({
    required this.date,
    required this.consumedKcal,
    required this.activityKcal,
    required this.appliedKcal,
    required this.baseTarget,
    required this.exerciseMinutes,
    required this.activityCount,
    required this.isRestDay,
    required this.hasRecords,
    this.steps,
  });

  final DateTime date;
  final int consumedKcal;
  final int activityKcal;
  final int appliedKcal;
  final int baseTarget;
  final int exerciseMinutes;
  final int activityCount;
  final int? steps;
  final bool isRestDay;
  final bool hasRecords;

  int get adjustedTarget => baseTarget + appliedKcal;

  int get balanceKcal => adjustedTarget - consumedKcal;

  /// Indicador neutral: dentro / fuera, sin color de castigo (F-12).
  bool get isWithinTarget => hasRecords && balanceKcal >= 0;
}

class ChartPoint {
  const ChartPoint(this.date, this.value);

  final DateTime date;
  final double value;
}

class CaloriesDay {
  const CaloriesDay({
    required this.date,
    required this.consumed,
    required this.target,
    required this.exerciseApplied,
  });

  final DateTime date;
  final int consumed;
  final int target;
  final int exerciseApplied;
}

class ActivityDayPoint {
  const ActivityDayPoint({
    required this.date,
    required this.minutes,
    required this.calories,
    required this.sessions,
  });

  final DateTime date;
  final int minutes;
  final int calories;
  final int sessions;
}

class CategorySlice {
  const CategorySlice({required this.category, required this.minutes});

  final ActivityCategory category;
  final int minutes;
}

class ActivityPeriodTotals {
  const ActivityPeriodTotals({
    required this.minutes,
    required this.sessions,
    required this.avgDurationMinutes,
    required this.estimatedCalories,
    required this.activeDays,
    required this.longestSessionMinutes,
    required this.restDays,
    this.mostFrequentTypeName,
  });

  final int minutes;
  final int sessions;
  final int avgDurationMinutes;
  final int estimatedCalories;
  final int activeDays;
  final int longestSessionMinutes;
  final int restDays;
  final String? mostFrequentTypeName;
}

/// Agregado de Progreso (S-23, S-24).
class ProgressSummary {
  const ProgressSummary({
    required this.from,
    required this.to,
    required this.days,
    required this.weightPoints,
    required this.weightMovingAverage,
    required this.weightDeltaKg,
    required this.calorieDays,
    required this.averageConsumed,
    required this.activityByDay,
    required this.activityByCategory,
    required this.activityTotals,
    required this.weeklyAverageMinutes,
    required this.previousWeekDeltaMinutes,
    required this.goals,
    this.trendKgPerWeek,
    this.adherencePct,
    this.stepsAverage,
  });

  final DateTime from;
  final DateTime to;
  final int days;
  final List<ChartPoint> weightPoints;
  final List<ChartPoint> weightMovingAverage;
  final double weightDeltaKg;

  /// `null` con menos de 3 puntos: "Necesitamos unos días más de registro".
  final double? trendKgPerWeek;
  final List<CaloriesDay> calorieDays;
  final int averageConsumed;

  /// `null` con menos de 3 días con registro (§16).
  final int? adherencePct;
  final List<ActivityDayPoint> activityByDay;
  final List<CategorySlice> activityByCategory;
  final ActivityPeriodTotals activityTotals;
  final int weeklyAverageMinutes;
  final int previousWeekDeltaMinutes;
  final int? stepsAverage;
  final List<ActivityGoalProgress> goals;

  bool get hasEnoughWeightData => weightPoints.length >= 3;
}

class ActivityGoalProgress {
  const ActivityGoalProgress({required this.goal, required this.currentValue});

  final ActivityGoal goal;
  final int currentValue;
}
