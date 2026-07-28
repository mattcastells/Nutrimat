import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/models/app_release.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/update_providers.dart';

/// Buscar actualizaciones (Configuración → Actualizaciones).
///
/// Nutrimat se distribuye por fuera de Play Store, así que el aviso de versión
/// nueva lo da la app: consulta los releases del repositorio, y si hay una
/// posterior a la instalada ofrece bajarla e instalarla.
///
/// El chequeo lo dispara la persona. No hay consulta automática al abrir la
/// app ni descarga que arranque sola: bajar 25 MB con datos móviles sin haberlo
/// pedido no es una decisión que le toque tomar al software.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

enum _Phase { idle, checking, checked, downloading, installing }

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  _Phase _phase = _Phase.idle;
  UpdateStatus? _status;
  AppError? _error;
  double _progress = 0;

  Future<void> _check() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
      _status = null;
    });

    try {
      final current = await ref.read(installedVersionProvider.future);
      final status = await ref
          .read(updateServiceProvider)
          .check(current: current);
      if (!mounted) return;
      setState(() {
        _status = status;
        _phase = _Phase.checked;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _phase = _Phase.idle;
      });
    }
  }

  Future<void> _install(AppRelease release) async {
    setState(() {
      _phase = _Phase.downloading;
      _error = null;
      _progress = 0;
    });

    try {
      await ref
          .read(updateServiceProvider)
          .downloadAndInstall(
            release,
            onProgress: (value) {
              if (!mounted) return;
              setState(() => _progress = value);
            },
          );
      if (!mounted) return;
      // A partir de acá manda el diálogo de Android; la app queda esperando.
      setState(() => _phase = _Phase.installing);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _phase = _Phase.checked;
      });
    }
  }

  Future<void> _openReleasePage(AppRelease release) async {
    final uri = ref.read(updateServiceProvider).releasePage(release);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final installed = ref.watch(installedVersionLabelProvider);

    return NmScreen(
      title: 'Actualizaciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NmCard(
            child: ValueRow(
              label: 'Versión instalada',
              value: installed.maybeWhen(
                data: (value) => value,
                orElse: () => '—',
              ),
            ),
          ),
          const SizedBox(height: NmSpace.s4),

          if (_error != null) ...<Widget>[
            ErrorState(
              message: _error!.message,
              code: _error!.code.wire,
              onRetry: _phase == _Phase.idle ? _check : null,
            ),
            const SizedBox(height: NmSpace.s4),
          ],

          switch (_phase) {
            _Phase.checking => const _Busy(label: 'Buscando actualizaciones…'),
            _Phase.downloading => _Downloading(progress: _progress),
            _Phase.installing => const InfoNote(
              text:
                  'Android está instalando. Cuando termine, volvé a abrir la app.',
              tone: NmNoteTone.success,
            ),
            _ => _Result(
              status: _status,
              onCheck: _check,
              onInstall: _install,
              onOpenPage: _openReleasePage,
            ),
          },

          const SizedBox(height: NmSpace.s6),
          Text(
            'La primera vez, Android te va a pedir permiso para instalar.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const NmSpinner(size: 20),
      const SizedBox(width: NmSpace.s3),
      Text(
        label,
        style: NmTextStyles.from(NmType.bodySm, color: context.nm.textMuted),
      ),
    ],
  );
}

class _Downloading extends StatelessWidget {
  const _Downloading({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final percent = (progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          value: '$percent por ciento',
          child: ClipRRect(
            borderRadius: NmRadius.brSm,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: nm.surfaceRaised,
              valueColor: AlwaysStoppedAnimation<Color>(nm.accent),
            ),
          ),
        ),
        const SizedBox(height: NmSpace.s2),
        Text(
          'Descargando… $percent %',
          style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.status,
    required this.onCheck,
    required this.onInstall,
    required this.onOpenPage,
  });

  final UpdateStatus? status;
  final VoidCallback onCheck;
  final void Function(AppRelease) onInstall;
  final void Function(AppRelease) onOpenPage;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return switch (status) {
      null => NmButton(label: 'Buscar actualizaciones', onPressed: onCheck),

      UpToDate() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(PhosphorIcons.checkCircle(), size: 20, color: nm.success),
              const SizedBox(width: NmSpace.s2),
              Text('Estás al día', style: NmTextStyles.from(NmType.body)),
            ],
          ),
          const SizedBox(height: NmSpace.s4),
          NmButton.secondary(label: 'Buscar de nuevo', onPressed: onCheck),
        ],
      ),

      NoReleasesYet() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const InfoNote(
            text:
                'Todavía no hay ninguna versión publicada.',
          ),
          const SizedBox(height: NmSpace.s4),
          NmButton.secondary(label: 'Buscar de nuevo', onPressed: onCheck),
        ],
      ),

      final UpdateAvailable available => _Available(
        available: available,
        onInstall: onInstall,
        onOpenPage: onOpenPage,
      ),
    };
  }
}

class _Available extends StatelessWidget {
  const _Available({
    required this.available,
    required this.onInstall,
    required this.onOpenPage,
  });

  final UpdateAvailable available;
  final void Function(AppRelease) onInstall;
  final void Function(AppRelease) onOpenPage;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final release = available.release;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const NmTag(label: 'Versión nueva', variant: NmTagVariant.accent),
            const SizedBox(width: NmSpace.s2),
            Text(
              '${available.current} → ${release.version}',
              style: NmTextStyles.from(NmType.body),
            ),
          ],
        ),
        const SizedBox(height: NmSpace.s3),
        Text(
          'Publicada el ${longDay(release.publishedAt)} · '
          '${release.apkSizeLabel}',
          style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
        ),

        if (release.notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: NmSpace.s4),
          const NmSectionHeader(title: 'Qué cambió'),
          NmCard(
            child: Text(
              release.notes,
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
          ),
        ],

        const SizedBox(height: NmSpace.s5),
        NmButton(
          label: 'Descargar e instalar',
          onPressed: () => onInstall(release),
        ),
        const SizedBox(height: NmSpace.s2),
        NmButton.ghost(
          label: 'Ver en GitHub',
          onPressed: () => onOpenPage(release),
        ),
      ],
    );
  }
}
