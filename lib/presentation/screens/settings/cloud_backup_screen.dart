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

  /// Cuántas filas hay de cada tabla del lado del servidor. Se pide a mano: son
  /// nueve consultas y no hacen falta para usar la pantalla.
  Map<String, int>? _remoteRows;
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Compara lo que hay en este dispositivo contra lo que hay en las tablas.
  ///
  /// Desde que las tablas son la fuente de verdad, esta es la pantalla donde se
  /// comprueba que lo sean de verdad. Que los números no coincidan **no es
  /// necesariamente un problema** —lo cargado sin conexión todavía no subió— y
  /// por eso se muestran los dos lados en vez de un cartelito de "todo bien":
  /// el que sabe si la diferencia tiene sentido es quien la mira.
  Future<void> _compare() async {
    final service = ref.read(relationalSyncProvider);
    if (service == null) return;
    setState(() => _comparing = true);
    final rows = await service.remoteCounts();
    if (!mounted) return;
    setState(() {
      _remoteRows = rows;
      _comparing = false;
    });
  }

  static String _tableLabel(String table) => switch (table) {
    'meals' => 'Comidas',
    'activities' => 'Actividades',
    'weight_logs' => 'Pesos',
    'body_measurements' => 'Medidas',
    'water_logs' => 'Agua',
    'sleep_logs' => 'Sueño',
    final other => other,
  };

  /// `remoteCounts` devuelve −1 cuando una tabla no se pudo consultar. Eso no
  /// es cero: decir "0" sería afirmar que el servidor no tiene nada, que es
  /// justo la conclusión peligrosa.
  String _remoteLabel(String table) {
    final value = _remoteRows?[table];
    if (value == null) return '—';
    return value < 0 ? 'no se pudo leer' : '$value';
  }

  /// Lo mismo que cuenta `remoteCounts`, pero de este lado.
  Map<String, int> _localRows() {
    final repo = ref.read(repositoryProvider);
    return <String, int>{
      'meals': repo.allMeals.length,
      'activities': repo.allActivities.length,
      'weight_logs': repo.weightLogs.length,
      'body_measurements': repo.allMeasurements.length,
      'water_logs': repo.waterLogs.length,
      'sleep_logs': repo.sleepLogs.length,
    };
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

  /// Elegir de qué copia restaurar.
  ///
  /// Con una sola copia esto sería un botón; con historial es una decisión, y
  /// la fecha es justamente el dato que permite tomarla ("lo perdí ayer a la
  /// tarde, traeme la de la mañana").
  Future<void> _pickAndRestore() async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) return;

    setState(() {
      _restoring = true;
      _error = null;
    });

    final List<CloudBackupInfo> copias;
    try {
      copias = await service.versions();
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = error;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _restoring = false);

    if (copias.isEmpty) {
      setState(
        () => _error = const AppError(
          code: ApiErrorCode.notFound,
          message: 'No hay ninguna copia guardada todavía.',
        ),
      );
      return;
    }

    // Con una sola copia no hay nada que elegir: se va derecho a confirmar.
    final elegida = copias.length == 1
        ? copias.first
        : await showNmSheet<CloudBackupInfo>(
            context: context,
            builder: (context) => NmSheet(
              title: 'Elegí qué copia traer',
              subtitle: 'De la más nueva a la más vieja',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final copia in copias)
                    ActionRow(
                      icon: copia.isLatest
                          ? PhosphorIcons.cloudCheck()
                          : PhosphorIcons.clockCounterClockwise(),
                      label:
                          '${longDay(copia.updatedAt)} '
                          '${timeOfDay(copia.updatedAt)}',
                      subtitle: copia.isLatest
                          ? 'La última · ${copia.sizeLabel}'
                          : copia.sizeLabel,
                      onTap: () => Navigator.of(context).pop(copia),
                    ),
                ],
              ),
            ),
          );

    if (elegida == null || !mounted) return;
    await _restore(elegida);
  }

  Future<void> _restore(CloudBackupInfo copia) async {
    final service = ref.read(cloudBackupProvider);
    if (service == null) return;

    // Restaurar pisa todo lo que hay en el teléfono. Si alguien cargó cosas
    // acá desde la última copia, las pierde: eso se pregunta, no se asume.
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Traer la copia del ${longDay(copia.updatedAt)}?',
        body:
            'Se reemplaza todo lo que tenés en este teléfono por esa copia '
            '(${copia.sizeLabel}). Lo que hayas registrado acá después de esa '
            'fecha se pierde.',
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
      final json = await service.restore(path: copia.path);
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

          // ── Este dispositivo contra las tablas ──────────────────────────
          if (ref.read(relationalSyncProvider) != null) ...<Widget>[
            const SizedBox(height: NmSpace.s8),
            const NmSectionHeader(title: 'Este dispositivo y el servidor'),
            NmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_remoteRows == null)
                    Text(
                      'Tus datos viven en el servidor y este dispositivo tiene '
                      'una copia con la que trabaja. Acá podés ver si los dos '
                      'lados dicen lo mismo.',
                      style: NmTextStyles.from(
                        NmType.bodySm,
                        color: nm.textMuted,
                      ),
                    )
                  else ...<Widget>[
                    for (final entry in _localRows().entries)
                      ValueRow(
                        label: _tableLabel(entry.key),
                        value: '${entry.value} · ${_remoteLabel(entry.key)}',
                        muted: _remoteRows![entry.key] == entry.value,
                      ),
                    const SizedBox(height: NmSpace.s3),
                    Text(
                      'Acá · servidor. Que no coincidan no es necesariamente un '
                      'problema: lo que cargaste sin conexión todavía no subió, '
                      'y sube solo con el próximo cambio.',
                      style: NmTextStyles.from(
                        NmType.caption,
                        color: nm.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: NmSpace.s4),
                  NmButton.secondary(
                    label: _remoteRows == null ? 'Comparar' : 'Volver a comparar',
                    block: true,
                    loading: _comparing,
                    onPressed: _compare,
                  ),
                ],
              ),
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
            onPressed: _pickAndRestore,
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
