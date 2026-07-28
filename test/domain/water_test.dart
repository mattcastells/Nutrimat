import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:nutrimat/domain/models/water.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalRepository repo;
  final hoy = today();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  test('un día sin registro cuenta cero, no null', () {
    expect(repo.glassesOn(hoy), 0);
  });

  test('sumar vasos crea el registro del día', () async {
    await repo.addGlasses(hoy, 1);
    await repo.addGlasses(hoy, 1);
    expect(repo.glassesOn(hoy), 2);
    expect(repo.waterLogs, hasLength(1));
  });

  test('restar no baja de cero', () async {
    await repo.addGlasses(hoy, 1);
    await repo.addGlasses(hoy, -5);
    expect(repo.glassesOn(hoy), 0);
  });

  test('restar sin registro previo no crea un día vacío', () async {
    await repo.addGlasses(hoy, -1);
    expect(repo.waterLogs, isEmpty);
  });

  test('no se pasa del tope defensivo', () async {
    await repo.addGlasses(hoy, 999);
    expect(repo.glassesOn(hoy), WaterLog.maxGlasses);
  });

  test('cada día lleva su propia cuenta', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    await repo.addGlasses(hoy, 3);
    await repo.addGlasses(ayer, 7);
    expect(repo.glassesOn(hoy), 3);
    expect(repo.glassesOn(ayer), 7);
    expect(repo.waterLogs, hasLength(2));
  });

  test('cambiar el tamaño del vaso no reescribe el historial', () async {
    await repo.addGlasses(hoy, 4);
    await repo.setWaterGoal(glasses: 10, glassSizeMl: 500);

    // Los vasos registrados siguen siendo 4: lo que cambia es el equivalente
    // en ml que se muestra, no el dato guardado.
    expect(repo.glassesOn(hoy), 4);
    expect(repo.profile.waterGoalGlasses, 10);
    expect(repo.profile.glassSizeMl, 500);
  });

  test('la meta y el vaso quedan dentro de límites razonables', () async {
    await repo.setWaterGoal(glasses: 0, glassSizeMl: 5);
    expect(repo.profile.waterGoalGlasses, 1);
    expect(repo.profile.glassSizeMl, 50);

    await repo.setWaterGoal(glasses: 500, glassSizeMl: 99999);
    expect(repo.profile.waterGoalGlasses, WaterLog.maxGlasses);
    expect(repo.profile.glassSizeMl, 1000);
  });

  test('el registro sobrevive a guardar y volver a leer', () async {
    await repo.addGlasses(hoy, 5);
    final document = repo.store.toDocument();

    repo.store.restoreDocument(document);
    expect(repo.store.waterLogs, hasLength(1));
    expect(repo.store.waterLogs.first.glasses, 5);
  });
}
