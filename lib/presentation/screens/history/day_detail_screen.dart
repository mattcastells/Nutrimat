import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/charts/macro_bar.dart';
import '../../components/food/daily_summary_card.dart';
import '../../components/food/food_widgets.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../home/daily_breakdown_sheet.dart';
import '../weight/weight_sheet.dart';

/// S-22 · Detalle del día. La misma tarjeta que Inicio, editable (D-20).
class DayDetailScreen extends ConsumerWidget {
  const DayDetailScreen({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dailySummaryProvider(date));
    final repo = ref.watch(repositoryProvider);
    final units = ref.watch(unitSystemProvider);

    return NmScreen(
      title: longDay(date),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          DailySummaryCard(
            summary: summary,
            onBreakdown: () => showDailyBreakdownSheet(context, summary),
            onChangeCredit: () => context.push(Routes.exerciseCredit),
          ),
          const SizedBox(height: NmSpace.s6),
          NmCard(child: MacroBar(macros: summary.macros)),
          const SizedBox(height: NmSpace.s8),

          const NmSectionHeader(title: 'Comidas'),
          for (final slot in MealSlot.values)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s4),
              child: MealSection(
                slot: slot,
                meals: summary.mealsFor(slot),
                onAdd: () => context.push(
                  '${Routes.mealNew}?slot=${slot.wire}&date=${isoDate(date)}',
                ),
                onOpenMeal: (meal) => context.push(Routes.meal(meal.id)),
                onDeleteMeal: (meal) async {
                  await repo.deleteMeal(meal.id);
                  if (!context.mounted) return;
                  NmSnackbar.show(
                    context,
                    'Comida eliminada',
                    actionLabel: 'Deshacer',
                    undo: true,
                    onAction: () => repo.restoreMeal(meal.id),
                  );
                },
              ),
            ),

          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Actividad'),
          if (summary.activities.isEmpty)
            NmCard(
              child: ActivitySummaryCard(
                totals: summary.activityTotals,
                estimatedCalories: summary.exerciseEstimatedKcal,
                appliedCalories: summary.exerciseAppliedKcal,
                creditPercentage: summary.creditPercentage,
                isRestDay: summary.isRestDay,
                onAdd: () => context.push(
                  '${Routes.activityNew}?date=${isoDate(date)}',
                ),
              ),
            )
          else
            NmCard(
              child: Column(
                children: <Widget>[
                  for (final activity in summary.activities)
                    ActivityListItem(
                      activity: activity,
                      onTap: () => context.push(Routes.activity(activity.id)),
                      onEdit: () =>
                          context.push(Routes.activityEdit(activity.id)),
                      onDelete: () async {
                        await repo.deleteActivity(activity.id);
                        if (!context.mounted) return;
                        NmSnackbar.show(
                          context,
                          'Actividad eliminada',
                          actionLabel: 'Deshacer',
                          undo: true,
                          onAction: () => repo.restoreActivity(activity.id),
                        );
                      },
                    ),
                ],
              ),
            ),

          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Peso'),
          NmCard(
            child: WeightRow(
              weightKg: summary.weight?.weightKg,
              deltaKg: summary.weight?.deltaKg,
              units: units,
              onLog: () => showWeightSheet(context, date: date),
            ),
          ),

          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Cierre del día'),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Objetivo base',
                  value: Fmt.kcal(summary.baseTarget),
                ),
                ValueRow(
                  label: 'Ajuste por ejercicio',
                  value: '+${Fmt.kcal(summary.exerciseAppliedKcal)}',
                ),
                const NmDivider(),
                ValueRow(
                  label: 'Balance final',
                  value: Fmt.signed(summary.remainingKcal),
                  emphasis: true,
                  valueColor: summary.remainingKcal < 0
                      ? context.nm.overBudget
                      : null,
                ),
                ValueRow(
                  label: 'Calorías netas',
                  caption: 'consumidas − aplicadas',
                  value: Fmt.kcal(summary.netKcal),
                  muted: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
