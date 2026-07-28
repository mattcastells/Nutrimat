import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/icons.dart';
import '../../../domain/enums/enums.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../weight/weight_sheet.dart';

/// S-08 · Menú Agregar y S-09 · Menú Ejercicio.
///
/// Un bottom sheet nunca abre otro en el mismo nivel: `sheet.add` **reemplaza**
/// su contenido por `sheet.activity_add` con animación lateral, para que
/// "Atrás" vuelva al menú anterior y no cierre todo (IA §3).
Future<void> showAddSheet(BuildContext context, {bool activityFirst = false}) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => _AddSheet(activityFirst: activityFirst),
    );

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({required this.activityFirst});

  final bool activityFirst;

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  late bool _activityPane = widget.activityFirst;

  void _go(String location) {
    Navigator.of(context).pop();
    context.push(location);
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    return AnimatedSwitcher(
      duration: motion.move(NmMotion.base),
      switchInCurve: NmMotion.ease,
      switchOutCurve: NmMotion.easeOut,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<bool>(_activityPane);
        final offset = Tween<Offset>(
          begin: Offset(incoming ? 1 : -1, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: motion.reduced
              ? child
              : SlideTransition(position: offset, child: child),
        );
      },
      child: _activityPane
          ? _ActivityPane(
              key: const ValueKey<bool>(true),
              onBack: () => setState(() => _activityPane = false),
              onGo: _go,
            )
          : _MainPane(
              key: const ValueKey<bool>(false),
              onActivity: () => setState(() => _activityPane = true),
              onGo: _go,
            ),
    );
  }
}

class _MainPane extends ConsumerWidget {
  const _MainPane({required this.onActivity, required this.onGo, super.key});

  final VoidCallback onActivity;
  final void Function(String location) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider);
    final date = ref.watch(selectedDateProvider);
    final slot = MealSlot.forHour(DateTime.now().hour);

    return NmSheet(
      title: 'Agregar',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ActionRow(
            icon: PhosphorIcons.forkKnife(),
            label: 'Agregar comida',
            subtitle: 'Buscar alimentos y armar la comida',
            onTap: () => onGo(
              '${Routes.mealNew}?slot=${slot.wire}'
              '&date=${date.toIso8601String().substring(0, 10)}',
            ),
          ),
          ActionRow(
            icon: PhosphorIcons.camera(),
            label: 'Sacar foto de una comida',
            subtitle: 'La IA estima los ítems y vos los revisás',
            enabled: FeatureFlags.aiPhotoAnalysis,
            disabledNote: 'El análisis con IA todavía no está conectado',
            onTap: () => onGo(Routes.photoCapture),
          ),
          ActionRow(
            icon: PhosphorIcons.barcode(),
            label: 'Escanear alimento',
            subtitle: 'Buscar por código de barras',
            enabled: !offline,
            disabledNote: 'Necesita conexión',
            onTap: () => onGo(Routes.foodScan),
          ),
          ActionRow(
            icon: PhosphorIcons.personSimpleRun(),
            label: 'Agregar ejercicio',
            subtitle: 'Nueve formas de registrarlo',
            onTap: onActivity,
            trailing: Icon(PhosphorIcons.caretRight(), size: NmIconSize.md),
          ),
          ActionRow(
            icon: PhosphorIcons.scales(),
            label: 'Registrar peso',
            subtitle: 'Uno por día: si ya cargaste, se actualiza',
            onTap: () {
              Navigator.of(context).pop();
              showWeightSheet(context);
            },
          ),
          ActionRow(
            icon: PhosphorIcons.ruler(),
            label: 'Registrar medida corporal',
            subtitle: 'Cintura, cadera, pecho y más',
            onTap: () {
              Navigator.of(context).pop();
              showMeasurementSheet(context);
            },
          ),
        ],
      ),
    );
  }
}

class _ActivityPane extends ConsumerWidget {
  const _ActivityPane({required this.onBack, required this.onGo, super.key});

  final VoidCallback onBack;
  final void Function(String location) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final recent = ref.watch(recentActivitiesProvider);
    final favorites = ref.watch(favoriteActivitiesProvider);
    final integration = ref.watch(integrationProvider);
    final repo = ref.watch(repositoryProvider);

    Widget chips(List<String> labels) => Padding(
      padding: const EdgeInsets.only(
        left: NmSpace.s3,
        bottom: NmSpace.s3,
      ),
      child: Wrap(
        spacing: NmSpace.s2,
        children: <Widget>[
          for (final label in labels.take(3))
            NmTag(label: label, variant: NmTagVariant.outline),
        ],
      ),
    );

    return NmSheet(
      title: 'Agregar ejercicio',
      onBack: onBack,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ActionRow(
            icon: PhosphorIcons.magnifyingGlass(),
            label: 'Buscar actividad',
            subtitle: 'Todo el catálogo, por categoría',
            onTap: () => onGo(Routes.activitySearch),
          ),
          if (recent.isNotEmpty) ...<Widget>[
            ActionRow(
              icon: PhosphorIcons.clockCounterClockwise(),
              label: 'Actividad reciente',
              subtitle: 'Repetir algo de los últimos días',
              onTap: () => onGo(
                '${Routes.activityNew}?activityTypeId='
                '${recent.first.activityTypeId}',
              ),
            ),
            chips(recent.map((a) => a.displayName).toList()),
          ],
          if (favorites.isNotEmpty) ...<Widget>[
            ActionRow(
              icon: PhosphorIcons.star(),
              label: 'Actividad favorita',
              onTap: () => onGo(
                '${Routes.activityNew}?activityTypeId='
                '${favorites.first.activityTypeId}',
              ),
            ),
            chips(favorites.map((a) => a.displayName).toList()),
          ],
          ActionRow(
            icon: PhosphorIcons.plusCircle(),
            label: 'Crear actividad manual',
            subtitle: 'Definir tu propio tipo y su MET',
            onTap: () => onGo('${Routes.activityNew}?mode=custom'),
          ),
          ActionRow(
            icon: PhosphorIcons.arrowsClockwise(),
            label: 'Importar desde un dispositivo',
            subtitle: integration.isConnected
                ? 'Health Connect · conectada'
                : 'Health Connect · sin conectar',
            enabled:
                repo.isPlatformSupported && FeatureFlags.healthConnectSync,
            disabledNote: repo.isPlatformSupported
                ? 'Health Connect todavía no está conectado'
                : 'Health Connect solo está disponible en Android',
            onTap: () => onGo(Routes.integrations),
          ),
          ActionRow(
            icon: NmIcons.activity('Barbell'),
            label: 'Entrenamiento de fuerza',
            subtitle: 'Nombre, duración e intensidad',
            onTap: () => onGo('${Routes.activityNew}?mode=strength'),
          ),
          ActionRow(
            icon: NmIcons.activity('PersonSimpleWalk'),
            label: 'Caminata o carrera',
            subtitle: 'Con distancia y pasos',
            onTap: () => onGo('${Routes.activityNew}?mode=walk_run'),
          ),
          ActionRow(
            icon: PhosphorIcons.timer(),
            label: 'Actividad por duración',
            onTap: () => onGo('${Routes.activityNew}?mode=duration'),
          ),
          ActionRow(
            icon: PhosphorIcons.path(),
            label: 'Actividad por distancia',
            onTap: () => onGo('${Routes.activityNew}?mode=distance'),
          ),
          const SizedBox(height: NmSpace.s3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NmSpace.s3),
            child: Text(
              'Las calorías de ejercicio son una estimación.',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
