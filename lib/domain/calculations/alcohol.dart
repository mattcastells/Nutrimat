import 'rounding.dart';

/// Cuánto es "un trago", y cuántas calorías trae.
///
/// Todo lo de acá es **estimación**, y la pantalla lo dice con el mismo criterio
/// que el gasto por MET: un número aproximado no se muestra con la misma cara
/// que una medición. Lo que se guarda en la fila es el resultado, igual que
/// `activities.estimated_calories`, para que corregir un preset mañana no
/// reescriba lo que se tomó el sábado pasado.

/// Densidad del etanol, g/ml.
const double _densidadEtanol = 0.789;

/// Gramos de etanol de **una unidad de bebida estándar**.
///
/// Diez y no catorce: la UBE del Ministerio de Salud argentino, que es la que
/// usan las guías con las que se habla en una consulta acá. Catorce son los de
/// EE.UU. y darían un 40 % menos de tragos para el mismo vino.
const double gramosPorUBE = 10;

/// kcal por gramo de etanol. No son 4 como los hidratos ni 9 como las grasas:
/// el alcohol tiene su propio valor y es la razón por la que una noche puede
/// sumar 600 kcal sin que aparezca una sola comida.
const double _kcalPorGramoEtanol = 7.1;

const double _kcalPorGramoHidrato = 4;

/// Qué se tomó. El tipo no es cosmético: define cuántos hidratos trae además
/// del alcohol, que es la mitad de las calorías de una cerveza.
enum DrinkType {
  beer('beer', 'Cerveza', 3.6),
  wine('wine', 'Vino', 2.6),
  spirits('spirits', 'Destilado', 0),
  cocktail('cocktail', 'Trago', 10),
  cider('cider', 'Sidra', 5),
  other('other', 'Otra', 0);

  const DrinkType(this.wire, this.label, this.carbsPer100ml);

  final String wire;
  final String label;

  /// Gramos de hidratos por 100 ml. Valores de tabla, redondos a propósito:
  /// una cerveza no viene con su etiqueta nutricional en la mesa, y fingir dos
  /// decimales acá sería precisión inventada.
  final double carbsPer100ml;

  static DrinkType fromWire(String? w) => DrinkType.values.firstWhere(
    (t) => t.wire == w,
    orElse: () => DrinkType.other,
  );
}

/// Un formato de bebida con su volumen y graduación típicos.
///
/// Existe para que cargar sea elegir de una lista y no completar tres campos:
/// nadie sabe la graduación de lo que se tomó, pero todo el mundo sabe si fue
/// una lata o un chopp. Los valores viajan a la fila igual, así que quien
/// quiera corregirlos puede.
class DrinkPreset {
  const DrinkPreset({
    required this.id,
    required this.label,
    required this.type,
    required this.volumeMl,
    required this.abvPct,
  });

  final String id;
  final String label;
  final DrinkType type;
  final int volumeMl;
  final double abvPct;

  double get stdDrinks =>
      standardDrinks(volumeMl: volumeMl, abvPct: abvPct);

  int get kcal => alcoholKcal(
    volumeMl: volumeMl,
    abvPct: abvPct,
    type: type,
  );
}

/// Los formatos con los que se toma acá. Es una lista corta a propósito: el
/// campo libre está abajo de todo para lo que no entre.
const List<DrinkPreset> drinkPresets = <DrinkPreset>[
  DrinkPreset(
    id: 'beer_can',
    label: 'Lata de cerveza',
    type: DrinkType.beer,
    volumeMl: 473,
    abvPct: 5,
  ),
  DrinkPreset(
    id: 'beer_pint',
    label: 'Chopp / pinta',
    type: DrinkType.beer,
    volumeMl: 500,
    abvPct: 5,
  ),
  DrinkPreset(
    id: 'beer_bottle',
    label: 'Porrón',
    type: DrinkType.beer,
    volumeMl: 330,
    abvPct: 5,
  ),
  DrinkPreset(
    id: 'wine_glass',
    label: 'Copa de vino',
    type: DrinkType.wine,
    volumeMl: 150,
    abvPct: 13,
  ),
  DrinkPreset(
    id: 'wine_bottle',
    label: 'Botella de vino',
    type: DrinkType.wine,
    volumeMl: 750,
    abvPct: 13,
  ),
  DrinkPreset(
    id: 'spirit_shot',
    label: 'Medida de destilado',
    type: DrinkType.spirits,
    volumeMl: 45,
    abvPct: 40,
  ),
  DrinkPreset(
    id: 'cocktail',
    label: 'Trago / cóctel',
    type: DrinkType.cocktail,
    volumeMl: 250,
    abvPct: 12,
  ),
  DrinkPreset(
    id: 'cider_glass',
    label: 'Copa de sidra',
    type: DrinkType.cider,
    volumeMl: 200,
    abvPct: 5,
  ),
];

/// Gramos de etanol de un volumen a una graduación dada.
double ethanolGrams({required int volumeMl, required double abvPct}) =>
    volumeMl * (abvPct / 100) * _densidadEtanol;

/// Cuántas unidades de bebida estándar.
///
/// Es lo único con lo que se pueden **sumar** una cerveza y un whisky: 500 ml
/// de cerveza y 45 ml de whisky son casi la misma cantidad de alcohol, y sin
/// esta unidad el gráfico compararía mililitros y diría que la cerveza es diez
/// veces más.
double standardDrinks({required int volumeMl, required double abvPct}) =>
    roundTo(ethanolGrams(volumeMl: volumeMl, abvPct: abvPct) / gramosPorUBE, 2);

/// Las calorías de una bebida: el etanol más los hidratos que trae.
///
/// Los dos términos hacen falta. Solo con el etanol, una lata de cerveza daría
/// 130 kcal en vez de 200 y el error se acumularía justo en la bebida que más
/// se toma; solo con los hidratos, un whisky daría cero.
int alcoholKcal({
  required int volumeMl,
  required double abvPct,
  required DrinkType type,
}) {
  final etanol = ethanolGrams(volumeMl: volumeMl, abvPct: abvPct) *
      _kcalPorGramoEtanol;
  final hidratos =
      volumeMl / 100 * type.carbsPer100ml * _kcalPorGramoHidrato;
  return roundHalfUp(etanol + hidratos);
}

// El límite semanal de bajo riesgo de las guías del Ministerio de Salud —9 UBE
// y 14 según sexo— **no vive acá**: la app no lo muestra en ninguna pantalla, y
// el único lugar donde aparece es la referencia escrita del panel. Una
// constante que no lee nadie es peor que no tenerla, porque invita a suponer
// que algún cálculo la usa.
