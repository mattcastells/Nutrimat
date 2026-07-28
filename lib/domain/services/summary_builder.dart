import 'dart:math' as math;

import '../../core/utils/dates.dart';
import '../calculations/adherence.dart';
import '../calculations/moving_average.dart';
import '../calculations/rounding.dart';
import '../enums/enums.dart';
import '../models/activity.dart';
import '../models/body.dart';
import '../models/goal.dart';
import '../models/meal.dart';
import '../models/summaries.dart';

/// Construcción de los agregados de lectura a partir de los registros crudos.
///
/// Son funciones puras: no tocan red, base ni framework de UI. Toda la
/// aritmética sale de `domain/calculations/`.
abstract final class SummaryBuilder {
  static List<Meal> mealsOn(List<Meal> meals, DateTime date) =>
      meals
          .where((m) => !m.isDeleted && isSameDay(m.localDate, date))
          .toList()
        ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

  static List<Activity> activitiesOn(
    List<Activity> activities,
    DateTime date,
  ) =>
      activities
          .where((a) => !a.isDeleted && isSameDay(a.localDate, date))
          .toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  /// El resumen de Inicio (S-06) y del detalle del día (S-22).
  static DailySummary daily({
    required DateTime date,
    required Goal goal,
    required List<Meal> allMeals,
    required List<Activity> allActivities,
    required List<WeightLog> weightLogs,
    required int creditPercentage,
    required bool creditEnabled,
    required bool isRestDay,
  }) {
    final meals = mealsOn(allMeals, date);
    final activities = activitiesOn(allActivities, date);

    final consumed = meals.fold(0, (acc, m) => acc + m.totalKcal);
    final estimated = activities.fold(
      0,
      (acc, a) => acc + a.estimatedCalories,
    );
    // Cada actividad conserva su porcentaje congelado (D-05): se suman las
    // aplicadas ya persistidas, no se recalcula el día entero.
    final applied = creditEnabled
        ? activities.fold(0, (acc, a) => acc + a.appliedCalories)
        : 0;

    final protein = meals.fold(0.0, (acc, m) => acc + m.totalProteinG);
    final carbs = meals.fold(0.0, (acc, m) => acc + m.totalCarbsG);
    final fat = meals.fold(0.0, (acc, m) => acc + m.totalFatG);

    final minutes = activities.fold(0, (acc, a) => acc + a.durationMinutes);
    final stepsValues = activities
        .map((a) => a.steps)
        .whereType<int>()
        .toList();

    return DailySummary(
      date: dateOnly(date),
      baseTarget: goal.baseCalorieTarget,
      consumedKcal: consumed,
      exerciseEstimatedKcal: estimated,
      exerciseAppliedKcal: applied,
      creditPercentage: creditPercentage,
      creditEnabled: creditEnabled,
      macros: MacroSet(
        protein: MacroProgress(current: protein, target: goal.proteinG),
        carbs: MacroProgress(current: carbs, target: goal.carbsG),
        fat: MacroProgress(current: fat, target: goal.fatG),
      ),
      meals: meals,
      activities: activities,
      activityTotals: ActivityTotals(
        minutes: minutes,
        sessions: activities.length,
        steps: stepsValues.isEmpty
            ? null
            : stepsValues.fold<int>(0, (acc, s) => acc + s),
      ),
      weight: _weightSnapshot(weightLogs, date),
      isRestDay: isRestDay,
    );
  }

  static WeightSnapshot? _weightSnapshot(
    List<WeightLog> logs,
    DateTime date,
  ) {
    final sorted = <WeightLog>[...logs]
      ..sort((a, b) => a.localDate.compareTo(b.localDate));
    final upToDate = sorted
        .where((w) => !w.localDate.isAfter(dateOnly(date)))
        .toList();
    if (upToDate.isEmpty) return null;
    final latest = upToDate.last;
    final previous = upToDate.length > 1
        ? upToDate[upToDate.length - 2]
        : null;
    return WeightSnapshot(
      weightKg: latest.weightKg,
      deltaKg: previous == null
          ? 0
          : double.parse(
              (latest.weightKg - previous.weightKg).toStringAsFixed(1),
            ),
    );
  }

