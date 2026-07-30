import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/pal.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/meal_photo.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/auth_providers.dart';

/// Hasta cuántos días atrás se puede mirar el día de un pal.
const int palDayHistoryDays = 7;

/// El día de un pal, organizado por categoría igual que Inicio.
///
/// Lo que aparece depende de lo que esa persona decidió compartir (Perfil →
/// Pals → Qué ven mis pals): comida y el agregado de actividad siempre están;
/// fotos, agua, sueño y el detalle de cada actividad, solo si los prendió.
final palDayProvider = FutureProvider.family<PalDay?, ({String userId, DateTime date})>((
  ref,
  args,
) async {
  final client = ref.watch(palsClientProvider);
  if (client == null) return null;
  return client.dayOf(args.userId, args.date);
});

class PalDayScreen extends ConsumerStatefulWidget {
  const PalDayScreen({required this.userId, this.name, super.key});

  final String userId;
  final String? name;

  @override
  ConsumerState<PalDayScreen> createState() => _PalDayScreenState();
}

class _PalDayScreenState extends ConsumerState<PalDayScreen> {
  late DateTime _date = today();

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(
      palDayProvider((userId: widget.userId, date: _date)),
    );
    final isToday = isSameDay(_date, today());

    return NmScreen(
      title: widget.name ?? 'Su día',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          _DaySelector(date: _date, onChange: (d) => setState(() => _date = d)),
          const SizedBox(height: NmSpace.s4),

          day.when(
            loading: () => const SkeletonList(rows: 4, withAvatar: false),
            error: (error, _) => ErrorState(
              message: error is AppError
                  ? error.message
                  : 'No pudimos cargar su día.',
              onRetry: () => ref.invalidate(
                palDayProvider((userId: widget.userId, date: _date)),
              ),
            ),
            data: (value) => value == null || value.isEmpty
                ? EmptyState(
                    icon: PhosphorIcons.forkKnife(),
                    title: isToday
                        ? 'Todavía no cargó nada hoy'
                        : 'No cargó nada ese día',
                    body: isToday
                        ? 'Cuando registre algo va a aparecer acá.'
                        : 'No hay nada compartido para esta fecha.',
                  )
                : _Day(day: value),
          ),
        ],
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({required this.date, required this.onChange});

  final DateTime date;
  final ValueChanged<DateTime> onChange;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final oldestVisible = today().subtract(
      const Duration(days: palDayHistoryDays),
    );
    final canGoBack = date.isAfter(oldestVisible);
    final canGoForward = date.isBefore(today());

    return Row(
      children: <Widget>[
        NmIconButton(
          icon: PhosphorIcons.caretLeft(),
          tooltip: 'Día anterior',
          onPressed: canGoBack
              ? () => onChange(date.subtract(const Duration(days: 1)))
              : null,
        ),
        Expanded(
          child: Column(
            children: <Widget>[
              Text(
                friendlyDay(date),
                textAlign: TextAlign.center,
                style: NmTextStyles.from(NmType.h3, color: nm.text),
              ),
              Text(
                longDay(date),
                textAlign: TextAlign.center,
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ],
          ),
        ),
        NmIconButton(
          icon: PhosphorIcons.caretRight(),
          tooltip: 'Día siguiente',
          onPressed: canGoForward
              ? () => onChange(date.add(const Duration(days: 1)))
              : null,
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day});

  final PalDay day;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    final shared = <String>[
      'lo que comió',
      if (day.activities.isNotEmpty || day.activityCount > 0) 'si se movió',
      if (day.waterGlasses != null) 'el agua',
      if (day.sleepMinutes != null) 'el sueño',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NmCard(
          child: Column(
            children: <Widget>[
              ValueRow(
                label: 'Comió',
                value: Fmt.kcal(day.totalKcal),
                emphasis: true,
              ),
              ValueRow(
                label: 'Se movió',
                value: day.activityCount == 0
                    ? 'Todavía no'
                    : '${day.activityCount} '
                          '${day.activityCount == 1 ? 'vez' : 'veces'} · '
                          '${Fmt.duration(day.activityMinutes)}',
                muted: day.activityCount == 0,
              ),
            ],
          ),
        ),

        for (final slot in MealSlot.values)
          if (day.mealsIn(slot).isNotEmpty) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            NmSectionHeader(title: slot.label),
            NmCard(
              child: Column(
                children: <Widget>[
                  for (final meal in day.mealsIn(slot)) ...<Widget>[
                    if (meal.photoPath != null) ...<Widget>[
                      MealPhoto(path: meal.photoPath, height: 160),
                      const SizedBox(height: NmSpace.s2),
                    ],
                    ValueRow(label: meal.name, value: Fmt.kcal(meal.kcal)),
                  ],
                ],
              ),
            ),
          ],

        if (day.activities.isNotEmpty) ...<Widget>[
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Actividad'),
          NmCard(
            child: Column(
              children: <Widget>[
                for (final activity in day.activities)
                  ValueRow(
                    label: activity.name,
                    caption: Fmt.duration(activity.minutes),
                    value: activity.kcal == null ? '—' : Fmt.kcal(activity.kcal!),
                  ),
              ],
            ),
          ),
        ],

        if (day.waterGlasses != null) ...<Widget>[
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Agua'),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s1),
            child: NmListRow(
              title: '${day.waterGlasses} vasos',
              leading: Icon(PhosphorIcons.drop(), size: 20, color: nm.info),
            ),
          ),
        ],

        if (day.sleepMinutes != null) ...<Widget>[
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Sueño'),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s1),
            child: NmListRow(
              title: Fmt.duration(day.sleepMinutes!),
              subtitle: day.sleepQuality?.label,
              leading: Icon(PhosphorIcons.moon(), size: 20, color: nm.info),
            ),
          ),
        ],

        const SizedBox(height: NmSpace.s6),
        Text(
          'Esto es lo que decidió compartir: ${shared.join(', ')}. '
          'Su peso y sus medidas nunca se comparten.',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
      ],
    );
  }
}
