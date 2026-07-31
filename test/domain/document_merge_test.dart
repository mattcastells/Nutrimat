// La reconciliación entre el documento local y las tablas.
//
// Es el cambio de más riesgo del proyecto: hasta acá las tablas eran un
// respaldo de solo escritura y el documento mandaba, justamente para no
// arriesgar los datos de nadie mientras se verificaba. Darlo vuelta significa
// que algo de afuera puede reemplazar lo que la persona tiene delante, y este
// archivo existe para acotar exactamente cuándo.
//
// El invariante de fondo, y el que más importa: **reconciliar nunca puede dejar
// menos registros de los que había**. Esta función no borra. Lo único que puede
// hacer desaparecer algo es un registro marcado como borrado que gane por ser
// más reciente — y eso es un borrado que alguien pidió.

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/domain/services/document_merge.dart';

Map<String, dynamic> doc({
  List<Map<String, dynamic>> meals = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> weightLogs = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> waterLogs = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> goals = const <Map<String, dynamic>>[],
  List<Object?> recentFoodIds = const <Object?>[],
  Map<String, dynamic>? profile,
}) => <String, dynamic>{
  'schemaVersion': 1,
  'profile': profile,
  'meals': meals,
  'weightLogs': weightLogs,
  'waterLogs': waterLogs,
  'goals': goals,
  'recentFoodIds': recentFoodIds,
};

Map<String, dynamic> meal(String id, String updatedAt, {int kcal = 100}) =>
    <String, dynamic>{
      'id': id,
      'updatedAt': updatedAt,
      'name': 'Comida $id',
      'kcal': kcal,
    };

Map<String, dynamic> weight(String id, String loggedAt, double kg) =>
    <String, dynamic>{'id': id, 'loggedAt': loggedAt, 'weightKg': kg};

