import '../models/meal.dart';

/// Cómo se llama una comida cuando nadie le puso nombre.
///
/// Hasta acá el título era `items.first.name`: el primer ingrediente que se
/// hubiera cargado. Una milanesa con puré y ensalada se llamaba "Puré de papa"
/// si el puré entró primero, y dos comidas completamente distintas quedaban con
/// el mismo nombre por compartir el primer ítem. Eso no es un resumen, es un
/// accidente del orden de carga — y encima es lo que ven los pals y lo que
/// agrupa "lo que repetís" (`frequentMeals`).
///
/// Acá se arma un resumen de verdad: los ítems que más pesan en el plato, en
/// castellano y con la cola contada. Es una función pura y sin estado para que
/// la usen igual la app, la proyección de Pals y los tests.
abstract final class MealTitle {
  /// Cuántos ítems se nombran antes de contar el resto.
  ///
  /// Dos y no tres: "Milanesa, puré y ensalada" ya no entra en una fila de
  /// lista sin cortarse, y un título que se corta con puntos suspensivos no
  /// resume nada.
  static const int maxNamed = 2;

  /// Un título más largo que esto deja de leerse de un vistazo.
  static const int maxLength = 60;

  /// El resumen de una lista de ítems. Cadena vacía si no hay ninguno: quien
  /// llama decide con qué reemplazarla (el momento del día, normalmente).
  static String fromItems(List<MealItem> items) =>
      fromNames(items.map((i) => i.name).toList());

  /// La misma regla, sobre nombres sueltos. Existe aparte porque la
  /// proyección de Pals y la revisión de un análisis tienen los nombres antes
  /// de tener [MealItem]s.
  static String fromNames(List<String> rawNames) {
    final names = <String>[];
    for (final raw in rawNames) {
      final clean = _shorten(raw);
      // Sin repetir: tres ítems de "pan" son una comida de pan, no "Pan y pan".
      if (clean.isEmpty) continue;
      if (names.any((n) => n.toLowerCase() == clean.toLowerCase())) continue;
      names.add(clean);
    }

    if (names.isEmpty) return '';
    if (names.length == 1) return _cap(names.first);
    if (names.length <= maxNamed) {
      return _cap('${names.first} y ${_lower(names[1])}');
    }

    final rest = names.length - maxNamed;
    return _cap(
      '${names.first}, ${_lower(names[1])} y $rest más',
    );
  }

  /// Recorta un nombre de ítem a su parte útil.
  ///
  /// Los nombres del catálogo vienen con la aclaración detrás de una coma o
  /// entre paréntesis ("Arroz blanco, cocido sin sal", "Pan (integral)"). Para
  /// el título alcanza con lo de adelante: la precisión ya está en la lista de
  /// ítems, que es donde se la busca.
  static String _shorten(String raw) {
    var value = raw.trim();
    final paren = value.indexOf('(');
    if (paren > 0) value = value.substring(0, paren);
    final comma = value.indexOf(',');
    if (comma > 0) value = value.substring(0, comma);
    value = value.trim();
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1).trimRight()}…';
  }

  static String _lower(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  static String _cap(String s) {
    final value = s.length <= maxLength
        ? s
        : '${s.substring(0, maxLength - 1).trimRight()}…';
    return value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
  }
}
