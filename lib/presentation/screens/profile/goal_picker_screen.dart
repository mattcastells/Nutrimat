import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/goal_presets.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/services/goal_planner.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Elegir el objetivo: bajar, mantener, subir o ganar músculo.
///
/// Se muestra al crear la cuenta y queda disponible desde Perfil. Guardar deja
/// configurado el objetivo calórico, los macros y la actividad semanal de una;
/// después todo eso se puede tocar por separado en Objetivo y macros.
class GoalPickerScreen extends ConsumerStatefulWidget {
  const GoalPickerScreen({this.isFirstTime = false, super.key});

  /// Al crear la cuenta no hay a dónde volver: en vez de "Atrás" se ofrece
  /// "Ahora no", y guardar lleva a Inicio.
  final bool isFirstTime;

  @override
  ConsumerState<GoalPickerScreen> createState() => _GoalPickerScreenState();
}

class _GoalPickerScreenState extends ConsumerState<GoalPickerScreen> {
  GoalType? _selected;
  bool _saving = false;

  Future<void> _save(GoalPreset preset) async {
    final repo = ref.read(repositoryProvider);
    setState(() => _saving = true);

    await repo.saveGoal(
      GoalPlanner.build(
        preset: preset,
        profile: ref.read(profileProvider),
        weightKg: ref.read(currentWeightProvider),
        current: ref.read(currentGoalProvider),
      ),
    );
    for (final goal in GoalPlanner.activityGoals(
      preset,
      existing: repo.activityGoals,
    )) {
      await repo.saveActivityGoal(goal);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.isFirstTime) {
      context.go(Routes.home);
    } else {
      context.pop();
    }
    NmSnackbar.show(context, 'Objetivo actualizado desde hoy');
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final current = ref.watch(currentGoalProvider);
    final profile = ref.watch(profileProvider);
    final weightKg = ref.watch(currentWeightProvider);
    final selected = _selected ?? current?.goalType;

    return NmScreen(
      title: widget.isFirstTime ? '¿Qué buscás?' : 'Tu objetivo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            widget.isFirstTime
                ? 'Elegí uno para arrancar. Se puede cambiar cuando quieras y '
                      'los días ya registrados no se tocan.'
                : 'Cambiarlo recalcula tus calorías, tus macros y tu objetivo '
                      'de actividad. Rige desde hoy.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s6),

          for (final preset in GoalPreset.all)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s3),
              child: _PresetCard(
                preset: preset,
                selected: preset.goalType == selected,
                weightKg: weightKg,
                onTap: () => setState(() => _selected = preset.goalType),
              ),
            ),

          const SizedBox(height: NmSpace.s4),
          if (!profile.hasBodyData)
            InfoNote(
              tone: NmNoteTone.caution,
              text: 'Sin altura, nacimiento y sexo no podemos calcular las '
                  'calorías: se conserva el objetivo que ya tenías y solo se '
                  'guardan el ritmo y la actividad.',
              action: 'Cargar mis datos',
              onAction: () => context.push(Routes.profileBody),
            )
          else
            const InfoNote(
              text: 'Los valores son un punto de partida, no una indicación '
                  'médica. Si seguís un plan profesional, ajustalos a ese '
                  'plan.',
            ),

          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Guardar objetivo',
            block: true,
            loading: _saving,
            onPressed: selected == null
                ? null
                : () => _save(GoalPreset.of(selected)),
          ),
          if (widget.isFirstTime) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            NmButton.ghost(
              label: 'Ahora no',
              block: true,
              onPressed: () => context.go(Routes.home),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.weightKg,
    required this.onTap,
  });

  final GoalPreset preset;
  final bool selected;
  final double? weightKg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: NmCard(
        onTap: onTap,
        raised: selected,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  selected
                      ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                      : PhosphorIcons.circle(),
                  size: NmIconSize.md,
                  color: selected ? nm.accent : nm.textMuted,
                ),
                const SizedBox(width: NmSpace.s3),
                Expanded(
                  child: Text(
                    preset.goalType.label,
                    style: NmTextStyles.from(NmType.h4, color: nm.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NmSpace.s2),
            Text(
              preset.headline,
              style: NmTextStyles.from(NmType.bodySm, color: nm.text),
            ),
            const SizedBox(height: NmSpace.s3),
            Wrap(
              spacing: NmSpace.s2,
              runSpacing: NmSpace.s2,
              children: <Widget>[
                if (preset.rateKgPerWeek > 0)
                  NmTag(
                    label: '${Fmt.decimal2(preset.rateKgPerWeek)} kg/semana',
                    variant: NmTagVariant.outline,
                  ),
                NmTag(
                  label: weightKg == null
                      ? '${Fmt.decimal1(preset.proteinGPerKg)} g proteína/kg'
                      : '${preset.proteinTargetG(weightKg!)} g de proteína/día',
                  variant: NmTagVariant.outline,
                ),
                NmTag(
                  label: '${preset.activeMinutesPerWeek} min/semana',
                  variant: NmTagVariant.outline,
                ),
                NmTag(
                  label:
                      '${preset.strengthSessionsPerWeek} × fuerza/semana',
                  variant: NmTagVariant.outline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
