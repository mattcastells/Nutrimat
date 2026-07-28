import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/bmr.dart';
import '../../../domain/calculations/calorie_target.dart';
import '../../../domain/enums/enums.dart';
import '../../components/activity/activity_inputs.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import 'onboarding_controller.dart';

/// S-05 · Onboarding de 6 pasos.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({required this.step, super.key});

  final OnboardingStep step;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final FocusNode _titleFocus = FocusNode();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // El foco se mueve al título de cada paso al avanzar (accesibilidad S-05).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _titleFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final draft = ref.read(onboardingProvider);
    final step = widget.step;

    if (step == OnboardingStep.goal && draft.goalType == null) {
      setState(() => _error = 'Elegí un objetivo para seguir.');
      return;
    }
    if (step == OnboardingStep.body) {
      final validation = _validateBody(draft.birthDate, draft.heightCm, draft.weightKg);
      if (validation != null) {
        setState(() => _error = validation);
        return;
      }
    }
    if (step == OnboardingStep.target &&
        draft.targetMethod == TargetMethod.manual) {
      final manual = draft.manualTarget;
      if (manual == null || manual < 800 || manual > 6000) {
        setState(() => _error = 'Ingresá un objetivo entre 800 y 6000 kcal.');
        return;
      }
      final minimum = CalorieTargetRules.minimumFor(
        draft.biologicalSex ?? BiologicalSex.unspecified,
      );
      if (manual < minimum) {
        final confirmed = await _confirmLowTarget(minimum);
        if (!confirmed || !mounted) return;
      }
    }

    setState(() => _error = null);

    if (step == OnboardingStep.summary) {
      setState(() => _submitting = true);
      await ref.read(repositoryProvider).completeOnboarding(draft);
      if (!mounted) return;
      setState(() => _submitting = false);
      context.go(Routes.home);
      return;
    }

    context.go(Routes.onboardingStep(step.next!.slug));
  }

  String? _validateBody(DateTime? birth, double? height, double? weight) {
    if (birth == null) return 'Necesitamos tu fecha de nacimiento.';
    final age = ageFromBirthDate(birth);
    if (age < 13) return 'Necesitás tener al menos 13 años para usar Nutrimat.';
    if (age > 100) return 'Revisá la fecha de nacimiento.';
    if (height == null || height < 90 || height > 250) {
      return 'Ingresá una altura entre 90 y 250 cm.';
    }
    if (weight == null || weight < 25 || weight > 400) {
      return 'Ingresá un peso entre 25 y 400 kg.';
    }
    return null;
  }

  Future<bool> _confirmLowTarget(int minimum) async {
    final result = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: 'Es un objetivo muy bajo',
        body:
            'Por debajo de $minimum kcal por día cuesta cubrir los nutrientes '
            'básicos. Podés seguir, pero conviene revisarlo con un '
            'profesional.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Volver',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Usar ese valor igual',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _back() {
    final previous = widget.step.previous;
    if (previous == null) {
      _confirmExit();
      return;
    }
    context.go(Routes.onboardingStep(previous.slug));
  }

  Future<void> _confirmExit() async {
    final leave = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Salir del onboarding?',
        body: 'Vas a perder lo que cargaste.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Seguir acá',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Salir',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) context.go(Routes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final step = widget.step;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: NmScreen(
        bottom: Container(
          padding: EdgeInsets.fromLTRB(
            context.screenPadding,
            NmSpace.s3,
            context.screenPadding,
            NmSpace.s4 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: nm.bg,
            border: Border(top: BorderSide(color: nm.divider)),
          ),
          child: Row(
            children: <Widget>[
              NmButton.ghost(label: 'Atrás', onPressed: _back),
              const Spacer(),
              if (_canSkip(step))
                NmButton.ghost(
                  label: 'Después',
                  onPressed: () =>
                      context.go(Routes.onboardingStep(step.next!.slug)),
                ),
              const SizedBox(width: NmSpace.s2),
              NmButton(
                label: step == OnboardingStep.summary ? 'Empezar' : 'Continuar',
                loading: _submitting,
                onPressed: _next,
              ),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: NmSpace.s8),
            StepIndicator(current: step.number, total: 6),
            const SizedBox(height: NmSpace.s6),
            Focus(
              focusNode: _titleFocus,
              child: Semantics(
                header: true,
                child: Text(
                  step.title,
                  style: NmTextStyles.from(NmType.h1, color: nm.text),
                ),
              ),
            ),
            const SizedBox(height: NmSpace.s6),
            if (_error != null) ...<Widget>[
              InfoNote(text: _error!, tone: NmNoteTone.caution),
              const SizedBox(height: NmSpace.s4),
            ],
            switch (step) {
              OnboardingStep.goal => const _GoalStep(),
              OnboardingStep.body => const _BodyStep(),
              OnboardingStep.activityLevel => const _ActivityLevelStep(),
              OnboardingStep.target => const _TargetStep(),
              OnboardingStep.exerciseCredit => const _CreditStep(),
              OnboardingStep.summary => const _SummaryStep(),
            },
            const SizedBox(height: NmSpace.s10),
            if (step == OnboardingStep.body)
              Text(
                'El sexo biológico se usa solo para la fórmula de metabolismo '
                'basal.',
                style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  /// `body` no se puede omitir: sin él no hay BMR (IA §5).
  bool _canSkip(OnboardingStep step) =>
      step != OnboardingStep.body && step != OnboardingStep.summary;
}

class _GoalStep extends ConsumerWidget {
  const _GoalStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingProvider);
    return Column(
      children: <Widget>[
        for (final type in GoalType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: NmSpace.s3),
            child: NmRadioRow<GoalType>(
              title: type.label,
              subtitle: switch (type) {
                GoalType.lose => 'Un déficit moderado, sin apuro',
                GoalType.maintain => 'Sostener el peso actual',
                GoalType.gain => 'Un superávit conservador',
              },
              value: type,
              groupValue: draft.goalType ?? GoalType.maintain,
              onChanged: (v) =>
                  ref.read(onboardingProvider.notifier).setGoalType(v),
            ),
          ),
      ],
    );
  }
}

