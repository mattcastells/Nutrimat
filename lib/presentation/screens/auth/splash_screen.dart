import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../components/brand/brand_mark.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';

/// S-01 · Splash. Decide el destino inicial sin parpadeos.
///
/// `checking` dura como máximo 1500 ms; si excede, se navega igual con los
/// datos locales.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final repo = ref.read(repositoryProvider);
    if (!repo.hasSession) {
      context.go(Routes.welcome);
      return;
    }

    // Con servidor configurado, el perfil local no alcanza: si la sesión de
    // Supabase caducó o se revocó desde otro lado, hay que volver a entrar.
    // El modo demo (D-15) queda afuera a propósito — nunca tuvo cuenta.
    final needsAccount =
        ref.read(isCloudEnabledProvider) && !repo.profile.isDemo;
    if (needsAccount && ref.read(authGatewayProvider).currentAccount == null) {
      context.go(Routes.welcome);
      return;
    }

    // Con la sesión ya guardada no se pasa por la pantalla de entrar, así que
    // la puerta del respaldo hay que abrirla acá. Si no, la app dejaría de
    // respaldar en silencio en cada arranque normal.
    // Primero las tablas: son la persistencia con la que queremos quedarnos.
    // Si traen algo, el respaldo JSON ya no tiene que restaurar nada y su
    // puerta se abre igual, sin pisar lo que acabamos de traer.
    final desdeTablas = await ref
        .read(relationalSyncProvider)
        ?.openAfterPull(
          localIsEmpty: !repo.hasUserData,
          apply: repo.importDocument,
        );

    await ref
        .read(cloudBackupProvider)
        ?.openAfterRestore(
          localIsEmpty: (desdeTablas ?? false) ? false : !repo.hasUserData,
          apply: (json) => repo.importJson(json),
        );

    if (!mounted) return;
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Scaffold(
      backgroundColor: nm.bg,
      body: Center(
        child: Semantics(
          label: 'Nutrimat, cargando',
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: context.motion.reduced ? 1 : 0, end: 1),
            duration: context.motion.fade(NmMotion.base),
            curve: NmMotion.ease,
            builder: (context, t, child) => Opacity(opacity: t, child: child),
            child: const BrandWordmark(markSize: 44),
          ),
        ),
      ),
    );
  }
}
