// El alta guiada, caminada de punta a punta.
//
// Es obligatoria: mientras `needsOnboarding` sea `true` el router no deja entrar
// a Inicio. Eso la vuelve el lugar más caro para tener un bug — si un paso no
// deja avanzar, la persona no queda con una pantalla fea, queda **afuera de la
// app**, sin más salida que cerrar sesión.
//
// `onboarding_test.dart` prueba la regla (quién tiene que completar); esto
// prueba que se pueda.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nutrimat/core/router/routes.dart';
import 'package:nutrimat/core/theme/app_theme.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/data/local/local_auth_gateway.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:nutrimat/domain/enums/enums.dart';
import 'package:nutrimat/presentation/providers/app_providers.dart';
import 'package:nutrimat/presentation/providers/auth_providers.dart';
import 'package:nutrimat/presentation/screens/auth/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProviderContainer, LocalRepository)> _boot({
  DateTime? birthDate,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // El repositorio avisa de cada escritura por el contador de revisión, igual
  // que en `bootstrap`. No es detalle de armado: sin ese cable, el peso que se
  // registra en el paso 2 no lo ve `currentWeightProvider` en el paso 4, y el
  // objetivo sale `manual` en vez de calculado — que es exactamente el bug que
  // esta pantalla existe para no tener.
  void Function() notify = () {};
  final repo = LocalRepository(await LocalStore.open(), onChanged: () => notify());
  await repo.signIn('elias@nutrimat.test');
  if (birthDate != null) {
    await repo.updateProfile(repo.profile.copyWith(birthDate: birthDate));
  }
  final container = ProviderContainer(
    overrides: <Override>[
      repositoryProvider.overrideWithValue(repo),
      authGatewayProvider.overrideWithValue(LocalAuthGateway()),
    ],
  );
  notify = () => container.read(appRevisionProvider.notifier).bump();
  return (container, repo);
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    routerConfig: GoRouter(
      initialLocation: Routes.onboarding,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.onboarding,
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: Routes.home,
          builder: (context, state) => const Scaffold(body: Text('INICIO')),
        ),
        GoRoute(
          path: Routes.welcome,
          builder: (context, state) => const Scaffold(body: Text('BIENVENIDA')),
        ),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _continuar(WidgetTester tester, String etiqueta) async {
  await tester.ensureVisible(find.text(etiqueta));
  await tester.pump();
  await tester.tap(find.text(etiqueta));
  await tester.pump();
  // Cada paso escribe en la base local antes de avanzar, y esa escritura
  // necesita tiempo real: bajo el reloj falso el `await` no resuelve nunca.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(appLocale);
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1179, 2556);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('sin fecha de nacimiento no se puede pasar del primer paso', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      (container, _) = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    expect(find.text('Paso 1 de 4'), findsOneWidget);
    await _continuar(tester, 'Continuar');

    // Sigue en el primero: sin edad no hay Mifflin-St Jeor y el paso no se
    // puede dar por cumplido.
    expect(find.text('Paso 1 de 4'), findsOneWidget);
  });

  testWidgets('los cuatro pasos se caminan y dejan a la persona en Inicio', (
    tester,
  ) async {
    late ProviderContainer container;
    late LocalRepository repo;
    await tester.runAsync(() async {
      (container, repo) = await _boot(birthDate: DateTime(1990, 4, 12));
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // ── Paso 1: sexo y nacimiento ──────────────────────────────────────
    expect(find.text('Empecemos por vos'), findsOneWidget);
    await tester.tap(find.text('Masculino'));
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    // ── Paso 2: altura y peso ──────────────────────────────────────────
    expect(find.text('Paso 2 de 4'), findsOneWidget);
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), '178');
    await tester.enterText(campos.at(1), '82');
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    expect(find.text('Paso 3 de 4'), findsOneWidget);
    expect(repo.profile.heightCm, 178);
    // El peso entra como registro con fecha, no como campo del perfil: es lo
    // que hace que el primer punto de la curva de progreso sea el de hoy.
    expect(repo.currentWeightKg, 82);
    expect(repo.weightOn(today()), isNotNull);

    // ── Paso 3: nivel de actividad ─────────────────────────────────────
    await tester.tap(find.text(ActivityLevel.light.label));
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    // ── Paso 4: objetivo ───────────────────────────────────────────────
    expect(find.text('Paso 4 de 4'), findsOneWidget);
    expect(find.text('¿Qué buscás?'), findsOneWidget);
    expect(repo.profile.activityLevel, ActivityLevel.light);

    // Viene con "Mantener" marcado —es el objetivo de referencia que crea el
    // alta— así que elegir otro es un toque de verdad y no una formalidad.
    expect(find.text(GoalType.maintain.label), findsOneWidget);
    await tester.ensureVisible(find.text(GoalType.lose.label));
    await tester.pump();
    await tester.tap(find.text(GoalType.lose.label));
    await _settle(tester);
    await _continuar(tester, 'Empezar');

    expect(find.text('INICIO'), findsOneWidget);

    // Y el objetivo salió del cálculo, no del valor de referencia: es la razón
    // entera por la que esta pantalla existe.
    final goal = repo.currentGoalOrNull;
    expect(goal, isNotNull);
    expect(goal!.goalType, GoalType.lose);
    expect(goal.targetMethod, TargetMethod.calculated);
    expect(goal.bmrKcal, isNotNull);
    expect(repo.needsOnboarding, isFalse);
  });

  testWidgets('volver atrás conserva lo cargado', (tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      (container, _) = await _boot(birthDate: DateTime(1990, 4, 12));
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);
    await _continuar(tester, 'Continuar');

    await tester.enterText(find.byType(TextField).at(0), '178');
    await _settle(tester);

    await tester.tap(find.text('Atrás'));
    await _settle(tester);
    expect(find.text('Paso 1 de 4'), findsOneWidget);

    await _continuar(tester, 'Continuar');

    // La altura sigue escrita: si volver borrara lo cargado, "Atrás" sería una
    // trampa y nadie lo tocaría dos veces.
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      '178',
    );
  });

  testWidgets('hay salida: no se queda nadie encerrado', (tester) async {
    late ProviderContainer container;
    late LocalRepository repo;
    await tester.runAsync(() async {
      (container, repo) = await _boot();
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await _settle(tester);

    // Sin esto, quien no quiera dar estos datos no tiene forma de salir: el
    // router lo devuelve acá en cada arranque y la única salida sería
    // desinstalar.
    await tester.ensureVisible(find.text('Salir'));
    await tester.pump();
    await tester.tap(find.text('Salir'));
    await _settle(tester);

    await tester.tap(find.text('Salir').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await _settle(tester);

    expect(find.text('BIENVENIDA'), findsOneWidget);
    expect(repo.hasSession, isFalse);
  });
}
