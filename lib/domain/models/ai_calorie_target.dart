/// El objetivo calórico que propuso la IA, ya acotado por el servidor.
///
/// Es una **propuesta**: existe al lado del número de la fórmula y no reemplaza
/// nada hasta que la persona la acepta. Por eso trae el porqué y los dos
/// números de los que salió — sin ellos sería un valor caído del cielo, que es
/// exactamente lo que el producto no hace (RN-03).
class AiCalorieTarget {
  const AiCalorieTarget({
    required this.targetKcal,
    required this.rationale,
    required this.clamped,
    required this.bmrKcal,
    required this.tdeeKcal,
  });

  final int targetKcal;

  /// Por qué ese número. Es la mitad del valor de esto: el número solo ya lo da
  /// la fórmula, y sin llamar a nadie.
  final String rationale;

  /// El mínimo de RN-12 subió la propuesta. Se dice, igual que en la fórmula.
  final bool clamped;

  /// Los recalculó el servidor con los mismos datos del perfil. Van para poder
  /// mostrar de dónde salió la banda dentro de la que la propuesta es válida.
  final int bmrKcal;
  final int tdeeKcal;
}
