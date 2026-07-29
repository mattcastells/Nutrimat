import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../data/remote/cloud_backup_client.dart';
import '../../../domain/services/cloud_backup_service.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';

/// Respaldo en la nube (Configuración → Respaldo en la nube).
///
/// La copia sube sola cada vez que cambia algo; esta pantalla existe para
/// mirarla, forzarla y —lo importante— **restaurarla en un teléfono nuevo**.
class CloudBackupScreen extends ConsumerStatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  ConsumerState<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends ConsumerState<CloudBackupScreen> {
  CloudBackupInfo? _remote;
  bool _loading = true;
  bool _restoring = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final info = await service.remoteInfo();
      if (!mounted) return;
      setState(() {
        _remote = info;
        _loading = false;
        _error = null;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _backupNow() async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) return;
    setState(() => _error = null);
    await service.flush();
    await _load();
  }

  Future<void> _restore() async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) return;

    // Restaurar pisa todo lo que hay en el teléfono. Si alguien cargó cosas
    // acá desde la última copia, las pierde: eso se pregunta, no se asume.
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Traer la copia de la nube?',
        body:
            'Se reemplaza todo lo que tenés en este teléfono por la copia '
            'guardada. Lo que hayas registrado acá después de esa fecha se '
            'pierde.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Reemplazar',
            variant: NmButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _restoring = true;
      _error = null;
    });

    try {
      final json = await service.restore();
      if (json == null) {
        if (!mounted) return;
        setState(() {
          _restoring = false;
          _error = const AppError(
            code: ApiErrorCode.notFound,
            message: 'No hay ninguna copia guardada todavía.',
          );
        });
        return;
      }
      await ref.read(repositoryProvider).importJson(json);
      if (!mounted) return;
      setState(() => _restoring = false);
      NmSnackbar.show(context, 'Listo: se restauró la copia de la nube.');
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final state = ref.watch(backupStateProvider).valueOrNull;

    if (state is BackupUnavailable) {
      return NmScreen(
        title: 'Respaldo en la nube',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: NmSpace.s4),
            InfoNote(text: state.reason, tone: NmNoteTone.caution),
            const SizedBox(height: NmSpace.s4),
            Text(
              'Tus datos siguen guardados en este teléfono. Podés exportarlos '
              'a un archivo desde Configuración → Privacidad.',
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
          ],
        ),
      );
    }

    return NmScreen(
      title: 'Respaldo en la nube',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),

          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(label: 'Estado', value: _statusLabel(state)),
                ValueRow(
                  label: 'Última copia',
                  value: _loading
                      ? '…'
                      : _remote == null
                      ? 'Todavía ninguna'
                      : '${longDay(_remote!.updatedAt)} '
                            '${timeOfDay(_remote!.updatedAt)}',
                ),
                if (_remote != null)
                  ValueRow(label: 'Tamaño', value: _remote!.sizeLabel),
              ],
            ),
          ),

          // El error puede venir de esta pantalla o del último intento
          // automático: si el estado dice "falló" y no se muestra el motivo,
          // no hay forma de saber qué pasó.
          if (_error != null || state is BackupFailed) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            Builder(
              builder: (context) {
                final error =
                    _error ?? (state as BackupFailed).error;
                return ErrorState(
                  message: error.message,
                  code: error.code.wire,
                );
              },
            ),
          ],

          // El caso que borraba los datos: teléfono sin nada y una copia con
          // todo. Antes se subía el vacío y se perdía la copia; ahora se para
          // y se explica cuál es el movimiento correcto.
          if (state is BackupHeldEmpty) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            const InfoNote(
              tone: NmNoteTone.caution,
              text: 'No estamos subiendo nada porque este teléfono no tiene '
                  'registros. Si tu copia de la nube sí los tiene, traela con '
                  '"Restaurar desde la nube": subir esto la borraría.',
            ),
          ],

          const SizedBox(height: NmSpace.s6),
          NmButton.secondary(
            label: 'Respaldar ahora',
            block: true,
            icon: PhosphorIcons.cloudArrowUp(),
            loading: state is BackupUploading,
            onPressed: _backupNow,
          ),
          const SizedBox(height: NmSpace.s3),
          // Siempre habilitado. Antes se apagaba cuando el listado no
          // encontraba nada, y ese listado puede fallar por mil motivos que
          // no son "no hay copia": ahí el único camino de recuperación
          // desaparecía sin decir por qué. Si de verdad no hay nada, lo dice
          // al tocarlo, que es una respuesta y no un botón muerto.
          NmButton.secondary(
            label: 'Restaurar desde la nube',
            block: true,
            icon: PhosphorIcons.cloudArrowDown(),
            loading: _restoring,
            onPressed: _restore,
          ),

          const SizedBox(height: NmSpace.s6),
          Text(
            'La copia sube sola cada vez que registrás algo.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
        ],
      ),
    );
  }

  String _statusLabel(BackupState? state) => switch (state) {
    BackupUploading() => 'Subiendo…',
    BackupFailed() => 'Falló, se reintenta',
    BackupHeldEmpty() => 'En pausa',
    _ => 'Al día',
  };
}
