import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../providers/app_providers.dart';

/// `sheet.date_picker` — calendario mensual con densidad de registro.
Future<void> showDatePickerSheet(BuildContext context) => showNmSheet<void>(
  context: context,
  builder: (context) => const _DatePickerSheet(),
);

class _DatePickerSheet extends ConsumerStatefulWidget {
  const _DatePickerSheet();

  @override
  ConsumerState<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends ConsumerState<_DatePickerSheet> {
  late DateTime _month = DateTime(
    ref.read(selectedDateProvider).year,
    ref.read(selectedDateProvider).month,
  );

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final selected = ref.watch(selectedDateProvider);
    final withRecords = ref.watch(daysWithRecordsProvider);
    final today_ = today();

    final firstWeekday = DateTime(_month.year, _month.month).weekday;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return NmSheet(
      title: 'Elegir día',
      trailing: NmButton.ghost(
        label: 'Hoy',
        onPressed: () {
          ref.read(selectedDateProvider.notifier).goToToday();
          Navigator.of(context).pop();
        },
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              NmIconButton(
                icon: Icons.chevron_left,
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                tooltip: 'Mes anterior',
              ),
              Expanded(
                child: Text(
                  monthTitle(_month),
                  textAlign: TextAlign.center,
                  style: NmTextStyles.from(NmType.h4, color: nm.text),
                ),
              ),
              NmIconButton(
                icon: Icons.chevron_right,
                onPressed:
                    DateTime(_month.year, _month.month).isBefore(
                      DateTime(today_.year, today_.month),
                    )
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      )
                    : null,
                tooltip: 'Mes siguiente',
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s3),
          Row(
            children: <Widget>[
              for (final label in const <String>[
                'L',
                'M',
                'M',
                'J',
                'V',
                'S',
                'D',
              ])
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: NmTextStyles.from(
                      NmType.micro,
                      color: nm.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s2),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: firstWeekday - 1 + daysInMonth,
            itemBuilder: (context, index) {
              if (index < firstWeekday - 1) return const SizedBox.shrink();
              final day = DateTime(
                _month.year,
                _month.month,
                index - firstWeekday + 2,
              );
              final isSelected = isSameDay(day, selected);
              final hasRecords = withRecords.contains(isoDate(day));
              final isFutureDay = day.isAfter(today_);

              return Center(
                child: Semantics(
                  selected: isSelected,
                  label: longDay(day),
                  child: ExcludeSemantics(
                    child: InkResponse(
                      onTap: isFutureDay
                          ? null
                          : () {
                              ref
                                  .read(selectedDateProvider.notifier)
                                  .set(day);
                              Navigator.of(context).pop();
                            },
                      child: Container(
                        height: 38,
                        width: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? nm.accentFill : null,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: nm.accent)
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${day.day}',
                              style: NmTextStyles.from(
                                NmType.bodySm,
                                color: isFutureDay
                                    ? nm.textMuted.withValues(alpha: 0.4)
                                    : (isSelected
                                          ? nm.accentOnFill
                                          : nm.text),
                              ).tnum,
                            ),
                            SizedBox(
                              height: 4,
                              child: hasRecords
                                  ? Container(
                                      height: 3,
                                      width: 3,
                                      decoration: BoxDecoration(
                                        color: nm.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: NmSpace.s3),
          Row(
            children: <Widget>[
              Container(
                height: 4,
                width: 4,
                decoration: BoxDecoration(
                  color: nm.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: NmSpace.s2),
              Text(
                'Días con registros',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
