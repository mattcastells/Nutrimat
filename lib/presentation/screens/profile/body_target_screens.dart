import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/adherence.dart';
import '../../../domain/calculations/bmr.dart';
import '../../../domain/calculations/calorie_target.dart';
import '../../../domain/calculations/goal_presets.dart';
import '../../../domain/calculations/macros.dart';
import '../../../domain/calculations/tdee.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/goal.dart';
import '../../../domain/repositories/repositories.dart';
import '../../components/activity/activity_cards.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../weight/weight_sheet.dart';

const _uuid = Uuid();

/// S-32 · Perfil corporal. Mantiene al día lo que alimenta BMR, TDEE y MET.
class BodyProfileScreen extends ConsumerStatefulWidget {
  const BodyProfileScreen({super.key});

  @override
  ConsumerState<BodyProfileScreen> createState() => _BodyProfileScreenState();
}

class _BodyProfileScreenState extends ConsumerState<BodyProfileScreen> {
  late final TextEditingController _height = TextEditingController(
    text: ref.read(profileProvider).heightCm?.round().toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final profile = ref.watch(profileProvider);
    final repo = ref.watch(repositoryProvider);
    final weightKg = ref.watch(currentWeightProvider);
    final units = ref.watch(unitSystemProvider);
    final goal = ref.watch(currentGoalProvider);

    final age = profile.birthDate == null
        ? null
        : ageFromBirthDate(profile.birthDate!);

    int? suggested;
    if (profile.birthDate != null && profile.heightCm != null && weightKg != null) {
      final bmrValue = bmrMifflinStJeor(
        weightKg: weightKg,
        heightCm: profile.heightCm!,
        ageYears: age!,
        sex: profile.biologicalSex,
      );
      final tdeeValue = tdee(
        bmr: bmrValue,
        activityLevel: profile.activityLevel,
      );
      suggested = calorieTarget(
        tdee: tdeeValue,
        goalType: goal?.goalType ?? GoalType.maintain,
        rateKgPerWeek: goal?.rateKgPerWeek ?? 0,
        sex: profile.biologicalSex,
      ).target;
    }

    return NmScreen(
      title: 'Perfil corporal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            'Sexo biológico',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          NmSegmentedControl<BiologicalSex>(
            options: BiologicalSex.values
                .map(
                  (s) => (s, s == BiologicalSex.unspecified ? 'Otro' : s.label),
                )
                .toList(),
            value: profile.biologicalSex,
            onChanged: (v) =>
                repo.updateProfile(profile.copyWith(biologicalSex: v)),
          ),
          const SizedBox(height: NmSpace.s2),
          const InfoNote(
            text: 'Se usa solo para la fórmula de metabolismo basal.',
          ),
          const SizedBox(height: NmSpace.s6),
          NmDateField(
            label: 'Fecha de nacimiento',
            value: profile.birthDate,
            helper: age == null ? null : '$age años',
            lastDate: DateTime.now(),
            onChanged: (v) {
              if (ageFromBirthDate(v) < 13) {
                setState(
                  () => _error =
                      'Necesitás tener al menos 13 años para usar Nutrimat.',
                );
                return;
              }
              setState(() => _error = null);
              repo.updateProfile(profile.copyWith(birthDate: v));
            },
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            InfoNote(text: _error!, tone: NmNoteTone.caution),
          ],
          const SizedBox(height: NmSpace.s6),
          NmNumberField(
            label: 'Altura',
            controller: _height,
            suffix: 'cm',
            onChanged: (raw) {
              final parsed = double.tryParse(raw);
              if (parsed == null || parsed < 90 || parsed > 250) return;
              repo.updateProfile(profile.copyWith(heightCm: parsed));
            },
          ),
          const SizedBox(height: NmSpace.s6),
          NmCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'PESO ACTUAL',
                        style: NmTextStyles.from(
                          NmType.overline,
                          color: nm.textMuted,
                        ),
                      ),
                      const SizedBox(height: NmSpace.s1),
                      Text(
                        weightKg == null
                            ? 'Sin registro'
                            : Fmt.weight(weightKg, units),
                        style: NmTextStyles.from(
                          NmType.h3,
                          color: nm.text,
                        ).tnum,
                      ),
                    ],
                  ),
                ),
                NmButton.ghost(
                  label: 'Registrar',
                  onPressed: () => showWeightSheet(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Nivel de actividad'),
          for (final level in ActivityLevel.values)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s2),
              child: NmRadioRow<ActivityLevel>(
                title: level.label,
                subtitle: level.description,
                value: level,
                groupValue: profile.activityLevel,
                onChanged: (v) =>
                    repo.updateProfile(profile.copyWith(activityLevel: v)),
              ),
            ),
          const SizedBox(height: NmSpace.s6),
          // El IMC no se carga: sale de tu último peso y de tu altura, y se
          // mueve solo cuando alguno de los dos cambia. Sin decirlo, un número
          // en una pantalla de formularios se lee como un campo que no anda.
          if (weightKg != null && profile.heightCm != null)
            NmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ValueRow(
                    label: 'IMC',
                    caption: 'calculado, no se edita',
                    value: Fmt.decimal1(
                      bmi(weightKg: weightKg, heightCm: profile.heightCm!),
                    ),
                    emphasis: true,
                  ),
                  const NmDivider(),
                  const SizedBox(height: NmSpace.s2),
                  FormulaRow(
                    expression: 'peso ÷ altura²',
                    values:
                        '${Fmt.decimal1(weightKg)} kg ÷ '
                        '(${Fmt.decimal2(profile.heightCm! / 100)} m)² = '
                        '${Fmt.decimal1(bmi(weightKg: weightKg, heightCm: profile.heightCm!))}',
                  ),
                  const SizedBox(height: NmSpace.s3),
                  Text(
                    'Se actualiza solo cada vez que registrás un peso nuevo.',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ),
                  ),
                  const SizedBox(height: NmSpace.s3),
                  const InfoNote(
                    text: 'Es una referencia poblacional y nada más: no '
                        'distingue músculo de grasa ni dice nada sobre tu '
                        'salud. Para composición corporal miran los pliegues '
                        'y la bioimpedancia.',
                  ),
                  const SizedBox(height: NmSpace.s3),
                  NmButton.ghost(
                    label: 'Ver mis medidas corporales',
                    onPressed: () => context.push(Routes.progressMeasurements),
                  ),
                ],
              ),
            ),
          if (suggested != null &&
              goal != null &&
              suggested != goal.baseCalorieTarget) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            InfoNote(
              tone: NmNoteTone.info,
              text: 'Tu objetivo sugerido pasaría de '
                  '${Fmt.integer(goal.baseCalorieTarget)} a '
                  '${Fmt.integer(suggested)} kcal.',
              action: 'Actualizar objetivo',
              onAction: () => context.push('/profile/target'),
            ),
          ],
        ],
      ),
    );
  }
}