  /// Las filas-día del Historial (S-21), de la más reciente a la más vieja.
  static List<HistoryDay> history({
    required DateTime from,
    required DateTime to,
    required List<Meal> allMeals,
    required List<Activity> allActivities,
    required Goal Function(DateTime) goalFor,
    required bool Function(DateTime) isRestDay,
    bool creditEnabled = true,
  }) {
    final days = <HistoryDay>[];
    var cursor = dateOnly(to);
    final start = dateOnly(from);

    while (!cursor.isBefore(start)) {
      final meals = mealsOn(allMeals, cursor);
      final activities = activitiesOn(allActivities, cursor);
      final steps = activities.map((a) => a.steps).whereType<int>().toList();

      days.add(
        HistoryDay(
          date: cursor,
          consumedKcal: meals.fold(0, (acc, m) => acc + m.totalKcal),
          activityKcal: activities.fold(
            0,
            (acc, a) => acc + a.estimatedCalories,
          ),
          appliedKcal: creditEnabled
              ? activities.fold(0, (acc, a) => acc + a.appliedCalories)
              : 0,
          baseTarget: goalFor(cursor).baseCalorieTarget,
          exerciseMinutes: activities.fold(
            0,
            (acc, a) => acc + a.durationMinutes,
          ),
          activityCount: activities.length,
          steps: steps.isEmpty
              ? null
              : steps.fold<int>(0, (acc, s) => acc + s),
          isRestDay: isRestDay(cursor),
          hasRecords: meals.isNotEmpty || activities.isNotEmpty,
        ),
      );
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return days;
  }

  /// El agregado de Progreso (S-23 y S-24).
  static ProgressSummary progress({
    required DateTime from,
    required DateTime to,
    required List<Meal> allMeals,
    required List<Activity> allActivities,
    required List<WeightLog> weightLogs,
    required List<ActivityGoal> activityGoals,
    required Goal Function(DateTime) goalFor,
    required bool Function(DateTime) isRestDay,
    required bool creditEnabled,
  }) {
    final start = dateOnly(from);
    final end = dateOnly(to);
    final dayCount = daysBetween(start, end) + 1;

    final weightInRange =
        weightLogs
            .where(
              (w) =>
                  !w.localDate.isBefore(start) && !w.localDate.isAfter(end),
            )
            .toList()
          ..sort((a, b) => a.localDate.compareTo(b.localDate));

    final weightPoints = weightInRange
        .map((w) => ChartPoint(w.localDate, w.weightKg))
        .toList();
    final seriesPoints = weightInRange
        .map((w) => SeriesPoint(w.localDate, w.weightKg))
        .toList();
    final movingAvg = movingAverage(seriesPoints, 7)
        .map((p) => ChartPoint(p.date, p.value))
        .toList();

    final calorieDays = <CaloriesDay>[];
    final activityByDay = <ActivityDayPoint>[];
    final adherenceDays = <AdherenceDay>[];
    var restDayCount = 0;

    for (var i = 0; i < dayCount; i++) {
      final day = start.add(Duration(days: i));
      final meals = mealsOn(allMeals, day);
      final activities = activitiesOn(allActivities, day);
      final goal = goalFor(day);
      final applied = creditEnabled
          ? activities.fold(0, (acc, a) => acc + a.appliedCalories)
          : 0;
      final consumed = meals.fold(0, (acc, m) => acc + m.totalKcal);

      calorieDays.add(
        CaloriesDay(
          date: day,
          consumed: consumed,
          target: goal.baseCalorieTarget,
          exerciseApplied: applied,
        ),
      );
      adherenceDays.add(
        AdherenceDay(consumed: consumed, target: goal.baseCalorieTarget),
      );
      activityByDay.add(
        ActivityDayPoint(
          date: day,
          minutes: activities.fold(0, (acc, a) => acc + a.durationMinutes),
          calories: activities.fold(0, (acc, a) => acc + a.estimatedCalories),
          sessions: activities.length,
        ),
      );
      if (isRestDay(day)) restDayCount++;
    }

    final rangeActivities = allActivities
        .where(
          (a) =>
              !a.isDeleted &&
              !a.localDate.isBefore(start) &&
              !a.localDate.isAfter(end),
        )
        .toList();

    final byCategory = <ActivityCategory, int>{};
    final byType = <String, int>{};
    for (final a in rangeActivities) {
      final category = a.activityType?.category ?? ActivityCategory.other;
      byCategory[category] = (byCategory[category] ?? 0) + a.durationMinutes;
      final name = a.activityType?.displayName ?? 'Otras';
      byType[name] = (byType[name] ?? 0) + 1;
    }

    final totalMinutes = rangeActivities.fold(
      0,
      (acc, a) => acc + a.durationMinutes,
    );
    final activeDays = rangeActivities
        .map((a) => isoDate(a.localDate))
        .toSet()
        .length;

    String? mostFrequent;
    var mostFrequentCount = 0;
    byType.forEach((name, count) {
      if (count > mostFrequentCount) {
        mostFrequent = name;
        mostFrequentCount = count;
      }
    });

    final thisWeekStart = startOfIsoWeek(end);
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final thisWeekMinutes = rangeActivities
        .where((a) => !a.localDate.isBefore(thisWeekStart))
        .fold(0, (acc, a) => acc + a.durationMinutes);
    final lastWeekMinutes = allActivities
        .where(
          (a) =>
              !a.isDeleted &&
              !a.localDate.isBefore(lastWeekStart) &&
              a.localDate.isBefore(thisWeekStart),
        )
        .fold(0, (acc, a) => acc + a.durationMinutes);

    final stepValues = rangeActivities
        .map((a) => a.steps)
        .whereType<int>()
        .toList();

    final firstWeight = weightInRange.isEmpty
        ? 0.0
        : weightInRange.first.weightKg;
    final lastWeight = weightInRange.isEmpty
        ? 0.0
        : weightInRange.last.weightKg;

    return ProgressSummary(
      from: start,
      to: end,
      days: dayCount,
      weightPoints: weightPoints,
      weightMovingAverage: movingAvg,
      weightDeltaKg: double.parse(
        (lastWeight - firstWeight).toStringAsFixed(1),
      ),
      trendKgPerWeek: weightTrendKgPerWeek(seriesPoints),
      calorieDays: calorieDays,
      averageConsumed: calorieDays.isEmpty
          ? 0
          : roundHalfUp(
              calorieDays.fold(0, (acc, d) => acc + d.consumed) /
                  math.max(
                    1,
                    calorieDays.where((d) => d.consumed > 0).length,
                  ),
            ),
      adherencePct: adherencePct(adherenceDays),
      activityByDay: activityByDay,
      activityByCategory: byCategory.entries
          .map((e) => CategorySlice(category: e.key, minutes: e.value))
          .toList()
        ..sort((a, b) => b.minutes.compareTo(a.minutes)),
      activityTotals: ActivityPeriodTotals(
        minutes: totalMinutes,
        sessions: rangeActivities.length,
        avgDurationMinutes: rangeActivities.isEmpty
            ? 0
            : roundHalfUp(totalMinutes / rangeActivities.length),
        estimatedCalories: rangeActivities.fold(
          0,
          (acc, a) => acc + a.estimatedCalories,
        ),
        activeDays: activeDays,
        longestSessionMinutes: rangeActivities.isEmpty
            ? 0
            : rangeActivities
                  .map((a) => a.durationMinutes)
                  .reduce((a, b) => a > b ? a : b),
        restDays: restDayCount,
        mostFrequentTypeName: mostFrequent,
      ),
      weeklyAverageMinutes: dayCount == 0
          ? 0
          : roundHalfUp(totalMinutes / (dayCount / 7)),
      previousWeekDeltaMinutes: thisWeekMinutes - lastWeekMinutes,
      stepsAverage: stepValues.isEmpty
          ? null
          : roundHalfUp(
              stepValues.fold(0, (acc, s) => acc + s) / stepValues.length,
            ),
      goals: activityGoals
          .map(
            (g) => ActivityGoalProgress(
              goal: g,
              currentValue: _goalCurrentValue(
                goal: g,
                activities: allActivities,
                reference: end,
              ),
            ),
          )
          .toList(),
    );
  }

  /// Valor actual de un objetivo de actividad en su período (§18).
  static int _goalCurrentValue({
    required ActivityGoal goal,
    required List<Activity> activities,
    required DateTime reference,
  }) {
    final start = goal.period == GoalPeriod.week
        ? startOfIsoWeek(reference)
        : dateOnly(reference);
    final inPeriod = activities
        .where((a) => !a.isDeleted && !a.localDate.isBefore(start))
        .toList();

    return switch (goal.goalType) {
      ActivityGoalType.activeMinutes => inPeriod.fold(
        0,
        (acc, a) => acc + a.durationMinutes,
      ),
      ActivityGoalType.sessions => inPeriod.length,
      ActivityGoalType.steps => inPeriod
          .map((a) => a.steps ?? 0)
          .fold(0, (acc, s) => acc + s),
      ActivityGoalType.distance => inPeriod
          .map((a) => a.distanceMeters ?? 0)
          .fold(0, (acc, d) => acc + d),
      ActivityGoalType.strengthSessions => inPeriod
          .where((a) => a.activityType?.category == ActivityCategory.strength)
          .length,
      ActivityGoalType.activeDays => inPeriod
          .map((a) => isoDate(a.localDate))
          .toSet()
          .length,
    };
  }

  /// Mensajes de consistencia con copy neutral (S-24, RN-14 y RN-15).
  static List<String> consistencyNotes(ProgressSummary p) {
    final notes = <String>[];
    final totals = p.activityTotals;
    final windowDays = math.min(p.days, 7);

    if (totals.sessions == 0) {
      notes.add('Todavía no registraste actividad en este período.');
      return notes;
    }

    final restSuffix = totals.restDays > 0
        ? ' (${totals.restDays} de descanso planificado)'
        : '';
    notes.add(
      'Registraste actividad durante ${totals.activeDays} de los últimos '
      '$windowDays días$restSuffix.',
    );

    final thisWeek = p.activityByDay
        .where((d) => !d.date.isBefore(startOfIsoWeek(p.to)))
        .fold(0, (acc, d) => acc + d.minutes);
    notes.add('Esta semana acumulaste $thisWeek minutos de actividad.');

    final delta = p.previousWeekDeltaMinutes;
    if (delta > 0) {
      notes.add('Son $delta minutos más que la semana anterior.');
    } else if (delta < 0) {
      notes.add('Son ${delta.abs()} minutos menos que la semana anterior.');
    } else {
      notes.add('Los mismos minutos que la semana anterior.');
    }
    return notes;
  }
}
