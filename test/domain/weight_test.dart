// El bug reportado: no se podía editar ni borrar el peso de días anteriores.
//
// No era una fecha bloqueada en ningún lado —la causa real era que la lista
// de "Registros" nunca conectó `onEdit` ni un borrado a ninguna fila—, pero
// el contrato de fondo (editar/borrar/restaurar por fecha, cualquiera sea)
// es lo que hay que dejar probado para que no vuelva a regresionar en la capa
// de datos, sea cual sea la pantalla que la use.

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalRepository repo;
  final hoy = today();
  final haceTresDias = hoy.subtract(const Duration(days: 3));

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  group('editar', () {
    test('registrar de nuevo sobre un día pasado actualiza, no duplica', () async {
      await repo.logWeight(weightKg: 80, date: haceTresDias);
      await repo.logWeight(weightKg: 79.5, date: haceTresDias);

      expect(repo.weightLogs, hasLength(1));
      expect(repo.weightOn(haceTresDias)?.weightKg, 79.5);
    });
  });

  group('borrar y restaurar', () {
    test('borrar un registro de hace 3 días lo saca de la lista', () async {
      final log = await repo.logWeight(weightKg: 80, date: haceTresDias);

      await repo.deleteWeight(log.id);

      expect(repo.weightLogs, isEmpty);
      expect(repo.weightOn(haceTresDias), isNull);
    });

    test('borrar no afecta el registro de otro día', () async {
      final viejo = await repo.logWeight(weightKg: 80, date: haceTresDias);
      await repo.logWeight(weightKg: 78, date: hoy);

      await repo.deleteWeight(viejo.id);

      expect(repo.weightLogs, hasLength(1));
      expect(repo.weightOn(hoy)?.weightKg, 78);
    });

    test('restaurar devuelve el registro borrado', () async {
      final log = await repo.logWeight(weightKg: 80, date: haceTresDias);
      await repo.deleteWeight(log.id);

      await repo.restoreWeight(log.id);

      expect(repo.weightLogs, hasLength(1));
      expect(repo.weightOn(haceTresDias)?.weightKg, 80);
    });

    test('el peso actual ignora un registro borrado', () async {
      await repo.logWeight(weightKg: 80, date: haceTresDias);
      final ultimo = await repo.logWeight(weightKg: 79, date: hoy);

      await repo.deleteWeight(ultimo.id);

      expect(repo.currentWeightKg, 80);
    });
  });
}