class _BodyStep extends ConsumerStatefulWidget {
  const _BodyStep();

  @override
  ConsumerState<_BodyStep> createState() => _BodyStepState();
}

class _BodyStepState extends ConsumerState<_BodyStep> {
  late final TextEditingController _height = TextEditingController(
    text: ref.read(onboardingProvider).heightCm?.round().toString() ?? '',
  );
  late final TextEditingController _weight = TextEditingController(
    text: ref.read(onboardingProvider).weightKg?.toString() ?? '',
  );

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Sexo biológico',
          style: NmTextStyles.from(NmType.caption, color: context.nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s2),
        NmSegmentedControl<BiologicalSex>(
          options: BiologicalSex.values
              .map((s) => (s, s == BiologicalSex.unspecified ? 'Otro' : s.label))
              .toList(),
          value: draft.biologicalSex ?? BiologicalSex.unspecified,
          onChanged: (v) => controller.setBody(sex: v),
        ),
        const SizedBox(height: NmSpace.s6),
        NmDateField(
          label: 'Fecha de nacimiento',
          value: draft.birthDate,
          helper: draft.birthDate == null
              ? null
              : '${ageFromBirthDate(draft.birthDate!)} años',
          lastDate: DateTime.now(),
          onChanged: (v) => controller.setBody(birthDate: v),
        ),
        const SizedBox(height: NmSpace.s6),
        NmNumberField(
          label: 'Altura',
          controller: _height,
          suffix: 'cm',
          onChanged: (raw) =>
              controller.setBody(heightCm: double.tryParse(raw)),
        ),
        const SizedBox(height: NmSpace.s6),
        NmNumberField(
          label: 'Peso actual',
          controller: _weight,
          suffix: 'kg',
          decimals: 1,
          onChanged: (raw) => controller.setBody(
            weightKg: double.tryParse(raw.replaceAll(',', '.')),
          ),
        ),
      ],
    );
  }
}

class _ActivityLevelStep extends ConsumerWidget {
  const _ActivityLevelStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingProvider);
    return Column(
      children: <Widget>[
        for (final level in ActivityLevel.values)
          Padding(
            padding: const EdgeInsets.only(bottom: NmSpace.s3),
            child: NmRadioRow<ActivityLevel>(
              title: level.label,
              subtitle: level.description,
              value: level,
              groupValue: draft.activityLevel ?? ActivityLevel.moderate,
              onChanged: (v) =>
                  ref.read(onboardingProvider.notifier).setActivityLevel(v),
            ),
          ),
        const SizedBox(height: NmSpace.s3),
        const InfoNote(
          text: 'Este nivel ya incluye tu actividad habitual. Por eso el '
              'ejercicio que registres no se suma automáticamente al '
              'presupuesto del día.',
        ),
      ],
    );
  }
}

