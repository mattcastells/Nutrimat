import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/models/summaries.dart';
import '../charts/calorie_ring.dart';
import '../system/surfaces.dart';

/// La tarjeta principal de Inicio (S-06). ★
///
/// Muestra **siempre por separado** objetivo base, consumido, actividad,
/// ajuste aplicado, objetivo ajustado y restantes: el objetivo base nunca se
/// modifica por el ejercicio (RN-01). Con crédito 0 % la fila de ajuste
/// desaparece y en su lugar va el texto tenue de D-02.
class DailySummaryCard extends StatelessWidget {
  const DailySummaryCard({
    required this.summary,
    required this.onBreakdown,
    required this.onChangeCredit,
    super.key,
  });

  final DailySummary summary;
  final VoidCallback onBreakdown;
  final VoidCallback onChangeCredit;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final balance = summary.balance;

    return NmCard(
      padding: const EdgeInsets.all(NmSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: CalorieRing(
              consumed: summary.consumedKcal,
              adjustedTarget: summary.adjustedTarget,
              remaining: summary.remainingKcal,
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          ValueRow(
            label: 'Objetivo base',
            value: Fmt.integer(summary.baseTarget),
          ),
          const NmDivider(),
          ValueRow(
            label: 'Consumido',
            value: '−${Fmt.integer(summary.consumedKcal)}',
          ),
          const NmDivider(),
          ValueRow(
            label: 'Actividad',
            caption: '≈ estimado',
            value: Fmt.integer(summary.exerciseEstimatedKcal),
          ),
          const NmDivider(),
          if (balance.showsAdjustmentRow) ...<Widget>[
            ValueRow(
              label: 'Ajuste aplicado',
              caption: '${summary.creditPercentage} % del ejercicio',
              value: '+${Fmt.integer(summary.exerciseAppliedKcal)}',
            ),
            const NmDivider(),
            ValueRow(
              label: 'Objetivo ajustado',
              value: Fmt.integer(summary.adjustedTarget),
            ),
            const NmDivider(),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NmSpace.s3),
              child: InkWell(
                onTap: onChangeCredit,
                borderRadius: NmRadius.brSm,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'El ejercicio no suma a tu presupuesto',
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                    ),
                    Text(
                      'Cambiar',
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.isDark ? nm.accentText : nm.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ValueRow(
            label: balance.isOverBudget ? 'Te pasaste por' : 'Te quedan',
            value: '${Fmt.integer(summary.remainingKcal.abs())} kcal',
            emphasis: true,
            valueColor: balance.isOverBudget ? nm.overBudget : null,
          ),
          const SizedBox(height: NmSpace.s3),
          InkWell(
            onTap: onBreakdown,
            borderRadius: NmRadius.brSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    PhosphorIcons.info(),
                    size: NmIconSize.sm,
                    color: nm.isDark ? nm.accentText : nm.accent,
                  ),
                  const SizedBox(width: NmSpace.s2),
                  Text(
                    '¿Cómo se calcula?',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.isDark ? nm.accentText : nm.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton de Inicio: un bloque de tarjeta con un círculo (el anillo) y
/// cuatro líneas (21-motion §4.2).
class DailySummarySkeleton extends StatelessWidget {
  const DailySummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) => const NmCard(
    padding: EdgeInsets.all(NmSpace.s6),
    child: Column(
      children: <Widget>[
        Center(child: _Circle()),
        SizedBox(height: NmSpace.s6),
        _Line(),
        SizedBox(height: NmSpace.s4),
        _Line(),
        SizedBox(height: NmSpace.s4),
        _Line(),
        SizedBox(height: NmSpace.s4),
        _Line(),
      ],
    ),
  );
}

class _Circle extends StatelessWidget {
  const _Circle();

  @override
  Widget build(BuildContext context) => Container(
    height: 176,
    width: 176,
    decoration: BoxDecoration(
      color: context.nm.skeleton,
      shape: BoxShape.circle,
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line();

  @override
  Widget build(BuildContext context) => Container(
    height: 12,
    decoration: BoxDecoration(
      color: context.nm.skeleton,
      borderRadius: NmRadius.brMd,
    ),
  );
}