/// S-33 · Objetivo y macros.
class TargetScreen extends ConsumerStatefulWidget {
  const TargetScreen({super.key});

  @override
  ConsumerState<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends ConsumerState<TargetScreen> {
  GoalType? _goalType;
  double? _rate;
  bool _manual = false;
  late final TextEditingController _manualValue = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _manualValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final goal = ref.watch(currentGoalProvider);
    final weightKg = ref.watch(currentWeightProvider) ?? 70;
    final repo = ref.watch(repositoryProvider);

    if (goal == null) {
      return const NmScreen(
        title: 'Objetivo',
        child: Center(child: Text('Todavía no hay un objetivo.')),
      );
    }

    final goalType = _goalType ?? goal.goalType;
    final rate = _rate ?? goal.rateKgPerWeek;

    int? bmrValue;
    int? tdeeValue;
    var target = goal.baseCalorieTarget;
    var clamped = false;

    if (profile.birthDate != null && profile.heightCm != null) {
      bmrValue = bmrMifflinStJeor(
        weightKg: weightKg,
        heightCm: profile.heightCm!,
        ageYears: ageFromBirthDate(profile.birthDate!),
        sex: profile.biologicalSex,
      );
      tdeeValue = tdee(bmr: bmrValue, activityLevel: profile.activityLevel);
      final result = calorieTarget(
        tdee: tdeeValue,
        goalType: goalType,
        rateKgPerWeek: goalType == GoalType.maintain ? 0 : rate,
        sex: profile.biologicalSex,
      );
      if (!_manual) {
        target = result.target;
        clamped = result.clamped;
      }
    }
    if (_manual) {
      target = int.tryParse(_manualValue.text) ?? goal.baseCalorieTarget;
    }

    final macros = macroTargets(
      targetKcal: target,
      weightKg: weightKg,
      goalType: goalType,
    );
    final method = _manual ? TargetMethod.manual : TargetMethod.calculated;
    // El método también cuenta: pasar de manual a calculado con el mismo número
    // es un cambio real, y sin esto el botón quedaba deshabilitado.
    final dirty =
        target != goal.baseCalorieTarget ||
        goalType != goal.goalType ||
        rate != goal.rateKgPerWeek ||
        method != goal.targetMethod;

    return NmScreen(
      title: 'Objetivo y macros',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Objetivo vigente',
                  value: Fmt.kcal(goal.baseCalorieTarget),
                  emphasis: true,
                ),
                ValueRow(
                  label: 'Rige desde',
                  value: _formatDate(goal.startsOn),
                  muted: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          if (bmrValue != null) ...<Widget>[
            const NmSectionHeader(title: 'Cómo se calcula'),
            NmCard(
              child: Column(
                children: <Widget>[
                  ValueRow(
                    label: 'Metabolismo basal',
                    caption: 'Mifflin-St Jeor',
                    value: Fmt.kcal(bmrValue),
                  ),
                  ValueRow(
                    label: '× factor de actividad',
                    caption: profile.activityLevel.label,
                    value: Fmt.decimal2(profile.activityLevel.factor),
                  ),
                  ValueRow(label: 'Gasto diario', value: Fmt.kcal(tdeeValue!)),
                  if (goalType != GoalType.maintain)
                    ValueRow(
                      label: switch (goalType) {
                        GoalType.lose => '− déficit',
                        GoalType.gain => '+ superávit (al 50 %)',
                        GoalType.gainMuscle => '+ superávit',
                        GoalType.maintain => '',
                      },
                      value: Fmt.kcal(
                        (CalorieTargetRules.dailyAdjustment(rate) *
                                (goalType == GoalType.gain ? 0.5 : 1))
                            .round(),
                      ),
                    ),
                  const NmDivider(),
                  ValueRow(
                    label: 'Objetivo',
                    value: Fmt.kcal(target),
                    emphasis: true,
                  ),
                ],
              ),
            ),
            if (clamped) ...<Widget>[
              const SizedBox(height: NmSpace.s3),
              InfoNote(
                tone: NmNoteTone.caution,
                text: 'Ajustamos tu objetivo al mínimo saludable de '
                    '${CalorieTargetRules.minimumFor(profile.biologicalSex)} '
                    'kcal.',
              ),
            ],
            const SizedBox(height: NmSpace.s6),
          ],
          NmSectionHeader(
            title: 'Tipo de objetivo',
            action: 'Ver los cuatro',
            onAction: () => context.push(Routes.profileGoal),
          ),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final type in GoalType.values)
                NmChip(
                  label: type.label,
                  selected: type == goalType,
                  semanticsInRadioGroup: true,
                  onTap: () => setState(() {
                    _goalType = type;
                    // Cada objetivo trae su ritmo de referencia; conservar el
                    // del objetivo anterior daba combinaciones raras, como
                    // ganar músculo a 1 kg por semana.
                    _rate = GoalPreset.of(type).rateKgPerWeek;
                  }),
                ),
            ],
          ),
          if (goalType != GoalType.maintain) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            const NmSectionHeader(title: 'Ritmo'),
            Wrap(
              spacing: NmSpace.s2,
              runSpacing: NmSpace.s2,
              children: <Widget>[
                for (final option in const <double>[0.25, 0.5, 0.75, 1.0])
                  NmChip(
                    label: '${Fmt.decimal2(option)} kg / semana',
                    selected: rate == option,
                    semanticsInRadioGroup: true,
                    onTap: () => setState(() => _rate = option),
                  ),
              ],
            ),
            const SizedBox(height: NmSpace.s2),
            const InfoNote(text: 'El tope es 1 kg por semana.'),
          ],
          const SizedBox(height: NmSpace.s6),
          NmSwitchRow(
            title: 'Ingresar el objetivo a mano',
            value: _manual,
            onChanged: (v) => setState(() {
              _manual = v;
              if (v) _manualValue.text = target.toString();
            }),
          ),
          if (_manual) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            NmNumberField(
              label: 'Objetivo calórico',
              controller: _manualValue,
              suffix: 'kcal',
              helper: 'Entre 800 y 6000 kcal.',
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: 'Macros sugeridos'),
          NmCard(
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Proteínas',
                  caption: '${(macros.proteinG * 4 * 100 / target).round()} %',
                  value: Fmt.grams(macros.proteinG),
                ),
                ValueRow(
                  label: 'Carbohidratos',
                  caption: '${(macros.carbsG * 4 * 100 / target).round()} %',
                  value: Fmt.grams(macros.carbsG),
                ),
                ValueRow(
                  label: 'Grasas',
                  caption: '${(macros.fatG * 9 * 100 / target).round()} %',
                  value: Fmt.grams(macros.fatG),
                ),
              ],
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          const InfoNote(
            text: 'Al guardar, el objetivo nuevo rige desde hoy. Los días '
                'anteriores conservan el objetivo con el que fueron '
                'registrados.',
          ),
          // Sin datos corporales no hay fórmula posible: el objetivo solo puede
          // ser manual, y conviene decir dónde se cargan en vez de dejar el
          // botón apagado sin explicación.
          if (!profile.hasBodyData) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            InfoNote(
              text: 'Sin altura, nacimiento y sexo no se puede calcular. '
                  'Cargalos y el objetivo sale de tus datos.',
              action: 'Cargar mis datos',
              onAction: () => context.push(Routes.profileBody),
            ),
          ],
          const SizedBox(height: NmSpace.s4),
          NmButton(
            label: 'Guardar objetivo',
            block: true,
            loading: _saving,
            onPressed: !dirty
                ? null
                : () async {
                    if (target < 800 || target > 6000) return;
                    final minimum = CalorieTargetRules.minimumFor(
                      profile.biologicalSex,
                    );
                    if (target < minimum) {
                      final confirmed = await showNmDialog<bool>(
                        context: context,
                        builder: (context) => NmDialog(
                          title: 'Es un objetivo muy bajo',
                          body: 'Por debajo de $minimum kcal cuesta cubrir los '
                              'nutrientes básicos.',
                          actions: <Widget>[
                            NmButton.ghost(
                              label: 'Volver',
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
                            ),
                            NmButton(
                              label: 'Guardar igual',
                              onPressed: () => Navigator.of(context).pop(true),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                    }

                    setState(() => _saving = true);
                    await repo.saveGoal(
                      Goal(
                        id: _uuid.v4(),
                        goalType: goalType,
                        rateKgPerWeek: goalType == GoalType.maintain ? 0 : rate,
                        targetWeightKg: goal.targetWeightKg,
                        baseCalorieTarget: target,
                        targetMethod: _manual
                            ? TargetMethod.manual
                            : TargetMethod.calculated,
                        bmrKcal: bmrValue,
                        tdeeKcal: tdeeValue,
                        proteinG: macros.proteinG,
                        carbsG: macros.carbsG,
                        fatG: macros.fatG,
                        macroMethod: 'default',
                        startsOn: DateTime.now(),
                      ),
                    );
                    if (!context.mounted) return;
                    setState(() => _saving = false);
                    NmSnackbar.show(
                      context,
                      'Objetivo actualizado desde hoy',
                    );
                  },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';
}

/// S-34 · Mis alimentos, actividades, plantillas y favoritos.
class MyItemsScreen extends ConsumerStatefulWidget {
  const MyItemsScreen({this.initialTab = 0, super.key});

  final int initialTab;

  @override
  ConsumerState<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends ConsumerState<MyItemsScreen> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final weightKg = ref.watch(currentWeightProvider);

    return NmScreen(
      title: 'Mis cosas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmSegmentedControl<int>(
            options: const <(int, String)>[
              (0, 'Alimentos'),
              (1, 'Plantillas'),
              (2, 'Favoritos'),
            ],
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
          const SizedBox(height: NmSpace.s6),
          if (_tab == 0)
            _EmptyOrList(
              items: repo.ownFoods().map((f) => f.displayName).toList(),
              emptyTitle: 'Sin alimentos propios',
              emptyBody: 'Los alimentos que crees aparecen acá.',
              icon: PhosphorIcons.bowlFood(),
            )
          else if (_tab == 1)
            repo.templates.isEmpty
                ? _EmptyOrList(
                    items: const <String>[],
                    emptyTitle: 'Sin plantillas',
                    emptyBody:
                        'Guardá una actividad como plantilla para repetirla '
                        'en dos toques.',
                    icon: PhosphorIcons.barbell(),
                  )
                : Column(
                    children: <Widget>[
                      for (final template in repo.templates)
                        Padding(
                          padding: const EdgeInsets.only(bottom: NmSpace.s3),
                          child: ExerciseTemplateCard(
                            template: template,
                            typeName:
                                repo
                                    .typeById(template.activityTypeId)
                                    ?.displayName ??
                                'Actividad',
                            estimatedCalories: weightKg == null
                                ? null
                                : repo
                                      .estimate(
                                        ActivityDraft(
                                          activityTypeId:
                                              template.activityTypeId,
                                          startedAt: DateTime.now(),
                                          durationMinutes:
                                              template.defaultDurationMinutes,
                                          intensity: template.defaultIntensity,
                                          distanceMeters:
                                              template.defaultDistanceMeters,
                                        ),
                                      )
                                      .calories,
                            onDelete: () => repo.deleteTemplate(template.id),
                          ),
                        ),
                    ],
                  )
          else
            _EmptyOrList(
              items: <String>[
                ...repo.favorites().map((f) => 'Alimento · ${f.name}'),
                ...repo
                    .favoriteActivities()
                    .map((a) => 'Actividad · ${a.displayName}'),
              ],
              emptyTitle: 'Sin favoritos',
              emptyBody: 'Marcá con la estrella lo que uses seguido.',
              icon: PhosphorIcons.star(),
            ),
        ],
      ),
    );
  }
}

class _EmptyOrList extends StatelessWidget {
  const _EmptyOrList({
    required this.items,
    required this.emptyTitle,
    required this.emptyBody,
    required this.icon,
  });

  final List<String> items;
  final String emptyTitle;
  final String emptyBody;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    // El vacío es el `EmptyState` del sistema y no una columna a mano: la de
    // acá no estiraba al ancho disponible, así que el título y el cuerpo
    // quedaban centrados entre sí pero corridos respecto de la pantalla.
    if (items.isEmpty) {
      return EmptyState(icon: icon, title: emptyTitle, body: emptyBody);
    }
    return NmCard(
      padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
      child: Column(
        children: <Widget>[
          for (final item in items) NmListRow(title: item, dense: true),
        ],
      ),
    );
  }
}
