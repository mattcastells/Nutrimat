import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/bmr.dart';
import '../../../domain/calculations/calorie_target.dart';
import '../../../domain/calculations/goal_presets.dart';
import '../../../domain/calculations/tdee.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/goal_planner.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../profile/goal_picker_screen.dart';

/// S-05 · Alta guiada. Los datos con los que la app calcula, antes de Inicio.
///
/// **Es obligatoria y no tiene "Ahora no".** Antes de esto, crear la cuenta
/// dejaba a la persona en Inicio con un objetivo de 2.000 kcal que no salía de
/// ningún lado: sin fecha de nacimiento, altura ni peso no hay Mifflin-St Jeor,
/// así que el número grande de la pantalla principal era un valor de referencia
/// con forma de cuenta. El producto entero se apoya en que ningún número sea
/// inventado (RN-03); el primero que ve alguien no puede ser la excepción.
///
/// Los cuatro pasos son los insumos de las cuatro fórmulas, en el orden en que
/// se encadenan: sexo y edad y altura y peso → BMR, nivel de actividad → TDEE,
/// objetivo → calorías y macros. Cada paso se guarda al pasar al siguiente, así
/// que cerrar la app a mitad de camino no obliga a empezar de nuevo: al volver
/// se retoma con lo que ya estaba cargado.
///
/// Quién queda adentro lo decide `NutrimatRepositories.needsOnboarding`, y lo
/// hace cumplir el `redirect` del router: no alcanza con mandar acá desde el
/// alta, porque a Inicio también se llega desde el splash de un arranque
/// posterior.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const int totalSteps = 4;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;

  late BiologicalSex _sex;
  late DateTime? _birthDate;
  late ActivityLevel _level;
  GoalType? _goalType;

  late final TextEditingController _height;
  late final TextEditingController _weight;

  String? _birthError;
  String? _heightError;
  String? _weightError;

  @override
  void initState() {
    super.initState();
    // Se arranca con lo que ya haya. Quien vuelve porque le falta un dato no
    // tiene por qué volver a escribir los otros tres, y quien entra desde otro
    // teléfono se encuentra lo que trajeron las tablas.
    final profile = ref.read(profileProvider);
    _sex = profile.biologicalSex;
    _birthDate = profile.birthDate;
    _level = profile.activityLevel;
    _goalType = ref.read(currentGoalProvider)?.goalType;
    _height = TextEditingController(
      text: profile.heightCm?.round().toString() ?? '',
    );
    _weight = TextEditingController(
      text: ref.read(currentWeightProvider)?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  // ── Validación ──────────────────────────────────────────────────────────

  double? get _heightCm {
    final parsed = double.tryParse(_height.text.replaceAll(',', '.'));
    if (parsed == null || parsed < 90 || parsed > 250) return null;
    return parsed;
  }

  double? get _weightKg {
    final parsed = double.tryParse(_weight.text.replaceAll(',', '.'));
    if (parsed == null || parsed < 25 || parsed > 400) return null;
    return parsed;
  }

  bool get _canContinue => switch (_step) {
    0 => _birthDate != null && ageFromBirthDate(_birthDate!) >= 13,
    1 => _heightCm != null && _weightKg != null,
    2 => true,
    _ => _goalType != null,
  };

  // ── Guardado ────────────────────────────────────────────────────────────

  /// Guarda el paso que se está dejando atrás y avanza.
  ///
  /// Se escribe paso a paso y no todo al final a propósito: cada uno de estos
  /// datos vale por sí solo —la altura sirve aunque nunca se elija un objetivo—
  /// y perderlos porque la app se cerró en el paso siguiente sería obligar a
  /// repetir un formulario que ya se completó.
  Future<void> _next() async {
    if (!_canContinue || _saving) return;
    final repo = ref.read(repositoryProvider);
    setState(() => _saving = true);

    switch (_step) {
      case 0:
        await repo.updateProfile(
          ref.read(profileProvider).copyWith(
            biologicalSex: _sex,
            birthDate: _birthDate,
          ),
        );
      case 1:
        await repo.updateProfile(
          ref.read(profileProvider).copyWith(heightCm: _heightCm),
        );
        // El peso es un registro con fecha, no un campo del perfil: entra por
        // la misma puerta que el de todos los días, así que el primer punto de
        // la curva de progreso es el de hoy y no un valor suelto.
        await repo.logWeight(weightKg: _weightKg!, date: today());
      case 2:
        await repo.updateProfile(
          ref.read(profileProvider).copyWith(activityLevel: _level),
        );
      default:
        await _finish(repo);
        return;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _step++;
    });
  }

  Future<void> _finish(NutrimatRepositories repo) async {
    final preset = GoalPreset.of(_goalType!);
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
    context.go(Routes.home);
  }

  void _back() {
    if (_step == 0 || _saving) return;
    setState(() => _step--);
  }

  /// La salida de emergencia.
  ///
  /// Sin esto, quien no quiera dar estos datos queda encerrado en una pantalla
  /// de la que no se sale ni cerrando la app —el router vuelve a traerlo acá en
  /// el próximo arranque—, y la única forma de salir sería desinstalar. Cerrar
  /// sesión no borra nada: los datos que haya siguen en el servidor.
  Future<void> _signOut() async {
    final confirmed = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: '¿Salir sin completar?',
        body:
            'Volvés a la bienvenida. Tu cuenta y lo que tengas cargado quedan '
            'como están, y podés entrar de nuevo cuando quieras.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Seguir acá',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Salir',
            variant: NmButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(repositoryProvider).signOut();
    if (!mounted) return;
    context.go(Routes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return NmScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s8),
          StepIndicator(current: _step + 1, total: OnboardingScreen.totalSteps),
          const SizedBox(height: NmSpace.s6),
          Text(
            switch (_step) {
              0 => 'Empecemos por vos',
              1 => 'Tu altura y tu peso de hoy',
              2 => '¿Cuánto te movés?',
              _ => '¿Qué buscás?',
            },
            style: NmTextStyles.from(NmType.h1, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            switch (_step) {
              0 =>
                'La edad y el sexo entran en la fórmula del metabolismo basal. '
                    'No se comparten con nadie, ni con tus pals.',
              1 =>
                'Con esto y lo anterior ya podemos calcular cuánto gastás. El '
                    'peso lo vas a poder registrar todos los días.',
              2 =>
                'Es el multiplicador que convierte tu metabolismo basal en el '
                    'gasto del día. Elegí lo que hacés en una semana normal.',
              _ =>
                'De acá salen tus calorías, tus macros y tu objetivo semanal '
                    'de actividad. Se cambia cuando quieras.',
            },
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s8),

          switch (_step) {
            0 => _StepIdentity(
              sex: _sex,
              birthDate: _birthDate,
              error: _birthError,
              onSex: (v) => setState(() => _sex = v),
              onBirthDate: (v) => setState(() {
                if (ageFromBirthDate(v) < 13) {
                  _birthError =
                      'Necesitás tener al menos 13 años para usar Nutrimat.';
                  return;
                }
                _birthError = null;
                _birthDate = v;
              }),
            ),
            1 => _StepBody(
              height: _height,
              weight: _weight,
              heightError: _heightError,
              weightError: _weightError,
              onChanged: () => setState(() {
                _heightError = _height.text.isEmpty || _heightCm != null
                    ? null
                    : 'Poné una altura entre 90 y 250 cm.';
                _weightError = _weight.text.isEmpty || _weightKg != null
                    ? null
                    : 'Poné un peso entre 25 y 400 kg.';
              }),
            ),
            2 => _StepActivity(
              level: _level,
              onChanged: (v) => setState(() => _level = v),
            ),
            _ => _StepGoal(
              selected: _goalType,
              weightKg: _weightKg,
              onChanged: (v) => setState(() => _goalType = v),
            ),
          },

          // El resumen del cálculo, en cuanto hay con qué hacerlo.
          //
          // Aparece recién en el paso del nivel de actividad porque antes no
          // hay número que mostrar, y aparece porque pedir cuatro datos sin
          // decir para qué es pedirle a alguien que confíe. Acá se ve que el
          // objetivo sale de lo que se acaba de cargar y no de una tabla.
          if (_step >= 2) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            _CalculationPreview(
              sex: _sex,
              birthDate: _birthDate,
              heightCm: _heightCm,
              weightKg: _weightKg,
              level: _level,
              goalType: _goalType,
            ),
          ],

          const SizedBox(height: NmSpace.s8),
          NmButton(
            label: _step == OnboardingScreen.totalSteps - 1
                ? 'Empezar'
                : 'Continuar',
            block: true,
            loading: _saving,
            onPressed: _canContinue ? _next : null,
          ),
          const SizedBox(height: NmSpace.s2),
          Row(
            children: <Widget>[
              if (_step > 0)
                NmButton.ghost(label: 'Atrás', onPressed: _back),
              const Spacer(),
              NmButton.ghost(label: 'Salir', onPressed: _signOut),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepIdentity extends StatelessWidget {
  const _StepIdentity({
    required this.sex,
    required this.birthDate,
    required this.error,
    required this.onSex,
    required this.onBirthDate,
  });

  final BiologicalSex sex;
  final DateTime? birthDate;
  final String? error;
  final ValueChanged<BiologicalSex> onSex;
  final ValueChanged<DateTime> onBirthDate;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final age = birthDate == null ? null : ageFromBirthDate(birthDate!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Sexo biológico',
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s2),
        NmSegmentedControl<BiologicalSex>(
          options: BiologicalSex.values
              .map((s) => (s, s == BiologicalSex.unspecified ? 'Otro' : s.label))
              .toList(),
          value: sex,
          onChanged: onSex,
        ),
        const SizedBox(height: NmSpace.s2),
        const InfoNote(
          text: 'Se usa solo para la fórmula de metabolismo basal. Con "Otro" '
              'se toma el promedio de las dos.',
        ),
        const SizedBox(height: NmSpace.s6),
        NmDateField(
          label: 'Fecha de nacimiento',
          value: birthDate,
          error: error,
          helper: age == null ? null : '$age años',
          lastDate: DateTime.now(),
          // No es una suposición sobre nadie: es dónde abrir el calendario para
          // que el primer gesto sea elegir y no retroceder treinta años.
          initialDate: DateTime(DateTime.now().year - 30, 1, 1),
          onChanged: onBirthDate,
        ),
      ],
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.height,
    required this.weight,
    required this.heightError,
    required this.weightError,
    required this.onChanged,
  });

  final TextEditingController height;
  final TextEditingController weight;
  final String? heightError;
  final String? weightError;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      NmNumberField(
        label: 'Altura',
        controller: height,
        suffix: 'cm',
        error: heightError,
        autofocus: true,
        onChanged: (_) => onChanged(),
      ),
      const SizedBox(height: NmSpace.s6),
      NmNumberField(
        label: 'Peso de hoy',
        controller: weight,
        suffix: 'kg',
        decimals: 1,
        error: weightError,
        helper: 'Queda registrado con la fecha de hoy.',
        onChanged: (_) => onChanged(),
      ),
    ],
  );
}

