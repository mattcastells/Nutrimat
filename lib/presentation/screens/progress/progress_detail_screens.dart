import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/activity.dart';
import '../../../domain/models/summaries.dart';
import '../../../domain/services/summary_builder.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/charts/charts.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../weight/weight_sheet.dart';

const _uuid = Uuid();

/// Gráfico de peso ampliado.
class WeightChartScreen extends ConsumerWidget {
  const WeightChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final units = ref.watch(unitSystemProvider);
    final logs = ref.watch(repositoryProvider).weightLogs;

    return NmScreen(
      title: 'Peso',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: WeightChart(
              id: 'weight-full',
              height: 240,
              points: progress.weightPoints,
              movingAverage: progress.weightMovingAverage,
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  label: 'Variación',
                  value:
                      '${Fmt.signedDecimal1(progress.weightDeltaKg)} '
                      '${Fmt.weightUnit(units)}',
                ),
              ),
              const SizedBox(width: NmSpace.s3),
              Expanded(
                child: StatCard(
                  label: 'Tendencia semanal',
                  value: progress.trendKgPerWeek == null
                      ? '—'
                      : '${Fmt.signedDecimal1(progress.trendKgPerWeek!)} kg',
                  caption: progress.trendKgPerWeek == null
                      ? 'Necesitamos unos días más de registro'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Registros'),
          NmCard(
            child: Column(
              children: <Widget>[
                for (final log in logs.take(20))
                  ValueRow(
                    label: friendlyDay(log.localDate),
                    value: Fmt.weight(log.weightKg, units),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Registrar peso',
            block: true,
            onPressed: () => showWeightSheet(context),
          ),
        ],
      ),
    );
  }
}

/// Gráfico de calorías ampliado.
class CaloriesChartScreen extends ConsumerWidget {
  const CaloriesChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);

    return NmScreen(
      title: 'Calorías',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: CaloriesChart(
              id: 'calories-full',
              height: 240,
              days: progress.calorieDays,
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  label: 'Promedio diario',
                  value: Fmt.kcal(progress.averageConsumed),
                ),
              ),
              const SizedBox(width: NmSpace.s3),
              Expanded(
                child: StatCard(
                  label: 'Adherencia',
                  value: progress.adherencePct == null
                      ? '—'
                      : Fmt.percent(progress.adherencePct!),
                ),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s4),
          const InfoNote(
            text: 'Los días sin registro no cuentan ni a favor ni en contra.',
          ),
        ],
      ),
    );
  }
}

/// S-24 · Progreso de actividad.
class ActivityProgressScreen extends ConsumerWidget {
  const ActivityProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final totals = progress.activityTotals;

    if (totals.sessions == 0) {
      return NmScreen(
        title: 'Actividad',
        child: EmptyState(
          icon: PhosphorIcons.personSimpleRun(),
          title: 'Todavía no registraste actividad en este período',
          body: 'Cuando registres una, vas a ver acá los minutos, las '
              'sesiones y la distribución por categoría.',
        ),
      );
    }

