import 'meal.dart';

/// Un ingrediente de una comida sugerida, con lo que aporta.
///
/// Tiene la misma forma que un [MealItem] a propósito: si alguien decide cargar
/// la sugerencia, cada ingrediente pasa a ser un ítem de la comida sin
/// traducciones de por medio. Una conversión en el camino sería un lugar donde
/// los números pueden cambiar entre lo que se mostró y lo que se guardó.
class SuggestedItem {
  const SuggestedItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final String name;
  final double quantity;
  final String unit;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  static SuggestedItem? fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String?;
    final kcal = (j['kcal'] as num?)?.round();
    if (name == null || name.isEmpty || kcal == null) return null;
    return SuggestedItem(
      name: name,
      quantity: (j['quantity'] as num?)?.toDouble() ?? 1,
      unit: j['unit'] as String? ?? 'porcion',
      kcal: kcal,
      proteinG: (j['proteinG'] as num?)?.toDouble() ?? 0,
      carbsG: (j['carbsG'] as num?)?.toDouble() ?? 0,
      fatG: (j['fatG'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Una comida propuesta para lo que queda del día.
///
/// **Es una estimación, no una receta de nutricionista**, y la pantalla lo dice.
/// Los números salen del mismo modelo que estima una foto, con la misma
/// validación: cada ingrediente cierra por Atwater y el total es la suma de sus
/// partes. Lo que no cierra no llega hasta acá.
class MealSuggestion {
  const MealSuggestion({
    required this.name,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.items,
    required this.steps,
    this.minutes,
  });

  final String name;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final List<SuggestedItem> items;

  /// Los pasos de la preparación, en orden y sin numerar: el número lo pone la
  /// pantalla, así que insertar uno en el medio no obliga a reescribir el resto.
  final List<String> steps;

  /// Cuánto lleva prepararla. `null` si el modelo no lo dijo — y ahí no se
  /// muestra, en vez de inventar un "15 min" de relleno.
  final int? minutes;

  /// Cuánto del presupuesto usa, entre 0 y 1. Para dibujar la barra.
  double fractionOf(int budgetKcal) =>
      budgetKcal <= 0 ? 0 : (kcal / budgetKcal).clamp(0.0, 1.0);

  static MealSuggestion? fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String?;
    final kcal = (j['kcal'] as num?)?.round();
    if (name == null || name.isEmpty || kcal == null) return null;

    final items = <SuggestedItem>[];
    for (final raw in (j['items'] as List<dynamic>? ?? <dynamic>[])) {
      if (raw is! Map) continue;
      final item = SuggestedItem.fromJson(Map<String, dynamic>.from(raw));
      if (item != null) items.add(item);
    }

    final steps = <String>[
      for (final s in (j['steps'] as List<dynamic>? ?? <dynamic>[]))
        if (s is String && s.trim().isNotEmpty) s.trim(),
    ];

    // Sin ingredientes o sin pasos no es una sugerencia, es un título. Se
    // descarta acá y no se muestra a medias.
    if (items.length < 2 || steps.length < 2) return null;

    return MealSuggestion(
      name: name,
      kcal: kcal,
      proteinG: (j['proteinG'] as num?)?.toDouble() ?? 0,
      carbsG: (j['carbsG'] as num?)?.toDouble() ?? 0,
      fatG: (j['fatG'] as num?)?.toDouble() ?? 0,
      items: items,
      steps: steps,
      minutes: (j['minutes'] as num?)?.round(),
    );
  }
}
