import '../enums/enums.dart';

/// Punto de partida de cada objetivo: ritmo, proteína y actividad semanal.
///
/// Elegir "Bajar de peso" tiene que dejar la app configurada, no solo cambiar
/// una etiqueta. Estos valores son el arranque razonable de cada camino y todos
/// se pueden mover después desde Objetivo y macros: son un default, no un
/// diagnóstico, y ninguno reemplaza lo que indique un profesional.
///
/// De dónde salen:
///
/// - **Ritmo.** 0,5 kg/semana para bajar es el punto donde el déficit (≈ 550
///   kcal) todavía es sostenible; el tope duro sigue siendo 1 kg (RN-13). Para
///   subir, 0,25 kg/semana: más rápido que eso es mayormente grasa (D-04).
/// - **Proteína.** 1,6 g/kg cubre a cualquier persona activa; 2,0 g/kg en
///   déficit protege la masa magra y al ganar músculo es el insumo directo.
/// - **Actividad.** 150 min semanales de intensidad moderada es la
///   recomendación general de la OMS, con 2 sesiones de fuerza. Para bajar de
///   peso se sube a 200; para ganar músculo la fuerza pasa a 4 sesiones, que es
///   donde está el estímulo.
class GoalPreset {
  const GoalPreset({
    required this.goalType,
    required this.rateKgPerWeek,
    required this.proteinGPerKg,
    required this.activeMinutesPerWeek,
    required this.strengthSessionsPerWeek,
    required this.headline,
    required this.detail,
  });

  final GoalType goalType;

  /// Kg por semana. 0 en "Mantener".
  final double rateKgPerWeek;

  /// Piso de proteína diaria, en gramos por kilo de peso corporal.
  final double proteinGPerKg;

  final int activeMinutesPerWeek;
  final int strengthSessionsPerWeek;

  /// Una línea de qué hace el objetivo, para la pantalla de elección.
  final String headline;

  /// Qué queda configurado al elegirlo.
  final String detail;

  /// Gramos de proteína por día para un peso dado.
  int proteinTargetG(double weightKg) => (proteinGPerKg * weightKg).round();

  static const GoalPreset lose = GoalPreset(
    goalType: GoalType.lose,
    rateKgPerWeek: 0.5,
    proteinGPerKg: 2.0,
    activeMinutesPerWeek: 200,
    strengthSessionsPerWeek: 2,
    headline: 'Déficit sostenible, con la proteína alta.',
    detail:
        'Medio kilo por semana, 2 g de proteína por kilo para no perder '
        'músculo y 200 minutos de actividad semanal.',
  );

  static const GoalPreset maintain = GoalPreset(
    goalType: GoalType.maintain,
    rateKgPerWeek: 0,
    proteinGPerKg: 1.6,
    activeMinutesPerWeek: 150,
    strengthSessionsPerWeek: 2,
    headline: 'Comer lo que gastás y sostener la rutina.',
    detail:
        'El objetivo es tu gasto diario, 1,6 g de proteína por kilo y los 150 '
        'minutos semanales de la recomendación general.',
  );

  static const GoalPreset gain = GoalPreset(
    goalType: GoalType.gain,
    rateKgPerWeek: 0.25,
    proteinGPerKg: 1.6,
    activeMinutesPerWeek: 150,
    strengthSessionsPerWeek: 3,
    headline: 'Superávit chico, para que el peso suba de a poco.',
    detail:
        'Un cuarto de kilo por semana, 1,6 g de proteína por kilo y 3 '
        'entrenamientos de fuerza.',
  );

  static const GoalPreset gainMuscle = GoalPreset(
    goalType: GoalType.gainMuscle,
    rateKgPerWeek: 0.25,
    proteinGPerKg: 2.0,
    activeMinutesPerWeek: 150,
    strengthSessionsPerWeek: 4,
    headline: 'Superávit chico, proteína alta y fuerza cuatro veces.',
    detail:
        'Un cuarto de kilo por semana, 2 g de proteína por kilo y 4 '
        'entrenamientos de fuerza, que es de donde viene el estímulo.',
  );

  /// En el orden en que se muestran.
  static const List<GoalPreset> all = <GoalPreset>[
    lose,
    maintain,
    gain,
    gainMuscle,
  ];

  static GoalPreset of(GoalType type) => switch (type) {
    GoalType.lose => lose,
    GoalType.maintain => maintain,
    GoalType.gain => gain,
    GoalType.gainMuscle => gainMuscle,
  };
}