    return NmScreen(
      title: 'Actividad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: ActivityHistoryChart(
              id: 'activity-full',
              height: 220,
              points: progress.activityByDay,
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          Row(
            children: <Widget>[
              Expanded(
                child: StatCard(
                  label: 'Minutos activos',
                  value: Fmt.duration(totals.minutes),
                  caption: progress.previousWeekDeltaMinutes == 0
                      ? 'Igual que la semana anterior'
                      : '${Fmt.signed(progress.previousWeekDeltaMinutes)} min '
                            'vs. la semana anterior',
                  icon: PhosphorIcons.timer(),
                ),
              ),
              const SizedBox(width: NmSpace.s3),
              if (progress.stepsAverage != null)
                Expanded(
                  child: StatCard(
                    label: 'Pasos promedio',
                    value: Fmt.steps(progress.stepsAverage!),
                    icon: PhosphorIcons.footprints(),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Distribución por categoría'),
          NmCard(
            child: ActivityCategoryChart(slices: progress.activityByCategory),
          ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Resumen del período'),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Sesiones realizadas',
                  value: '${totals.sessions}',
                ),
                ValueRow(
                  label: 'Promedio de duración',
                  value: Fmt.duration(totals.avgDurationMinutes),
                ),
                ValueRow(
                  label: 'Calorías estimadas',
                  value: Fmt.estimatedKcal(totals.estimatedCalories),
                ),
                ValueRow(
                  label: 'Actividad más frecuente',
                  value: totals.mostFrequentTypeName ?? '—',
                ),
                ValueRow(
                  label: 'Mayor duración registrada',
                  value: Fmt.duration(totals.longestSessionMinutes),
                ),
                ValueRow(
                  label: 'Días con actividad',
                  value: '${totals.activeDays}',
                ),
                if (totals.restDays > 0)
                  ValueRow(
                    label: 'Descansos planificados',
                    value: '${totals.restDays}',
                    muted: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          ConsistencyNote(lines: SummaryBuilder.consistencyNotes(progress)),
        ],
      ),
    );
  }
}

/// S-25 · Objetivos de actividad. Opcionales y sin consecuencias (RN-09).
class ActivityGoalsScreen extends ConsumerWidget {
  const ActivityGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final repo = ref.watch(repositoryProvider);

    return NmScreen(
      title: 'Objetivos de actividad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          const InfoNote(
            text: 'Los objetivos de actividad nunca reducen tu objetivo '
                'calórico ni bloquean nada. Podés usar Nutrimat sin '
                'configurar ninguno.',
          ),
          const SizedBox(height: NmSpace.s6),
          if (progress.goals.isEmpty)
            EmptyState(
              icon: PhosphorIcons.target(),
              title: 'Sin objetivos configurados',
              body: 'Los objetivos de actividad son opcionales.',
              primaryLabel: 'Crear un objetivo',
              onPrimary: () => _showGoalSheet(context, ref, null),
            )
          else
            for (final goal in progress.goals)
              Padding(
                padding: const EdgeInsets.only(bottom: NmSpace.s3),
                child: ActivityGoalCard(
                  progress: goal,
                  onEdit: () => _showGoalSheet(context, ref, goal),
                  onToggle: (enabled) => repo.saveActivityGoal(
                    goal.goal.copyWith(enabled: enabled),
                  ),
                ),
              ),
          const SizedBox(height: NmSpace.s4),
          if (progress.goals.isNotEmpty)
            NmButton.secondary(
              label: 'Crear otro objetivo',
              block: true,
              onPressed: () => _showGoalSheet(context, ref, null),
            ),
        ],
      ),
    );
  }

  void _showGoalSheet(
    BuildContext context,
    WidgetRef ref,
    ActivityGoalProgress? existing,
  ) {
    var type = existing?.goal.goalType ?? ActivityGoalType.activeMinutes;
    var period = existing?.goal.period ?? GoalPeriod.week;
    final value = TextEditingController(
      text: (existing?.goal.targetValue ?? 150).toString(),
    );

    showNmSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => NmSheet(
          title: existing == null ? 'Nuevo objetivo' : 'Editar objetivo',
          footer: Row(
            children: <Widget>[
              if (existing != null)
                NmButton.ghost(
                  label: 'Eliminar',
                  onPressed: () async {
                    await ref
                        .read(repositoryProvider)
                        .deleteActivityGoal(existing.goal.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              const Spacer(),
              NmButton(
                label: 'Guardar',
                onPressed: () async {
                  final parsed = int.tryParse(value.text);
                  if (parsed == null || parsed <= 0) return;
                  await ref.read(repositoryProvider).saveActivityGoal(
                    ActivityGoal(
                      id: existing?.goal.id ?? _uuid.v4(),
                      goalType: type,
                      targetValue: parsed,
                      period: period,
                      startDate: existing?.goal.startDate ?? today(),
                    ),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const NmSectionHeader(title: 'Tipo'),
              Wrap(
                spacing: NmSpace.s2,
                runSpacing: NmSpace.s2,
                children: <Widget>[
                  for (final option in ActivityGoalType.values)
                    NmChip(
                      label: option.label,
                      selected: option == type,
                      semanticsInRadioGroup: true,
                      onTap: () => setLocal(() => type = option),
                    ),
                ],
              ),
              const SizedBox(height: NmSpace.s6),
              NmNumberField(label: 'Valor objetivo', controller: value),
              const SizedBox(height: NmSpace.s6),
              const NmSectionHeader(title: 'Período'),
              NmSegmentedControl<GoalPeriod>(
                options: GoalPeriod.values
                    .map((p) => (p, p == GoalPeriod.day ? 'Día' : 'Semana'))
                    .toList(),
                value: period,
                onChanged: (v) => setLocal(() => period = v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// S-26 · Medidas corporales.
class MeasurementsScreen extends ConsumerStatefulWidget {
  const MeasurementsScreen({super.key});

  @override
  ConsumerState<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends ConsumerState<MeasurementsScreen> {
  MeasurementMetric _metric = MeasurementMetric.waist;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final entries = repo.measurements(_metric);
    final points = entries
        .map((m) => ChartPoint(m.localDate, m.value))
        .toList();

    return NmScreen(
      title: 'Medidas corporales',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final metric in MeasurementMetric.values)
                NmChip(
                  label: metric.label,
                  selected: metric == _metric,
                  semanticsInRadioGroup: true,
                  onTap: () => setState(() => _metric = metric),
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s6),
          if (points.length < 2)
            EmptyState(
              compact: true,
              icon: PhosphorIcons.ruler(),
              title: 'Sin registros de ${_metric.label.toLowerCase()}',
              body: 'Con dos registros ya podemos dibujar la serie.',
              primaryLabel: 'Registrar medida',
              onPrimary: () => showMeasurementSheet(context),
            )
          else ...<Widget>[
            NmCard(
              child: WeightChart(
                id: 'measure-${_metric.wire}',
                points: points,
                movingAverage: const <ChartPoint>[],
              ),
            ),
            const SizedBox(height: NmSpace.s6),
            NmCard(
              child: Column(
                children: <Widget>[
                  for (final entry in entries.reversed.take(12))
                    ValueRow(
                      label: friendlyDay(entry.localDate),
                      value: '${Fmt.decimal1(entry.value)} ${entry.unit}',
                    ),
                ],
              ),
            ),
            const SizedBox(height: NmSpace.s6),
            NmButton(
              label: 'Registrar medida',
              block: true,
              onPressed: () => showMeasurementSheet(context),
            ),
          ],
        ],
      ),
    );
  }
}
