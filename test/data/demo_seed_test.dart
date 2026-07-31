// Los datos de ejemplo no pueden llegar a una compilación de verdad.
//
// El caso real: alguien creó su cuenta y se encontró adentro con el historial
// de "Camila" —treinta días de comidas, un peso de 100 kg y dos actividades por
// día— que no era de nadie. Con la sesión abierta eso se reconcilia contra las
// tablas y sube, así que a partir de ahí los datos inventados y los reales
// viven en la misma cuenta y no se distinguen.
//
// Hay tres cerrojos y acá se prueban los tres, porque cada uno tapa un camino
// distinto: sembrar, arrancar con lo ya sembrado, y entrar a una cuenta desde
// una sesión de prueba.

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/core/config/feature_flags.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/mock/seed.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalRepository> _boot() async {
  final store = await LocalStore.open();
  return LocalRepository(store, onChanged: () {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => FeatureFlags.seededDemoDataOverride = null);

  group('la siembra', () {
    test('no hace nada cuando no está permitida', () async {
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final store = await LocalStore.open();
      store.seed();

      expect(store.profile, isNull);
      expect(store.meals, isEmpty);
      expect(store.weightLogs, isEmpty);
      expect(store.activities, isEmpty);
    });

    test('sigue andando mientras se desarrolla sin servidor', () async {
      FeatureFlags.seededDemoDataOverride = true;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final store = await LocalStore.open();
      store.seed();

      expect(store.profile?.id, demoProfileId);
      expect(store.meals, isNotEmpty);
    });
  });

  group('un teléfono que ya tiene los datos sembrados', () {
    test('los pierde al arrancar una compilación que no puede sembrar', () async {
      // Un teléfono con la versión anterior: sembró y guardó.
      FeatureFlags.seededDemoDataOverride = true;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final antes = await _boot();
      await antes.startDemoSession(seeded: true);
      expect(antes.store.meals, isNotEmpty);

      // La versión de ahora abre lo mismo.
      FeatureFlags.seededDemoDataOverride = false;
      final despues = await _boot();

      expect(despues.hasSession, isFalse);
      expect(despues.store.meals, isEmpty);
      expect(despues.store.weightLogs, isEmpty);
      expect(despues.hasUserData, isFalse);
    });

    test('un documento de verdad no se toca', () async {
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final antes = await _boot();
      await antes.signIn('yo@nutrimat.test');
      await antes.logWeight(weightKg: 72, date: DateTime.now());

      final despues = await _boot();

      expect(despues.hasSession, isTrue);
      expect(despues.profile.email, 'yo@nutrimat.test');
      expect(despues.weightLogs, hasLength(1));
    });
  });

  group('entrar a una cuenta desde el modo de prueba', () {
    test('no se lleva puesto lo que había en la sesión anónima', () async {
      FeatureFlags.seededDemoDataOverride = true;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repo = await _boot();
      await repo.startDemoSession(seeded: true);
      expect(repo.allMeals, isNotEmpty, reason: 'la prueba parte de datos sembrados');

      // El camino que lo provocaba: probar sin cuenta y después entrar.
      await repo.signIn('elias@nutrimat.test');

      expect(repo.profile.email, 'elias@nutrimat.test');
      expect(repo.profile.isDemo, isFalse);
      expect(repo.profile.displayName, isNull, reason: 'ni el nombre de la demo');
      expect(repo.allMeals, isEmpty);
      expect(repo.allActivities, isEmpty);
      expect(repo.weightLogs, isEmpty);
      expect(repo.hasUserData, isFalse);
    });

    test('una sesión con cuenta sí conserva lo suyo al reentrar', () async {
      FeatureFlags.seededDemoDataOverride = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repo = await _boot();
      await repo.signIn('yo@nutrimat.test');
      await repo.logWeight(weightKg: 72, date: DateTime.now());

      await repo.signIn('yo@nutrimat.test');

      expect(repo.weightLogs, hasLength(1));
    });
  });
}
