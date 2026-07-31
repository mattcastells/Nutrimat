/// Reconcilia el documento local con el que vino de las tablas.
///
/// ## Por qué existe
///
/// Hasta acá las tablas solo se consultaban **si el teléfono estaba vacío**: en
/// cuanto había algo local, la app no volvía a mirarlas nunca. Con eso el
/// documento era la fuente de verdad y las tablas un respaldo de solo escritura,
/// que es exactamente lo que había que dar vuelta — y lo que impide que la misma
/// cuenta se use desde dos lados. Un navegador que ya se visitó una vez tiene su
/// propia copia en `localStorage`, así que sin esto la web y el teléfono
/// divergen desde la segunda visita y no se vuelven a encontrar.
///
/// ## La regla
///
/// **Unión por id, gana el más reciente, y nunca se pierde nada.** En detalle:
///
/// 1. Un registro que está en los dos lados se resuelve por su marca de tiempo:
///    `updatedAt` donde existe, `loggedAt` donde es lo que se reescribe en cada
///    guardado.
/// 2. Empate, o sin marca de tiempo de ninguno de los dos lados: **gana el
///    local**. Es el conservador: lo que la persona tiene delante no se
///    reemplaza por algo del servidor que no se puede probar que sea más nuevo.
/// 3. Un registro que está solo en local **se conserva**. Puede ser algo que
///    todavía no se subió; borrarlo por no estar del otro lado sería perder un
///    dato por un problema de red.
/// 4. Un registro que está solo en el servidor **se suma**. Es lo que cargaron
///    desde otro dispositivo.
///
/// De ahí sale un invariante que los tests verifican y que conviene tener a
/// mano: **el documento reconciliado nunca tiene menos registros que el local**.
/// Esta función no puede borrar nada. Lo único que puede hacer un borrado es un
/// registro marcado como borrado (`deletedAt`) que gane por ser más reciente, y
/// eso es un borrado que alguien pidió, no un accidente.
///
/// ## Lo que no se toca
///
/// El perfil, la integración, los filtros y las preferencias se quedan **como
/// están en local**. No son un historial: son la configuración de este
/// dispositivo, cambian poco, y pisarlas con las de otro lado es molesto sin
/// aportar nada. La excepción natural ya está cubierta: si el documento local
/// está vacío, no hay nada local que conservar y entra el remoto entero.
library;

/// Las listas del documento que se reconcilian por id, y con qué marca de
/// tiempo se desempata cada una.
///
/// Está escrito así —una tabla, no un `if` por colección— para que agregar una
/// lista nueva sea agregar una fila. Una colección que se olvide acá no se
/// rompe: cae en [_keepLocal] y se conserva la local, que es el lado seguro.
const Map<String, List<String>> _timestampFields = <String, List<String>>{
  'meals': <String>['updatedAt'],
  'activities': <String>['updatedAt'],
  'waterLogs': <String>['updatedAt'],
  // El peso, las medidas y el sueño reescriben `loggedAt` en cada guardado, así
  // que cumple el mismo papel que `updatedAt` en los otros.
  'weightLogs': <String>['loggedAt'],
  'measurements': <String>['loggedAt'],
  'sleepLogs': <String>['loggedAt'],
  // Sin marca de tiempo: se unen por id y ante conflicto gana el local.
  'goals': <String>[],
  'activityGoals': <String>[],
  'userFoods': <String>[],
  'templates': <String>[],
  'customTypes': <String>[],
};

/// Listas de valores sueltos —sin id— que se unen sin desempatar.
const List<String> _idlessLists = <String>['recentFoodIds', 'restDays'];