class _TargetStep extends ConsumerStatefulWidget {
  const _TargetStep();

  @override
  ConsumerState<_TargetStep> createState() => _TargetStepState();
}

class _TargetStepState extends ConsumerState<_TargetStep> {
  late final TextEditingController _manual = TextEditingController(
    text: ref.read(onboardingProvider).manualTarget?.toString() ?? '',
  );

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final draft = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);
    final preview = controller.preview();
    final isManual = draft.targetMethod == TargetMethod.manual;
    final goalType = draft.goalType ?? GoalType.maintain;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (preview.bmr != null) ...<Widget>[
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Metabolismo basal (BMR)',
                  value: Fmt.kcal(preview.bmr!),
                  muted: true,
                ),
                ValueRow(
                  label: 'Gasto diario (TDEE)',
                  caption: (draft.activityLevel ?? ActivityLevel.moderate).label,
                  value: Fmt.kcal(preview.tdee!),
                  muted: true,
                ),
                const NmDivider(),
                ValueRow(
                  label: 'Tu objetivo',
                  value: Fmt.kcal(preview.target),
                  emphasis: true,
                ),
              ],
            ),
          ),
          if (preview.clamped) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            InfoNote(
              tone: NmNoteTone.caution,
              text: 'Ajustamos tu objetivo al mínimo saludable de '
                  '${preview.minimum} kcal.',
            ),
          ],
          const SizedBox(height: NmSpace.s6),
        ] else
          const InfoNote(
            tone: NmNoteTone.caution,
            text: 'Sin tus datos corporales no podemos calcular el objetivo: '
                'ingresalo a mano.',
          ),
        if (goalType != GoalType.maintain) ...<Widget>[
          Text(
            'Ritmo',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final rate in const <double>[0.25, 0.5, 0.75, 1.0])
                NmChip(
                  label: '${Fmt.decimal2(rate)} kg / semana',
                  selected: draft.rateKgPerWeek == rate,
                  onTap: () => controller.setRate(rate),
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s3),
          const InfoNote(
            text: 'El máximo es 1 kg por semana. No hay una opción más '
                'agresiva, a propósito.',
          ),
          const SizedBox(height: NmSpace.s6),
        ],
        NmSwitchRow(
          title: 'Ingresar el objetivo a mano',
          value: isManual,
          onChanged: (v) => controller.setTargetMethod(
            v ? TargetMethod.manual : TargetMethod.calculated,
          ),
        ),
        if (isManual) ...<Widget>[
          const SizedBox(height: NmSpace.s3),
          NmNumberField(
            label: 'Objetivo calórico',
            controller: _manual,
            suffix: 'kcal',
            helper: 'Entre 800 y 6000 kcal.',
            onChanged: (raw) => controller.setManualTarget(int.tryParse(raw)),
          ),
        ],
      ],
    );
  }
}

class _CreditStep extends ConsumerWidget {
  const _CreditStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingProvider);
    final controller = ref.read(onboardingProvider.notifier);

    return ExerciseCreditSelector(
      value: draft.exerciseCreditPercentage,
      enabled: true,
      previewEstimatedCalories: 240,
      onChanged: controller.setCredit,
      onToggleEnabled: (enabled) {
        if (!enabled) controller.setCredit(0);
      },
    );
  }
}

class _SummaryStep extends ConsumerWidget {
  const _SummaryStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingProvider);
    final preview = ref.read(onboardingProvider.notifier).preview();
    final credit = draft.exerciseCreditPercentage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NmCard(
          child: Column(
            children: <Widget>[
              ValueRow(
                label: 'Objetivo diario',
                value: Fmt.kcal(preview.target),
                emphasis: true,
              ),
              const NmDivider(),
              ValueRow(
                label: 'Proteínas',
                value: Fmt.grams(preview.macros.proteinG),
              ),
              ValueRow(
                label: 'Carbohidratos',
                value: Fmt.grams(preview.macros.carbsG),
              ),
              ValueRow(label: 'Grasas', value: Fmt.grams(preview.macros.fatG)),
              const NmDivider(),
              ValueRow(
                label: 'El ejercicio suma',
                value: credit == 0 ? 'No suma' : '$credit %',
              ),
            ],
          ),
        ),
        const SizedBox(height: NmSpace.s4),
        const InfoNote(
          text: 'Podés cambiar todo esto cuando quieras desde Perfil. Los '
              'objetivos viejos quedan guardados: el historial no se '
              'reescribe.',
        ),
      ],
    );
  }
}
