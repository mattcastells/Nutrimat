// El aviso de versión nueva al abrir la app.
//
// La app se distribuye por fuera de Play Store, así que nadie avisa que salió
// una versión: hasta ahora había que acordarse de entrar a Configuración →
// Actualizaciones, y el resultado fue gente corriendo versiones de meses atrás
// sin enterarse. Lo que se prueba acá son los frenos, porque un aviso que
// molesta se aprende a descartar sin leer —justo cuando llegue el que importa.

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/data/local/update_prompt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('la primera vez se consulta', () async {
    final store = await UpdatePromptStore.open();
    expect(store.shouldCheck(), isTrue);
  });

  test('recién consultada no se vuelve a consultar', () async {
    final store = await UpdatePromptStore.open();
    final ahora = DateTime(2026, 7, 31, 16, 17);
    await store.markChecked(now: ahora);

    expect(store.shouldCheck(now: ahora), isFalse);
    expect(
      store.shouldCheck(now: ahora.add(const Duration(hours: 5))),
      isFalse,
      reason: 'abrir la app diez veces en una tarde es lo normal',
    );
    expect(
      store.shouldCheck(now: ahora.add(UpdatePromptStore.checkInterval)),
      isTrue,
    );
  });

  test('lo consultado sobrevive a cerrar la app', () async {
    final ahora = DateTime(2026, 7, 31, 16, 17);
    await (await UpdatePromptStore.open()).markChecked(now: ahora);

    final despues = await UpdatePromptStore.open();

    expect(despues.shouldCheck(now: ahora), isFalse);
    expect(despues.lastCheck, ahora);
  });

  test('"ahora no" calla esa versión y solo esa', () async {
    final store = await UpdatePromptStore.open();
    await store.postpone('1.11.0');

    expect(store.isPostponed('1.11.0'), isTrue);
    // La que viene vuelve a avisar sola: el "no" era sobre una versión, no
    // sobre las actualizaciones.
    expect(store.isPostponed('1.11.1'), isFalse);
    expect(store.isPostponed('1.12.0'), isFalse);
  });

  test('postergar dos veces deja la última, no acumula', () async {
    final store = await UpdatePromptStore.open();
    await store.postpone('1.11.0');
    await store.postpone('1.12.0');

    expect(store.isPostponed('1.12.0'), isTrue);
    expect(store.isPostponed('1.11.0'), isFalse);
  });

  test('una hora guardada ilegible no rompe: se consulta', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'nutrimat.updates.last_check': 'no es una fecha',
    });
    final store = await UpdatePromptStore.open();

    expect(store.lastCheck, isNull);
    expect(store.shouldCheck(), isTrue);
  });
}
