import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../components/brand/brand_mark.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/update_providers.dart';

/// S-27 · Perfil.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final profile = ref.watch(profileProvider);
    final goal = ref.watch(currentGoalProvider);
    final pending = ref.watch(pendingCountProvider);
    final repo = ref.watch(repositoryProvider);

    return NmScreen(
      title: 'Perfil',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: Row(
              children: <Widget>[
                Container(
                  height: 52,
                  width: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: nm.accentFill,
                    borderRadius: BorderRadius.circular(NmRadius.full),
                  ),
                  child: Text(
                    (profile.displayName ?? profile.email ?? 'N')
                        .characters
                        .first
                        .toUpperCase(),
                    style: NmTextStyles.from(
                      NmType.h3,
                      color: nm.accentOnFill,
                    ),
                  ),
                ),
                const SizedBox(width: NmSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        profile.displayName ?? 'Tu perfil',
                        style: NmTextStyles.from(NmType.h4, color: nm.text),
                      ),
                      Text(
                        profile.isDemo
                            ? 'Modo demo · sin respaldo'
                            : profile.email ?? '',
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (profile.isDemo)
                  NmButton.ghost(
                    label: 'Crear cuenta',
                    onPressed: () => context.push(Routes.signUp),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          if (goal != null)
            NmCard(
              child: Column(
                children: <Widget>[
                  ValueRow(
                    label: 'Objetivo vigente',
                    value: Fmt.kcal(goal.baseCalorieTarget),
                    emphasis: true,
                  ),
                  ValueRow(
                    label: goal.goalType.label,
                    value: goal.goalType.name == 'maintain'
                        ? '—'
                        : '${Fmt.decimal2(goal.rateKgPerWeek)} kg/semana',
                    muted: true,
                  ),
                  ValueRow(
                    label: 'El ejercicio suma',
                    value: profile.effectiveCreditPercentage == 0
                        ? 'No suma'
                        : '${profile.effectiveCreditPercentage} %',
                    muted: true,
                  ),
                ],
              ),
            ),
          const SizedBox(height: NmSpace.s6),
          NmCard(
            padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
            child: Column(
              children: <Widget>[
                NmListRow(
                  title: 'Perfil corporal',
                  subtitle: 'Sexo, nacimiento, altura, nivel de actividad',
                  leading: Icon(PhosphorIcons.user()),
                  onTap: () => context.push(Routes.profileBody),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Objetivo y macros',
                  subtitle: 'Cómo se calcula tu objetivo diario',
                  leading: Icon(PhosphorIcons.target()),
                  onTap: () => context.push(Routes.profileTarget),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Mis alimentos y plantillas',
                  subtitle: 'Alimentos propios, actividades, favoritos',
                  leading: Icon(PhosphorIcons.bowlFood()),
                  onTap: () => context.push(Routes.profileFoods),
                ),
                const NmDivider(indent: NmSpace.s6),
                NmListRow(
                  title: 'Configuración',
                  leading: Icon(PhosphorIcons.gear()),
                  onTap: () => context.push(Routes.settings),
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s8),
          NmButton.secondary(
            label: 'Cerrar sesión',
            block: true,
            icon: PhosphorIcons.signOut(),
            onPressed: () async {
              if (pending > 0) {
                final confirmed = await showNmDialog<bool>(
                  context: context,
                  builder: (context) => NmDialog(
                    title: 'Tenés registros sin sincronizar',
                    body:
                        'Tenés $pending ${pending == 1 ? 'registro' : 'registros'} '
                        'sin sincronizar. Si cerrás sesión se pierden.',
                    actions: <Widget>[
                      NmButton.ghost(
                        label: 'Volver',
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      NmButton(
                        label: 'Cerrar sesión igual',
                        variant: NmButtonVariant.danger,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
              }
              // Primero el servidor y después lo local: si se hiciera al
              // revés y el cierre remoto fallara, quedaría una sesión abierta
              // sin ninguna pantalla desde donde cerrarla.
              await ref.read(authGatewayProvider).signOut();
              await repo.signOut();
              if (!context.mounted) return;
              context.go(Routes.welcome);
            },
          ),
          const SizedBox(height: NmSpace.s8),
          Center(
            child: Column(
              children: <Widget>[
                const BrandMark(size: 28, monochrome: true),
                const SizedBox(height: NmSpace.s2),
                Text(
                  ref
                      .watch(installedVersionLabelProvider)
                      .maybeWhen(
                        data: (v) => 'Nutrimat ',
                        orElse: () => 'Nutrimat',
                      ),
                  style: NmTextStyles.from(NmType.micro, color: nm.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