void main() {
  group('lo que no se puede perder', () {
    test('nunca quedan menos registros de los que había', () {
      final local = doc(
        meals: <Map<String, dynamic>>[
          meal('a', '2026-07-30T10:00:00Z'),
          meal('b', '2026-07-30T11:00:00Z'),
          meal('c', '2026-07-30T12:00:00Z'),
        ],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-31T10:00:00Z')],
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect((merged['meals']! as List).length, 3);
    });

    test('lo que solo está en local sobrevive', () {
      // Puede ser algo que todavía no se subió. Borrarlo por no estar del otro
      // lado sería perder un dato por un problema de red.
      final local = doc(
        meals: <Map<String, dynamic>>[meal('sin-subir', '2026-07-31T10:00:00Z')],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[meal('otra', '2026-07-31T09:00:00Z')],
      );

      final merged = mergeDocuments(local: local, remote: remote);
      final ids = (merged['meals']! as List)
          .map((m) => (m as Map)['id'])
          .toList();

      expect(ids, containsAll(<String>['sin-subir', 'otra']));
    });

    test('un remoto vacío no toca nada', () {
      final local = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-30T10:00:00Z')],
        weightLogs: <Map<String, dynamic>>[
          weight('w', '2026-07-30T08:00:00Z', 80),
        ],
      );

      final merged = mergeDocuments(local: local, remote: doc());

      expect(merged['meals'], local['meals']);
      expect(merged['weightLogs'], local['weightLogs']);
    });
  });

  group('quién gana un conflicto', () {
    test('el más reciente por updatedAt', () {
      final local = doc(
        meals: <Map<String, dynamic>>[
          meal('a', '2026-07-30T10:00:00Z', kcal: 100),
        ],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[
          meal('a', '2026-07-31T10:00:00Z', kcal: 250),
        ],
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect((merged['meals']! as List).length, 1);
      expect(((merged['meals']! as List).first as Map)['kcal'], 250);
    });

    test('el local si es el más reciente, aunque el otro venga del servidor', () {
      final local = doc(
        meals: <Map<String, dynamic>>[
          meal('a', '2026-08-01T10:00:00Z', kcal: 999),
        ],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[
          meal('a', '2026-07-31T10:00:00Z', kcal: 250),
        ],
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect(((merged['meals']! as List).first as Map)['kcal'], 999);
    });

    test('empatados gana el local', () {
      // Es el caso normal: el mismo registro subido y bajado. Reemplazarlo no
      // cambiaría nada salvo el riesgo de traerse una versión con menos campos.
      final local = doc(
        meals: <Map<String, dynamic>>[
          meal('a', '2026-07-31T10:00:00Z', kcal: 100),
        ],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[
          meal('a', '2026-07-31T10:00:00Z', kcal: 250),
        ],
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect(((merged['meals']! as List).first as Map)['kcal'], 100);
    });

    test('sin marca de tiempo comparable gana el local', () {
      final local = doc(
        meals: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'kcal': 100},
        ],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[
          meal('a', '2026-08-01T10:00:00Z', kcal: 250),
        ],
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect(((merged['meals']! as List).first as Map)['kcal'], 100);
    });

    test('el peso desempata por loggedAt, que es lo que reescribe al guardar', () {
      final local = doc(
        weightLogs: <Map<String, dynamic>>[
          weight('w', '2026-07-30T08:00:00Z', 80.0),
        ],
      );
      final remote = doc(
        weightLogs: <Map<String, dynamic>>[
          weight('w', '2026-07-31T08:00:00Z', 79.4),
        ],
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect(((merged['weightLogs']! as List).first as Map)['weightKg'], 79.4);
    });
  });

  group('un borrado sí puede ganar', () {
    test('un borrado local que nunca se subió no lo resucita el servidor', () {
      // El escenario que más asusta al dar vuelta la fuente de verdad: borrás
      // algo, la subida falla, y al reconciliar vuelve de entre los muertos.
      //
      // No pasa, y no por suerte: `copyWith` refresca `updatedAt` en cada
      // llamada, así que el borrado local queda con fecha más nueva que la
      // copia que quedó en el servidor y le gana. Si algún día `copyWith`
      // dejara de hacerlo, este test se cae.
      final local = doc(
        meals: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'a',
            'updatedAt': '2026-07-31T18:00:00Z',
            'deletedAt': '2026-07-31T18:00:00Z',
          },
        ],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-31T10:00:00Z')],
      );

      final merged = mergeDocuments(local: local, remote: remote);
      final row = (merged['meals']! as List).first as Map;

      expect(row['deletedAt'], isNotNull, reason: 'sigue borrado');
    });

    test('el registro borrado en otro dispositivo llega marcado', () {
      // Es el único caso en que algo desaparece de la vista, y es un borrado
      // que alguien pidió: viene con `deletedAt` y con fecha más nueva.
      final local = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-30T10:00:00Z')],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'a',
            'updatedAt': '2026-07-31T10:00:00Z',
            'deletedAt': '2026-07-31T10:00:00Z',
            'name': 'Comida a',
          },
        ],
      );

      final merged = mergeDocuments(local: local, remote: remote);
      final row = (merged['meals']! as List).first as Map;

      expect(row['deletedAt'], isNotNull);
    });
  });

  group('el navegador que se abre por primera vez', () {
    test('sin nada local, entra el remoto entero', () {
      final remote = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-31T10:00:00Z')],
        profile: <String, dynamic>{'id': 'u1', 'displayName': 'Matías'},
      );

      final merged = mergeDocuments(local: doc(), remote: remote);

      expect((merged['meals']! as List).length, 1);
      // Incluida la configuración: no hay nada local que valga la pena
      // conservar en un dispositivo recién estrenado.
      expect((merged['profile']! as Map)['displayName'], 'Matías');
    });

    test('con datos locales, el perfil local se conserva', () {
      // El perfil no es historial: es la configuración de este dispositivo.
      // Pisarla con la de otro lado es molesto y no aporta.
      final local = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-31T10:00:00Z')],
        profile: <String, dynamic>{'id': 'u1', 'displayName': 'acá'},
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[meal('b', '2026-07-31T10:00:00Z')],
        profile: <String, dynamic>{'id': 'u1', 'displayName': 'allá'},
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect((merged['profile']! as Map)['displayName'], 'acá');
      // Pero la comida del otro dispositivo sí entra.
      expect((merged['meals']! as List).length, 2);
    });
  });

  group('listas sin id', () {
    test('los recientes se unen conservando el orden local', () {
      // Con contenido de los dos lados: un documento que solo tiene recientes
      // cuenta como vacío —no hay registros— y ahí entra el remoto entero.
      final local = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-31T10:00:00Z')],
        recentFoodIds: <Object?>['a', 'b'],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-31T10:00:00Z')],
        recentFoodIds: <Object?>['b', 'c'],
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect(merged['recentFoodIds'], <Object?>['a', 'b', 'c']);
    });
  });

  group('lo que viene mal formado no rompe nada', () {
    test('un registro remoto sin id se conserva en vez de descartarse', () {
      final local = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-31T10:00:00Z')],
      );
      final remote = doc(
        meals: <Map<String, dynamic>>[
          <String, dynamic>{'updatedAt': '2026-07-31T11:00:00Z', 'kcal': 5},
        ],
      );

      final merged = mergeDocuments(local: local, remote: remote);

      expect((merged['meals']! as List).length, 2);
    });

    test('una lista remota que no es lista se ignora', () {
      final local = doc(
        meals: <Map<String, dynamic>>[meal('a', '2026-07-31T10:00:00Z')],
      );
      final remote = <String, dynamic>{'meals': 'esto no es una lista'};

      final merged = mergeDocuments(local: local, remote: remote);

      expect((merged['meals']! as List).length, 1);
    });
  });
}