/// Reconcilia [local] con [remote] y devuelve el documento resultante.
///
/// Los dos vienen con la forma de `LocalStore.toDocument()`: el cliente
/// relacional arma el remoto con esa misma forma justamente para que haya un
/// solo lector y un solo reconciliador.
Map<String, dynamic> mergeDocuments({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) {
  // Sin nada local, el remoto entra entero: no hay nada que reconciliar y
  // conservar la configuración vacía de un dispositivo recién instalado no le
  // sirve a nadie. Es el caso del navegador que se abre por primera vez.
  if (_isEmpty(local)) return Map<String, dynamic>.from(remote);

  final merged = Map<String, dynamic>.from(local);

  for (final entry in _timestampFields.entries) {
    final key = entry.key;
    final localRows = _rows(local[key]);
    final remoteRows = _rows(remote[key]);
    if (remoteRows.isEmpty) continue;

    merged[key] = _mergeById(
      localRows: localRows,
      remoteRows: remoteRows,
      timestampFields: entry.value,
    );
  }

  for (final key in _idlessLists) {
    final localList = _values(local[key]);
    final remoteList = _values(remote[key]);
    if (remoteList.isEmpty) continue;
    // El orden local manda —en los recientes significa algo— y lo que solo
    // está del otro lado se agrega al final.
    merged[key] = <Object?>[
      ...localList,
      ...remoteList.where((v) => !localList.contains(v)),
    ];
  }

  return merged;
}

/// Un documento sin un solo registro de contenido.
///
/// Se mira el contenido y no las claves: un documento recién creado trae todas
/// las listas, vacías, y tratarlo como "tiene datos" haría que la reconciliación
/// conservara la nada.
bool _isEmpty(Map<String, dynamic> document) {
  for (final key in _timestampFields.keys) {
    if (_rows(document[key]).isNotEmpty) return false;
  }
  return true;
}

List<Map<String, dynamic>> _rows(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in raw)
      if (item is Map<String, dynamic>) item,
  ];
}

List<Object?> _values(Object? raw) =>
    raw is List ? List<Object?>.from(raw) : const <Object?>[];

/// Une dos listas por `id`, resolviendo los repetidos por marca de tiempo.
///
/// El resultado conserva el orden local y agrega al final lo que solo estaba del
/// otro lado, para que la reconciliación no reordene un historial que la persona
/// ya vio en cierto orden.
List<Map<String, dynamic>> _mergeById({
  required List<Map<String, dynamic>> localRows,
  required List<Map<String, dynamic>> remoteRows,
  required List<String> timestampFields,
}) {
  final remoteById = <String, Map<String, dynamic>>{};
  final remoteWithoutId = <Map<String, dynamic>>[];
  for (final row in remoteRows) {
    final id = row['id'];
    if (id is String && id.isNotEmpty) {
      remoteById[id] = row;
    } else {
      // Sin id no se puede aparear con nada. Se conserva igual: descartarlo
      // sería perder un registro por venir mal formado.
      remoteWithoutId.add(row);
    }
  }

  final out = <Map<String, dynamic>>[];
  final usados = <String>{};

  for (final localRow in localRows) {
    final id = localRow['id'];
    if (id is! String || !remoteById.containsKey(id)) {
      out.add(localRow);
      continue;
    }
    usados.add(id);
    final remoteRow = remoteById[id]!;
    out.add(
      _remoteIsNewer(localRow, remoteRow, timestampFields)
          ? remoteRow
          : localRow,
    );
  }

  for (final entry in remoteById.entries) {
    if (!usados.contains(entry.key)) out.add(entry.value);
  }
  out.addAll(remoteWithoutId);

  return out;
}

/// Si el registro remoto le gana al local.
///
/// Estrictamente más nuevo: ante un empate gana el local. La igualdad es el caso
/// normal —el mismo registro subido y bajado— y ahí reemplazarlo no cambiaría
/// nada salvo el riesgo de traerse una versión con menos campos.
bool _remoteIsNewer(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
  List<String> timestampFields,
) {
  for (final field in timestampFields) {
    final localAt = _parse(local[field]);
    final remoteAt = _parse(remote[field]);
    // Sin fecha de un lado no se puede comparar, y sin comparación no se
    // reemplaza: gana el local.
    if (localAt == null || remoteAt == null) return false;
    if (remoteAt.isAfter(localAt)) return true;
    if (localAt.isAfter(remoteAt)) return false;
  }
  return false;
}

DateTime? _parse(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
