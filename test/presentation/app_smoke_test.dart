// Smoke test de la app completa: monta `NutrimatApp` con su router real y
// recorre las decisiones de arranque de S-01 y S-02.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nutrimat/app.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:nutrimat/presentation/components/charts/calorie_ring.dart';
import 'package:nutrimat/presentation/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _boot({required bool seeded}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await LocalStore.open();
  if (seeded) store.seed();

  void Function() notify = () {};
  final repository = LocalRepository(store, onChanged: () => notify());
  final container = ProviderContainer(
    overrides: <Override>[repositoryProvider.overrideWithValue(repository)],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(appLocale);
  });

  setUp(() {
    // Un teléfono real, no los 800×600 por defecto: con el viewport chico la
    // bienvenida queda cortada y no se puede tocar el último botón.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1179, 2556);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('sin sesión, el splash lleva a la bienvenida', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: false);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NutrimatApp(),
      ),
    );
    await _settle(tester);

    expect(
      find.text('Comida y movimiento, en un solo número honesto'),
      findsOneWidget,
    );
    expect(find.text('Crear cuenta'), findsOneWidget);
    expect(find.text('Probar sin cuenta'), findsOneWidget);
  });

  testWidgets('con perfil completo, el splash lleva a Inicio', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: true);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NutrimatApp(),
      ),
    );
    await _settle(tester);

    expect(find.byType(CalorieRing), findsOneWidget);
    expect(find.text('Objetivo base'), findsOneWidget);
    // El shell muestra los cuatro destinos y el FAB.
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Historial'), findsOneWidget);
    expect(find.text('Progreso'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });

  testWidgets('"Probar sin cuenta" entra en modo demo y muestra Inicio', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: false);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NutrimatApp(),
      ),
    );
    await _settle(tester);

    final demoButton = find.text('Probar sin cuenta');
    await tester.ensureVisible(demoButton);
    await tester.pump();
    await tester.tap(demoButton);
    await tester.pump();
    // La escritura en la base local es asíncrona de verdad: hay que dejar
    // correr el reloj real antes de seguir pumpeando.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _settle(tester);

    // Modo demo (D-15): usuario local anónimo con la app entera funcionando.
    expect(find.byType(CalorieRing), findsOneWidget);
    expect(container.read(profileProvider).isDemo, isTrue);
  });

  testWidgets('se puede navegar a Historial, Progreso y Perfil', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _boot(seeded: true);
    });
    addTearDown(() => container.dispose());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NutrimatApp(),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Historial'));
    await _settle(tester);
    expect(find.textContaining('días coinciden'), findsOneWidget);

    await tester.tap(find.text('Progreso'));
    await _settle(tester);
    expect(find.text('Promedio diario'), findsOneWidget);
    expect(find.text('Adherencia'), findsOneWidget);

    await tester.tap(find.text('Perfil'));
    await _settle(tester);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.text('Objetivo vigente'), findsOneWidget);
  });
}