class _StepActivity extends StatelessWidget {
  const _StepActivity({required this.level, required this.onChanged});

  final ActivityLevel level;
  final ValueChanged<ActivityLevel> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (final option in ActivityLevel.values)
        Padding(
          padding: const EdgeInsets.only(bottom: NmSpace.s2),
          child: NmRadioRow<ActivityLevel>(
            title: option.label,
            subtitle: option.description,
            value: option,
            groupValue: level,
            onChanged: onChanged,
          ),
        ),
    ],
  );
}

class _StepGoal extends StatelessWidget {
  const _StepGoal({
    required this.selected,
    required this.weightKg,
    required this.onChanged,
  });

  final GoalType? selected;
  final double? weightKg;
  final ValueChanged<GoalType> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (final preset in GoalPreset.all)
        Padding(
          padding: const EdgeInsets.only(bottom: NmSpace.s3),
          child: GoalPresetCard(
            preset: preset,
            selected: preset.goalType == selected,
            weightKg: weightKg,
            onTap: () => onChanged(preset.goalType),
          ),
        ),
    ],
  );
}

/// Lo que sale de los datos cargados, mientras se cargan.
///
/// Los mismos tres números que después explica Objetivo y macros, con las
/// mismas funciones: si acá dijera otra cosa que la pantalla de Objetivo, una
/// de las dos estaría mintiendo.
class _CalculationPreview extends StatelessWidget {
  const _CalculationPreview({
    required this.sex,
    required this.birthDate,
    required this.heightCm,
    required this.weightKg,
    required this.level,
    required this.goalType,
  });

