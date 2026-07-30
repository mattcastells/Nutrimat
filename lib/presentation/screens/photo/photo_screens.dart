import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/ai_analysis.dart';
import '../../../domain/models/analysis_stage.dart';
import '../../../domain/models/meal.dart';
import '../../components/activity/badges.dart';
import '../../components/feedback/analysis_progress.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/food_widgets.dart';
import '../../components/food/photo_viewer.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../meal/meal_draft.dart';

const _uuid = Uuid();

/// El análisis en curso, para pasarlo de "Analizando" a "Revisar".
final analysisProvider = StateProvider<AiAnalysis?>((ref) => null);
final photoPathProvider = StateProvider<String?>((ref) => null);

/// Slot y día a los que va la comida cuando se entró desde una sección
/// concreta ("+" de Almuerzo, por ejemplo) y no desde el menú general.
///
/// Va por provider y no por query param porque el circuito son tres pantallas
/// encadenadas con `pushReplacement`: arrastrar los parámetros por las tres
/// solo abre lugares donde perderlos.
class PhotoTarget {
  const PhotoTarget({required this.slot, required this.date});

  final MealSlot slot;
  final DateTime date;
}

final photoTargetProvider = StateProvider<PhotoTarget?>((ref) => null);

/// S-18 · Cámara.
class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  ConsumerState<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _permissionDenied = false;
  bool _busy = false;

  Future<void> _capture(ImageSource source) async {
    if (source == ImageSource.camera) {
      final proceed = await _showRationale();
      if (!proceed || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      // Compresión a 1024 px del lado mayor, calidad 0,8 (F-05 paso 3).
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (file == null) return;
      ref.read(photoPathProvider.notifier).state = file.path;
      if (!mounted) return;
      context.pushReplacement(Routes.photoAnalyzing);
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _permissionDenied = true;
      });
    }
  }

  /// `dialog.permission_rationale`: se explica el permiso antes de pedirlo.
  Future<bool> _showRationale() async {
    final accepted = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: 'Vamos a usar la cámara',
        body: 'La foto se usa solo para estimar los ítems de la comida. '
            'Podés corregir todo antes de guardar y la imagen queda en tu '
            'teléfono.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Ahora no',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Continuar',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    final remaining = repo.quotaLimit - repo.quotaUsed;
    final quotaExhausted = remaining <= 0;

    return Scaffold(
      backgroundColor: nm.bg,
      appBar: const NmModalHeader(title: 'Sacar foto'),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(context.screenPadding),
          child: Column(
            children: <Widget>[
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: nm.surfaceRaised,
                    borderRadius: NmRadius.brLg,
                    border: Border.all(color: nm.divider),
                  ),
                  child: _permissionDenied
                      ? EmptyState(
                          icon: PhosphorIcons.camera(),
                          title: 'No pudimos abrir la cámara',
                          body: 'Podés darle permiso desde la configuración '
                              'del sistema o elegir una foto de la galería.',
                          primaryLabel: 'Elegir de la galería',
                          onPrimary: () => _capture(ImageSource.gallery),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              PhosphorIcons.aperture(),
                              size: 64,
                              color: nm.textMuted,
                            ),
                            const SizedBox(height: NmSpace.s4),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NmSpace.s6,
                              ),
                              child: Text(
                                'Encuadrá el plato completo desde arriba.',
                                textAlign: TextAlign.center,
                                style: NmTextStyles.from(
                                  NmType.bodySm,
                                  color: nm.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: NmSpace.s4),
              if (quotaExhausted)
                const InfoNote(
                  tone: NmNoteTone.caution,
                  text: 'Llegaste al límite diario de análisis por foto. '
                      'Podés registrar la comida a mano.',
                )
              else if (remaining <= 5)
                InfoNote(
                  text: 'Te quedan $remaining análisis por foto hoy.',
                ),
              const SizedBox(height: NmSpace.s4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NmButton.secondary(
                      label: 'Galería',
                      icon: PhosphorIcons.images(),
                      onPressed: quotaExhausted
                          ? null
                          : () => _capture(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: NmSpace.s3),
                  Expanded(
                    child: NmButton(
                      label: 'Sacar foto',
                      icon: PhosphorIcons.camera(),
                      loading: _busy,
                      onPressed: quotaExhausted
                          ? null
                          : () => _capture(ImageSource.camera),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// S-19 · Analizando. La única espera larga del producto (21-motion §4.4).
class PhotoAnalyzingScreen extends ConsumerStatefulWidget {
  const PhotoAnalyzingScreen({super.key});

  @override
  ConsumerState<PhotoAnalyzingScreen> createState() =>
      _PhotoAnalyzingScreenState();
}

class _PhotoAnalyzingScreenState extends ConsumerState<PhotoAnalyzingScreen>
    with SingleTickerProviderStateMixin {
  /// Qué se cuenta mientras el modelo trabaja, y desde qué segundo.
  ///
  /// Los cortes salen de medir el circuito real, no de tantear: la mediana de
  /// la llamada es 12,3 s y el percentil 90 está en 24,9 s (`AnalysisTiming`).
  ///
  /// El aviso de demora estaba en 15 s y **saltaba durante el funcionamiento
  /// normal**: a los 15 s la mitad de los análisis buenos siguen corriendo. Un
  /// cartel de alarma que aparece cuando todo va bien enseña a ignorarlo, así
  /// que se corrió al percentil 90 — recién ahí es cierto que se demora.
  ///
  /// Los tiempos son relativos al inicio del paso `analyzing`: preparar y
  /// subir tienen su propio texto, que sale de `AnalysisStage`.
  static const List<(int, String)> _phases = <(int, String)>[
    (0, 'Buscando alimentos en la foto…'),
    (2500, 'Reconociendo las preparaciones…'),
    (5000, 'Estimando el tamaño de las porciones…'),
    (8000, 'Calculando calorías y macros…'),
    (11000, 'Revisando que los números cierren…'),
    (14500, 'Terminando'),
    (24900, 'Está tardando más de lo normal'),
  ];

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  final List<Timer> _timers = <Timer>[];
  String _phase = _phases.first.$2;
  bool _cancelled = false;

  /// En qué paso real va el circuito, y desde cuándo. Los dos alimentan la
  /// barra: el paso da el tramo y el reloj estima dentro de él.
  AnalysisStage _stage = AnalysisStage.preparing;
  DateTime _stageStartedAt = DateTime.now();

  /// Qué falló. Sin esto, un análisis que se cae dejaba la pantalla girando
  /// para siempre en "Está tardando más de lo normal": `analyze` lanzaba, nadie
  /// lo agarraba, y no había ni error ni salida más que Cancelar. La espera
  /// eterna es la peor forma de contar un fallo, porque no se distingue de que
  /// esté por terminar.
  AppError? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _stage = AnalysisStage.preparing;
    _stageStartedAt = DateTime.now();

    // Un tick corto mantiene viva la estimación del tramo del modelo. No es
    // una animación: es el reloj real contra el que se dibuja la barra.
    _timers.add(
      Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _error == null) setState(() {});
      }),
    );
    unawaited(_run());
  }

  /// Arranca los mensajes recién cuando empieza el trabajo del modelo: contar
  /// "estimando porciones" mientras todavía se sube la foto sería inventar.
  void _startPhaseMessages() {
    for (final phase in _phases.skip(1)) {
      _timers.add(
        Timer(Duration(milliseconds: phase.$1), () {
          if (mounted && _error == null) setState(() => _phase = phase.$2);
        }),
      );
    }
  }

  void _onStage(AnalysisStage stage) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _stageStartedAt = DateTime.now();
      if (stage == AnalysisStage.analyzing) {
        _phase = _phases.first.$2;
        _startPhaseMessages();
      }
    });
  }

  Future<void> _run() async {
    final path = ref.read(photoPathProvider);
    if (!mounted || _cancelled) return;

    try {
      final analysis = await ref
          .read(repositoryProvider)
          .analyze(photoPath: path ?? '', onStage: _onStage);
      if (!mounted || _cancelled) return;

      ref.read(analysisProvider.notifier).state = analysis;
      context.pushReplacement(Routes.photoReview);
    } on AppError catch (error) {
      if (!mounted || _cancelled) return;
      setState(() => _error = error);
    } on Object catch (error) {
      if (!mounted || _cancelled) return;
      setState(
        () => _error = AppError(
          code: ApiErrorCode.server,
          message: 'No pudimos analizar la foto. Cargá la comida a mano; la '
              'foto queda adjunta.',
          requestId: error.toString(),
        ),
      );
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _phase = _phases.first.$2;
    });
    _start();
  }

  /// Salida sin IA: se arma la comida a mano con la foto ya sacada.
  void _manual() {
    final target = ref.read(photoTargetProvider);
    final DateTime date = target?.date ?? ref.read(selectedDateProvider);
    final MealSlot slot =
        target?.slot ?? MealSlot.forHour(DateTime.now().hour);
    ref
        .read(mealDraftProvider.notifier)
        .start(
          slot: slot,
          date: date,
          photoPath: ref.read(photoPathProvider),
        );
    context.pushReplacement(
      '${Routes.mealNew}?slot=${slot.wire}&date=${isoDate(date)}',
    );
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final path = ref.watch(photoPathProvider);
    final animate = !context.motion.reduced;

    return Scaffold(
      backgroundColor: nm.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(context.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: NmRadius.brLg,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (path != null)
                        Opacity(
                          opacity: 0.45,
                          child: Image.file(File(path), fit: BoxFit.cover),
                        )
                      else
                        ColoredBox(color: nm.surfaceRaised),
                      // Barrido vertical: sugiere lectura, no progreso falso.
                      if (animate)
                        AnimatedBuilder(
                          animation: _sweep,
                          builder: (context, _) => Align(
                            alignment: Alignment(0, _sweep.value * 2 - 1),
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    Colors.transparent,
                                    nm.accent,
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NmSpace.s6),

              if (_error != null) ...<Widget>[
                ErrorState(
                  message: _error!.message,
                  code: _error!.code.wire,
                  onRetry: _retry,
                ),
                const SizedBox(height: NmSpace.s5),
                NmButton(
                  label: 'Cargar la comida a mano',
                  block: true,
                  onPressed: _manual,
                ),
                const SizedBox(height: NmSpace.s2),
                NmButton.ghost(
                  label: 'Volver',
                  block: true,
                  onPressed: () {
                    _cancelled = true;
                    context.pop();
                  },
                ),
              ] else ...<Widget>[
                AnalysisProgress(
                  stage: _stage,
                  elapsedInStage: DateTime.now().difference(_stageStartedAt),
                ),
                const SizedBox(height: NmSpace.s5),
                Semantics(
                  liveRegion: true,
                  child: AnimatedSwitcher(
                    duration: context.motion.fade(NmMotion.fast),
                    child: Text(
                      _stage == AnalysisStage.analyzing
                          ? _phase
                          : _stage.label,
                      key: ValueKey<String>(
                        _stage == AnalysisStage.analyzing
                            ? _phase
                            : _stage.label,
                      ),
                      style: NmTextStyles.from(NmType.h3, color: nm.text),
                    ),
                  ),
                ),
                const SizedBox(height: NmSpace.s3),
                Text(
                  'El tiempo restante es una estimación: cuánto tarda el '
                  'modelo no lo decidimos nosotros.',
                  style: NmTextStyles.from(
                    NmType.caption,
                    color: nm.textMuted,
                  ),
                ),
                const SizedBox(height: NmSpace.s6),
                NmButton.secondary(
                  label: 'Cancelar',
                  block: true,
                  onPressed: () {
                    _cancelled = true;
                    context.pop();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// S-20 · Revisar análisis. ★
///
/// Ningún dato de IA se guarda sin pasar por el ojo de la persona.
class PhotoReviewScreen extends ConsumerStatefulWidget {
  const PhotoReviewScreen({super.key});

  @override
  ConsumerState<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends ConsumerState<PhotoReviewScreen> {
  bool _saving = false;

  /// Ya se guardó, así que al salir no hay que descartar el borrador.
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    // Después del primer frame, no en `initState` ni en `didChangeDependencies`:
    // Riverpod prohíbe modificar un provider durante un ciclo de vida del
    // widget y tira *"Tried to modify a provider while the widget tree was
    // building"*. Es el mismo motivo por el que `MealFormScreen` abre su
    // borrador así.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startDraft();
    });
  }

  /// El borrador se abre **al entrar**, no al guardar.
  ///
  /// Antes los ítems vivían en una lista de esta pantalla y el borrador se
  /// armaba recién en `_save`. Con eso, "Agregar un ítem que falta" mandaba al
  /// buscador, el buscador agregaba al borrador… que todavía no existía:
  /// `addItem` sobre `null` no hace nada y no avisa. El alimento elegido se
  /// perdía en silencio y la pantalla volvía igual que antes. Siendo el
  /// borrador la única lista, ese camino funciona sin nada especial.
  void _startDraft() {
    final analysis = ref.read(analysisProvider);
    if (analysis == null) return;
    final target = ref.read(photoTargetProvider);
    final photoPath = ref.read(photoPathProvider);

    ref.read(mealDraftProvider.notifier).start(
      // Si se entró por el "+" de una sección, ese slot manda sobre la hora.
      slot: target?.slot ?? MealSlot.forHour(DateTime.now().hour),
      date: target?.date ?? ref.read(selectedDateProvider),
      // Sin foto, la estimación salió de una descripción escrita: se guarda
      // como tal para que el origen del dato no diga algo que no pasó.
      source: photoPath == null ? MealSource.aiText : MealSource.aiPhoto,
      photoPath: photoPath,
      aiAnalysisId: analysis.id,
      items: <MealItem>[
        for (var i = 0; i < analysis.items.length; i++)
          _toMealItem(analysis.items[i], i),
      ],
    );
  }

  /// Un ítem estimado por la IA se distingue de uno elegido del catálogo por
  /// tener [MealItem.aiConfidence]. No es un detalle: el badge de confianza
  /// dice cuánta duda tiene el modelo, y ponerle uno a un alimento del catálogo
  /// sería presentar un dato verificado como si fuera una estimación.
  static MealItem _toMealItem(AiAnalysisItem item, int position) => MealItem(
    id: _uuid.v4(),
    name: item.name,
    quantity: item.quantity,
    unit: item.unit,
    kcal: item.kcal,
    proteinG: item.proteinG,
    carbsG: item.carbsG,
    fatG: item.fatG,
    aiConfidence: item.confidence,
    position: position,
  );

  /// Se va sin guardar: el borrador no puede quedar dando vueltas, porque
  /// "Nueva comida" retoma cualquier borrador abierto y aparecería con los
  /// ítems de un análisis que se descartó.
  void _discardIfUnsaved() {
    if (_committed) return;
    ref.read(mealDraftProvider.notifier).clear();
    ref.read(analysisProvider.notifier).state = null;
    ref.read(photoTargetProvider.notifier).state = null;
  }

  Future<void> _save() async {
    final draft = ref.read(mealDraftProvider);
    if (draft == null || draft.isEmpty) return;

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final date = draft.date;

    await repo.saveMeal(draft.toMeal(syncStatus: SyncStatus.synced));
    _committed = true;
    ref.read(mealDraftProvider.notifier).clear();
    ref.read(analysisProvider.notifier).state = null;
    ref.read(photoTargetProvider.notifier).state = null;
    // Inicio queda parado en el día donde acaba de caer la comida: guardar
    // algo y no verlo en ningún lado se lee como que no se guardó.
    ref.read(selectedDateProvider.notifier).set(date);

    if (!mounted) return;
    setState(() => _saving = false);
    context.go(Routes.home);
    NmSnackbar.show(
      context,
      draft.source == MealSource.aiText
          ? 'Comida guardada desde la descripción'
          : 'Comida guardada desde la foto',
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final analysis = ref.watch(analysisProvider);
    final draft = ref.watch(mealDraftProvider);
    final path = ref.watch(photoPathProvider);
    final controller = ref.read(mealDraftProvider.notifier);

    if (analysis == null) {
      return NmScreen(
        title: 'Revisar análisis',
        child: ErrorState(
          message: 'No pudimos leer la estimación. Podés cargar la comida a '
              'mano.',
          onRetry: () => context.go(Routes.mealNew),
          retryLabel: 'Cargar a mano',
        ),
      );
    }

    // El borrador se abre después del primer frame, así que este es ese frame.
    if (draft == null) {
      return Scaffold(
        backgroundColor: nm.bg,
        appBar: const NmModalHeader(title: 'Revisar análisis'),
        body: const Center(child: NmSpinner()),
      );
    }

    final items = draft.items;
    final lowConfidence = items.any(
      (i) => i.aiConfidence != null && i.aiConfidence! < 0.5,
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _discardIfUnsaved();
      },
      child: Scaffold(
        backgroundColor: nm.bg,
        appBar: const NmModalHeader(title: 'Revisar análisis'),
        body: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(context.screenPadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: NmLayout.contentMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (path != null)
                            ClipRRect(
                              borderRadius: NmRadius.brMd,
                              child: ZoomablePhoto(
                                file: File(path),
                                child: Image.file(
                                  File(path),
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          const SizedBox(height: NmSpace.s4),
                          AiEstimateBanner(
                            confidenceAvg: analysis.confidenceAvg,
                          ),
                          const SizedBox(height: NmSpace.s6),
                          Text(
                            'Momento del día',
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.textMuted,
                            ),
                          ),
                          const SizedBox(height: NmSpace.s2),
                          Wrap(
                            spacing: NmSpace.s2,
                            children: <Widget>[
                              for (final slot in MealSlot.values)
                                NmChip(
                                  label: slot.label,
                                  selected: slot == draft.slot,
                                  semanticsInRadioGroup: true,
                                  onTap: () => controller.setSlot(slot),
                                ),
                            ],
                          ),
                          const SizedBox(height: NmSpace.s6),
                          const NmSectionHeader(title: 'Ítems detectados'),
                          for (var i = 0; i < items.length; i++)
                            StaggeredItem(
                              index: i,
                              child: _AiItemRow(
                                // La clave es el id del ítem y no su posición:
                                // sin esto, borrar el primero le pasa el estado
                                // (y el controlador de texto) del borrado al que
                                // queda en su lugar.
                                key: ValueKey<String>(items[i].id),
                                item: items[i],
                                onChanged: (updated) =>
                                    controller.replaceItem(i, updated),
                                onRemove: () =>
                                    controller.removeItem(items[i].id),
                              ),
                            ),
                          const SizedBox(height: NmSpace.s4),
                          NmButton.secondary(
                            label: 'Agregar un ítem que falta',
                            block: true,
                            icon: PhosphorIcons.plus(),
                            onPressed: () => context.push(
                              '${Routes.foodSearch}?target=ai_item',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              MealTotalsBar(
                kcal: draft.totalKcal,
                proteinG: draft.proteinG,
                carbsG: draft.carbsG,
                fatG: draft.fatG,
                child: NmButton(
                  label: lowConfidence ? 'Guardar igual' : 'Guardar comida',
                  block: true,
                  loading: _saving,
                  onPressed: items.isEmpty ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila editable del análisis.
///
/// Tiene que ser `StatefulWidget` y el controlador vivir acá adentro. Antes se
/// creaba un `TextEditingController` nuevo **en cada build**, y como cada tecla
/// dispara un `setState` del padre, pasaba esto: se rehacía el campo, el texto
/// se volvía a calcular desde la cantidad ya modificada y el cursor saltaba al
/// principio. Escribir "150" daba cualquier cosa menos 150, y encima cada
/// controlador quedaba sin liberar.
class _AiItemRow extends StatefulWidget {
  const _AiItemRow({
    required this.item,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final MealItem item;
  final ValueChanged<MealItem> onChanged;
  final VoidCallback onRemove;

  @override
  State<_AiItemRow> createState() => _AiItemRowState();
}

class _AiItemRowState extends State<_AiItemRow> {
  late final TextEditingController _quantity = TextEditingController(
    text: _format(widget.item.quantity),
  );

  /// La cantidad con la que se calcularon los macros que están en pantalla.
  /// Se guarda al empezar a editar para que reescalar sea siempre contra el
  /// original y no contra el resultado del tecleo anterior.
  late final double _base = widget.item.quantity;
  late final MealItem _baseItem = widget.item;

  static String _format(double q) => q == q.roundToDouble()
      ? q.toInt().toString()
      : q.toString().replaceAll('.', ',');

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    // Campo vacío o a medio escribir ("1," mientras se tipea "1,5"): no se
    // toca nada todavía. Antes cualquier tecla intermedia reescalaba los
    // macros y el número quedaba arrastrado.
    if (parsed == null || parsed <= 0) return;
    if (_base <= 0) return;

    final ratio = parsed / _base;
    widget.onChanged(
      _baseItem.copyWith(
        quantity: parsed,
        kcal: (_baseItem.kcal * ratio).round(),
        proteinG: _baseItem.proteinG * ratio,
        carbsG: _baseItem.carbsG * ratio,
        fatG: _baseItem.fatG * ratio,
        // Insumo para `ai_result_corrected` (F-06 paso 6). Se marca el ítem que
        // se corrigió y no todos, como antes: un solo cambio ensuciaba la
        // medición al dejar la comida entera marcada como corregida.
        wasAiCorrected: _baseItem.aiConfidence != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final item = widget.item;
    final confidence = item.aiConfidence;
    final low = confidence != null && confidence < 0.5;

    return Padding(
      padding: const EdgeInsets.only(bottom: NmSpace.s3),
      child: NmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.name,
                    style: NmTextStyles.from(NmType.body, color: nm.text),
                  ),
                ),
                // El badge de confianza es del modelo. Un alimento que la
                // persona eligió del catálogo no tiene confianza que mostrar
                // —tiene una tabla nutricional detrás— y ponerle una sería
                // presentar un dato verificado como si fuera una estimación.
                if (confidence != null)
                  ConfidenceBadge(value: confidence)
                else
                  const NmTag(
                    label: 'Del catálogo',
                    variant: NmTagVariant.outline,
                  ),
                NmIconButton(
                  icon: PhosphorIcons.trash(),
                  onPressed: widget.onRemove,
                  tooltip: 'Quitar ${item.name}',
                  size: NmIconSize.md,
                ),
              ],
            ),
            const SizedBox(height: NmSpace.s3),
            Row(
              children: <Widget>[
                Expanded(
                  child: NmTextField(
                    label: 'Cantidad',
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    error: low ? 'Revisá esta cantidad' : null,
                    onChanged: _onChanged,
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Unidad',
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                      const SizedBox(height: NmSpace.s2),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NmSpace.s3,
                        ),
                        child: Text(
                          item.unit,
                          style: NmTextStyles.from(
                            NmType.body,
                            color: nm.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                Text(
                  '${item.kcal} kcal',
                  style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
