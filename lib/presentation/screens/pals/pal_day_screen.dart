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
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/auth_providers.dart';

/// El día de un pal: qué comió y si se movió.
///
/// Solo hoy. Mirar el historial de otra persona no es lo que se pidió, y no
/// publicarlo es lo que hace que no se pueda.
final palDayProvider = FutureProvider.family<PalDay?, String>((
  ref,
  userId,
) async {
  final client = ref.watch(palsClientProvider);
  if (client == null) return null;
  return client.dayOf(userId, today());
});

class PalDayScreen extends ConsumerWidget {
  const PalDayScreen({required this.userId, this.name, super.key});

  final String userId;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final day = ref.watch(palDayProvider(userId));

    return NmScreen(
      title: name ?? 'Su día',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            longDay(today()),
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s4),

          day.when(
            loading: () => const SkeletonList(rows: 4, withAvatar: false),
            error: (error, _) => ErrorState(
              message: error is AppError
                  ? error.message
                  : 'No pudimos cargar su día.',
              onRetry: () => ref.invalidate(palDayProvider(userId)),
            ),
            data: (value) => value == null || value.isEmpty
                ? EmptyState(
                    icon: PhosphorIcons.forkKnife(),
                    title: 'Todavía no cargó nada hoy',
                    body: 'Cuando registre algo va a aparecer acá.',
                  )
                : _Day(day: value),
          ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day});

  final PalDay day;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

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

        const SizedBox(height: NmSpace.s6),
        for (final slot in MealSlot.values)
          if (day.mealsIn(slot).isNotEmpty) ...<Widget>[
            NmSectionHeader(title: slot.label),
            NmCard(
              child: Column(
                children: <Widget>[
                  for (final meal in day.mealsIn(slot))
                    ValueRow(label: meal.name, value: Fmt.kcal(meal.kcal)),
                ],
              ),
            ),
            const SizedBox(height: NmSpace.s4),
          ],

        const SizedBox(height: NmSpace.s2),
        Text(
          'Esto es todo lo que se comparte. Su peso, sus medidas y sus fotos no '
          'salen de su teléfono.',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
      ],
    );
  }
}
