import '../enums/enums.dart';
import 'calorie_target.dart';

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

  /// Kg por semana **de referencia**, para cuando no hay con qué calcular el
  /// gasto. Con datos corporales manda [GoalPace.steady], que sale de una
  /// fracción de ese gasto; sin ellos no hay fracción posible y este número es
  /// lo único que se puede decir.
  final double rateKgPerWeek;

  /// El ritmo con el que arranca cada objetivo. Es el mismo para los cuatro:
  /// la diferencia entre ellos ya la pone la fracción, que no es la misma
  /// bajando que subiendo.
  GoalPace get defaultPace => GoalPace.steady;

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

/// A qué velocidad avanza el objetivo. Es la única perilla que mueve las
/// calorías sin tocar los datos del cuerpo.
///
/// **Cada opción es una fracción del gasto diario, no una cantidad de kilos.**
/// Medio kilo por semana son 550 kcal para cualquiera, y 550 kcal es el 21 %
/// del gasto de una persona de 2.600 y el 35 % del de una de 1.550: el mismo
/// rótulo escondía dos esfuerzos que no se parecen, y el segundo es de los que
/// terminan en una consulta preguntando por qué la app le dio tan poco. Como el
/// gasto sale de metabolismo basal × nivel de actividad, la fracción ya está
/// leyendo el cuerpo y la semana de quien elige. Los kilos por semana no
/// desaparecen: pasan a ser la consecuencia, y se muestran como tal.
///
/// Los nombres no califican a quien elige. Un ritmo no es "agresivo" ni
/// "conservador": eso convierte una decisión práctica —cuánta comida queda por
/// día— en una sobre el carácter, y empuja a elegir el más duro para no quedar
/// como el que se rinde. Cada opción se muestra con su número al lado, que es
/// el dato con el que realmente se decide.
///
/// El tope sigue siendo 1 kg por semana (RN-13): sobre un gasto muy grande la
/// fracción se recorta ahí.
enum GoalPace {
  gentle('De a poco'),
  steady('Sostenido'),
  firm('Más firme'),
  fastest('Al máximo');

  const GoalPace(this.label);

  final String label;

  /// Qué fracción del gasto diario se resta —o se suma— con este ritmo.
  ///
  /// Bajar llega hasta el 25 %: más que eso es donde el déficit se empieza a
  /// pagar con masa magra y con adherencia, y no hay ritmo que valga eso.
  ///
  /// Subir usa fracciones más chicas porque el cuerpo no construye músculo al
  /// ritmo al que puede acumular grasa, y `gain` usa la mitad que `gain_muscle`:
  /// es D-04 —"subir de peso no es subir grasa"— dicho donde se puede leer, en
  /// vez de escondido en una multiplicación por 0,5 dentro de la fórmula.
  double fractionFor(GoalType goalType) => switch (goalType) {
    GoalType.lose => switch (this) {
      gentle => 0.10,
      steady => 0.15,
      firm => 0.20,
      fastest => 0.25,
    },
    GoalType.gainMuscle => switch (this) {
      gentle => 0.05,
      steady => 0.10,
      firm => 0.15,
      fastest => 0.20,
    },
    GoalType.gain => switch (this) {
      gentle => 0.025,
      steady => 0.05,
      firm => 0.075,
      fastest => 0.10,
    },
    // Mantener no tiene ritmo: el objetivo es el gasto y nada más.
    GoalType.maintain => 0,
  };

  /// Qué implica este ritmo, que no es lo mismo bajando que subiendo: bajando
  /// el costo es el margen del día, y subiendo es cuánto de lo que sube va a
  /// ser grasa.
  String detailFor(GoalType goalType) => switch (goalType) {
    GoalType.lose => switch (this) {
      gentle => 'Es el que más comida deja por día.',
      steady => 'El equilibrio entre avance y margen, y el que sugerimos.',
      firm => 'El día queda bastante más ajustado.',
      fastest => 'Es el tope, y deja poco lugar para improvisar.',
    },
    GoalType.gain || GoalType.gainMuscle => switch (this) {
      gentle => 'Es el que menos grasa suma.',
      steady => 'El equilibrio entre avance y grasa, y el que sugerimos.',
      firm => 'Buena parte de lo que suba va a ser grasa.',
      fastest => 'Es el tope, y casi todo lo que suba va a ser grasa.',
    },
    GoalType.maintain => '',
  };

  /// Cómo se dice esta fracción en pantalla: "20 % menos que tu gasto".
  String shareLabelFor(GoalType goalType) {
    final fraction = fractionFor(goalType);
    if (fraction == 0) return 'Tu gasto diario, sin ajuste';
    // Sin decimales cuando no hacen falta: "2,5 %" solo aparece en `gain`.
    final pct = fraction * 100;
    final texto = pct == pct.roundToDouble()
        ? pct.round().toString()
        : pct.toStringAsFixed(1).replaceAll('.', ',');
    return goalType == GoalType.lose
        ? '$texto % menos que tu gasto'
        : '$texto % más que tu gasto';
  }

  /// El ritmo que le corresponde a una fracción ya guardada.
  ///
  /// Un objetivo viejo trae kilos por semana y no una fracción, así que la
  /// pantalla tiene que poder volver de un lado al otro: sin esto, todo lo
  /// guardado antes de este cambio abriría sin nada marcado, y una lista sin
  /// selección se lee como si no hubiera elección hecha.
  static GoalPace nearestForRate({
    required double rateKgPerWeek,
    required GoalType goalType,
    required int tdee,
  }) {
    if (tdee <= 0 || goalType == GoalType.maintain) return steady;
    final fraction =
        (rateKgPerWeek * CalorieTargetRules.kcalPerKgOfFat / 7) / tdee;
    var best = steady;
    for (final pace in values) {
      final delta = (pace.fractionFor(goalType) - fraction).abs();
      if (delta < (best.fractionFor(goalType) - fraction).abs()) best = pace;
    }
    return best;
  }
}
