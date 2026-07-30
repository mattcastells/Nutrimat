import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
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
import '../weight/measurement_sheet.dart';
import '../weight/weight_sheet.dart';

const _uuid = Uuid();

/// Gráfico de peso ampliado.
class WeightChartScreen extends ConsumerWidget {
  const WeightChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final progress = ref.watch(progressProvider);
    final units = ref.watch(unitSystemProvider);
    final repo = ref.watch(repositoryProvider);
    final logs = repo.weightLogs;

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
          StatCardRow(
            children: <Widget>[
              StatCard(
                label: 'Variación',
                value:
                    '${Fmt.signedDecimal1(progress.weightDeltaKg)} '
                    '${Fmt.weightUnit(units)}',
              ),
              StatCard(
                label: 'Tendencia semanal',
                value: progress.trendKgPerWeek == null
                    ? '—'
                    : '${Fmt.signedDecimal1(progress.trendKgPerWeek!)} kg',
                caption: progress.trendKgPerWeek == null
                    ? 'Necesitamos unos días más de registro'
                    : null,
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s8),
          const NmSectionHeader(title: 'Registros'),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s1),
            child: Column(
              children: <Widget>[
                for (final log in logs.take(20))
                  Dismissible(
                    key: ValueKey<String>(log.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NmSpace.s6,
                      ),
                      decoration: BoxDecoration(
                        color: nm.danger.withValues(alpha: 0.14),
                        borderRadius: NmRadius.brMd,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            PhosphorIcons.trash(),
                            size: NmIconSize.md,
                            color: nm.danger,
                          ),
                          const SizedBox(width: NmSpace.s2),
                          Text(
                            'Eliminar',
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                    confirmDismiss: (_) async {
                      final id = log.id;
                      await repo.deleteWeight(id);
                      if (context.mounted) {
                        NmSnackbar.show(
                          context,
                          'Registro eliminado',
                          actionLabel: 'Deshacer',
                          undo: true,
                          onAction: () => repo.restoreWeight(id),
                        );
                      }
                      return false;
                    },
                    child: ValueRow(
                      label: friendlyDay(log.localDate),
                      value: Fmt.weight(log.weightKg, units),
                      onEdit: () =>
                          showWeightSheet(context, date: log.localDate),
                    ),
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
          StatCardRow(
            children: <Widget>[
              StatCard(
                label: 'Promedio diario',
                value: Fmt.kcal(progress.averageConsumed),
              ),
              StatCard(
                label: 'Adherencia',
                value: progress.adherencePct == null
                    ? '—'
                    : Fmt.percent(progress.adherencePct!),
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
          StatCardRow(
            children: <Widget>[
              StatCard(
                label: 'Minutos activos',
                value: Fmt.duration(totals.minutes),
                caption: progress.previousWeekDeltaMinutes == 0
                    ? 'Igual que la semana anterior'
                    : '${Fmt.signed(progress.previousWeekDeltaMinutes)} min '
                          'vs. la semana anterior',
                icon: PhosphorIcons.timer(),
              ),
              if (progress.stepsAverage != null)
                StatCard(
                  label: 'Pasos promedio',
                  value: Fmt.steps(progress.stepsAverage!),
                  icon: PhosphorIcons.footprints(),
                )
              else
                const SizedBox.shrink(),
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
  MeasurementGroup _group = MeasurementGroup.perimeters;
  MeasurementMetric _metric = MeasurementMetric.waist;

  void _selectGroup(MeasurementGroup group) => setState(() {
    _group = group;
    // La métrica elegida tiene que pertenecer al grupo visible, si no el
    // gráfico muestra una serie que no está en ninguna de las opciones.
    if (_metric.group != group) _metric = MeasurementMetric.inGroup(group).first;
  });

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    // Se lee para que la pantalla se redibuje al guardar desde el sheet.
    ref.watch(appRevisionProvider);

    final entries = repo.measurements(_metric);
    final points = entries
        .map((m) => ChartPoint(m.localDate, m.value))
        .toList();
    final last = entries.isEmpty ? null : entries.last;

    return NmScreen(
      title: 'Medidas corporales',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmSegmentedControl<MeasurementGroup>(
            options: const <(MeasurementGroup, String)>[
              (MeasurementGroup.perimeters, 'Perímetros'),
              (MeasurementGroup.skinfolds, 'Pliegues'),
              (MeasurementGroup.composition, 'Balanza'),
            ],
            value: _group,
            onChanged: _selectGroup,
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            _group.help,
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s4),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final metric in MeasurementMetric.inGroup(_group))
                NmChip(
                  label: metric.longLabel,
                  selected: metric == _metric,
                  semanticsInRadioGroup: true,
                  onTap: () => setState(() => _metric = metric),
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s6),

          if (last != null) ...<Widget>[
            NmCard(
              child: ValueRow(
                label: 'Último registro',
                caption: friendlyDay(last.localDate),
                value: '${Fmt.decimal1(last.value)} ${last.unit}'.trim(),
                emphasis: true,
              ),
            ),
            const SizedBox(height: NmSpace.s4),
          ],

          if (points.length < 2)
            EmptyState(
              compact: true,
              icon: PhosphorIcons.ruler(),
              title: last == null
                  ? 'Sin registros de ${_metric.label.toLowerCase()}'
                  : 'Falta un registro más',
              body: 'Con dos registros ya podemos dibujar la serie.',
              primaryLabel: 'Registrar medidas',
              onPrimary: () => showMeasurementSheet(context, group: _group),
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
                      value: '${Fmt.decimal1(entry.value)} ${entry.unit}'
                          .trim(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NmSpace.s6),
            NmButton(
              label: 'Registrar medidas',
              block: true,
              onPressed: () => showMeasurementSheet(context, group: _group),
            ),
          ],

          const SizedBox(height: NmSpace.s6),
          Text(
            'El peso se registra desde Inicio y la altura en Perfil corporal: '
            'los dos alimentan otros cálculos, así que viven ahí y no acá.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
