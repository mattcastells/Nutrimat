import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:nutrimat/domain/models/sleep.dart';
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

  test('un día sin registro devuelve null', () {
    expect(repo.sleepOn(hoy), isNull);
  });

  test('registrar de nuevo el mismo día actualiza, no duplica', () async {
    await repo.logSleep(
      date: hoy,
      minutes: 420,
      quality: SleepQuality.ok,
    );
    await repo.logSleep(
      date: hoy,
      minutes: 480,
      quality: SleepQuality.good,
    );

    expect(repo.sleepLogs, hasLength(1));
    expect(repo.sleepOn(hoy)!.minutes, 480);
    expect(repo.sleepOn(hoy)!.quality, SleepQuality.good);
  });

  test('el id se conserva al actualizar', () async {
    await repo.logSleep(date: hoy, minutes: 420, quality: SleepQuality.ok);
    final first = repo.sleepOn(hoy)!.id;

    await repo.logSleep(date: hoy, minutes: 500, quality: SleepQuality.ok);
    expect(repo.sleepOn(hoy)!.id, first);
  });

  test('valores imposibles se recortan', () async {
    // 40 minutos o 30 horas son un error de carga, no una noche.
    await repo.logSleep(date: hoy, minutes: 40, quality: SleepQuality.ok);
    expect(repo.sleepOn(hoy)!.minutes, SleepLog.minMinutes);

    await repo.logSleep(date: hoy, minutes: 1800, quality: SleepQuality.ok);
    expect(repo.sleepOn(hoy)!.minutes, SleepLog.maxMinutes);
  });

  test('cada día lleva su propia noche', () async {
    final ayer = hoy.subtract(const Duration(days: 1));
    await repo.logSleep(date: hoy, minutes: 420, quality: SleepQuality.ok);
    await repo.logSleep(date: ayer, minutes: 300, quality: SleepQuality.bad);

    expect(repo.sleepOn(hoy)!.minutes, 420);
    expect(repo.sleepOn(ayer)!.minutes, 300);
    expect(repo.sleepLogs, hasLength(2));
  });

  test('la duración se muestra en horas y minutos', () {
    SleepLog log(int minutes) => SleepLog(
      id: 'x',
      localDate: hoy,
      minutes: minutes,
      quality: SleepQuality.ok,
      loggedAt: hoy,
    );
    expect(log(480).label, '8 h');
    expect(log(450).label, '7 h 30');
  });

  test('sobrevive a guardar y volver a leer', () async {
    await repo.logSleep(
      date: hoy,
      minutes: 465,
      quality: SleepQuality.great,
    );
    repo.store.restoreDocument(repo.store.toDocument());

    expect(repo.sleepOn(hoy)!.minutes, 465);
    expect(repo.sleepOn(hoy)!.quality, SleepQuality.great);
  });

  test('un respaldo viejo sin sueño no rompe nada', () async {
    final document = repo.store.toDocument()..remove('sleepLogs');
    repo.store.restoreDocument(document);
    expect(repo.sleepLogs, isEmpty);
  });
}
