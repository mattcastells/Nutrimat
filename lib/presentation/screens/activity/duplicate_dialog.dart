import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/models/activity.dart';
import '../../../domain/repositories/repositories.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// S-14 · Diálogo de duplicado.
///
/// La app **nunca** borra sola (D-07): sin acción de la persona el registro
/// queda en `needs_review`. No se cierra por tap fuera.
Future<void> showDuplicateDialog(
  BuildContext context,
  WidgetRef ref,
  DuplicateCandidate candidate,
) => showNmDialog<void>(
  context: context,
  dismissible: false,
  builder: (context) => _DuplicateDialog(candidate: candidate),
);

class _DuplicateDialog extends ConsumerWidget {
  const _DuplicateDialog({required this.candidate});

  final DuplicateCandidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);

    Future<void> resolve(DuplicateResolution resolution) async {
      await repo.resolveDuplicate(candidate, resolution);
      if (!context.mounted) return;
      Navigator.of(context).pop();
    }

    return NmDialog(
      title: '¿Son la misma actividad?',
      body: 'Detectamos dos registros que se solapan. Decidí vos qué hacer: '
          'no borramos nada por nuestra cuenta.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: 'Comparación de las dos actividades',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _Column(
                    title: 'La tuya',
                    activity: candidate.existing,
                    other: candidate.incoming,
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                Expanded(
                  child: _Column(
                    title: 'Health Connect',
                    activity: candidate.incoming,
                    other: candidate.existing,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s4),
          InfoNote(
            tone: NmNoteTone.caution,
            text: 'Coincidencia estimada: '
                '${(candidate.score.score * 100).round()} %'
                '${candidate.score.reasons.isEmpty ? '' : ' · '
                      '${candidate.score.reasons.map((r) => r.label).join(' · ')}'}',
          ),
          const SizedBox(height: NmSpace.s4),
          Column(
            children: <Widget>[
              NmButton(
                label: 'Son la misma — quedate con la importada',
                block: true,
                onPressed: () => resolve(DuplicateResolution.keepIncoming),
              ),
              const SizedBox(height: NmSpace.s2),
              NmButton.secondary(
                label: 'Son la misma — quedate con la mía',
                block: true,
                onPressed: () => resolve(DuplicateResolution.keepExisting),
              ),
              const SizedBox(height: NmSpace.s2),
              NmButton.secondary(
                label: 'Son distintas — guardá las dos',
                block: true,
                onPressed: () => resolve(DuplicateResolution.keepBoth),
              ),
              const SizedBox(height: NmSpace.s2),
              NmButton.ghost(
                label: 'Decidir después',
                block: true,
                onPressed: () => resolve(DuplicateResolution.defer),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s2),
          Text(
            'Lo que descartes se puede recuperar durante 30 días.',
            style: NmTextStyles.from(NmType.micro, color: nm.textMuted),
          ),
        ],
      ),
      actions: const <Widget>[],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.activity,
    required this.other,
  });

  final String title;
  final Activity activity;
  final Activity other;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    Widget row(String label, String value, {required bool differs}) => Padding(
      padding: const EdgeInsets.only(bottom: NmSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: NmTextStyles.from(NmType.micro, color: nm.textMuted),
          ),
          Text(
            value,
            style: NmTextStyles.from(
              NmType.bodySm,
              color: differs ? nm.caution : nm.text,
            ).tnum,
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(NmSpace.s3),
      decoration: BoxDecoration(
        color: nm.surfaceRaised,
        borderRadius: NmRadius.brMd,
        border: Border.all(color: nm.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: NmTextStyles.from(NmType.h4, color: nm.text)),
          const SizedBox(height: NmSpace.s3),
          row(
            'Tipo',
            activity.displayName,
            differs: activity.activityTypeId != other.activityTypeId,
          ),
          row(
            'Horario',
            timeOfDay(activity.startedAt),
            differs:
                activity.startedAt.difference(other.startedAt).inMinutes.abs() >
                5,
          ),
          row(
            'Duración',
            Fmt.duration(activity.durationMinutes),
            differs: activity.durationMinutes != other.durationMinutes,
          ),
          if (activity.distanceMeters != null)
            row(
              'Distancia',
              '${(activity.distanceMeters! / 1000).toStringAsFixed(2)} km',
              differs: activity.distanceMeters != other.distanceMeters,
            ),
          row(
            'Calorías',
            Fmt.estimatedKcal(activity.estimatedCalories),
            differs:
                (activity.estimatedCalories - other.estimatedCalories).abs() >
                20,
          ),
        ],
      ),
    );
  }
}

/// Advertencia no bloqueante de solapamiento al guardar (F-08).
Future<bool> showOverlapWarning(
  BuildContext context,
  DuplicateCandidate candidate,
) async {
  final result = await showNmDialog<bool>(
    context: context,
    builder: (context) => NmDialog(
      title: 'Ya tenés una actividad en ese horario',
      body:
          '${candidate.existing.displayName} · '
          '${timeOfDay(candidate.existing.startedAt)} · '
          '${Fmt.duration(candidate.existing.durationMinutes)}. '
          '¿Es otra distinta?',
      actions: <Widget>[
        NmButton.ghost(
          label: 'Volver a revisar',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NmButton(
          label: 'Sí, es otra',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