  final BiologicalSex sex;
  final DateTime? birthDate;
  final double? heightCm;
  final double? weightKg;
  final ActivityLevel level;
  final GoalType? goalType;

  @override
  Widget build(BuildContext context) {
    if (birthDate == null || heightCm == null || weightKg == null) {
      return const SizedBox.shrink();
    }

    final bmrValue = bmrMifflinStJeor(
      weightKg: weightKg!,
      heightCm: heightCm!,
      ageYears: ageFromBirthDate(birthDate!),
      sex: sex,
    );
    final tdeeValue = tdee(bmr: bmrValue, activityLevel: level);
    final target = goalType == null
        ? null
        : calorieTarget(
            tdee: tdeeValue,
            goalType: goalType!,
            rateKgPerWeek: GoalPreset.of(goalType!).rateKgPerWeek,
            sex: sex,
          );

    return NmCard(
      child: Column(
        children: <Widget>[
          ValueRow(
            label: 'Metabolismo basal',
            caption: 'Mifflin-St Jeor',
            value: Fmt.kcal(bmrValue),
          ),
          ValueRow(
            label: '× nivel de actividad',
            caption: level.label,
            value: Fmt.decimal2(level.factor),
          ),
          ValueRow(label: 'Gasto diario', value: Fmt.kcal(tdeeValue)),
          if (target != null) ...<Widget>[
            const NmDivider(),
            ValueRow(
              label: 'Tu objetivo',
              value: Fmt.kcal(target.target),
              emphasis: true,
            ),
          ],
        ],
      ),
    );
  }
}
