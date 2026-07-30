// El día de un pal se lee por categorías y en un orden fijo: comida, agua,
// deporte y sueño. Y solo aparece lo que esa persona decidió compartir.
//
// El orden se prueba porque es la mitad del pedido: si una categoría se corre
// de lugar según lo que haya cargado ese día, hay que volver a leer todo cada
// vez que se abre la pantalla.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nutrimat/core/theme/app_theme.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/domain/enums/enums.dart';
import 'package:nutrimat/domain/models/pal.dart';
import 'package:nutrimat/domain/models/sleep.dart';
import 'package:nutrimat/presentation/screens/pals/pal_day_screen.dart';

const String _userId = 'pal-1';

PalDay _day({
  int? waterGlasses,
  int? sleepMinutes,
  List<PalActivity> activities = const <PalActivity>[],
  int activityCount = 0,
  int activityMinutes = 0,
}) => PalDay(
  userId: _userId,
  date: today(),
  meals: const <PalMeal>[
    PalMeal(slot: MealSlot.breakfast, name: 'Sandwich de miga', kcal: 598),
    PalMeal(slot: MealSlot.lunch, name: 'Arroz', kcal: 525),
  ],
  activityMinutes: activityMinutes,
  activityCount: activityCount,
  activities: activities,
  waterGlasses: waterGlasses,
  sleepMinutes: sleepMinutes,
  sleepQuality: sleepMinutes == null ? null : SleepQuality.good,
);

Widget _wrap(PalDay day) => ProviderScope(
  overrides: <Override>[
    palDayProvider((
      userId: _userId,
      date: today(),
    )).overrideWith((ref) => Future<PalDay?>.value(day)),
  ],
  child: MaterialApp(
    theme: NmAppTheme.dark(),
    locale: const Locale('es', 'AR'),
    home: const PalDayScreen(userId: _userId, name: 'Gordito #1'),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 700));
}

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(appLocale);
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 2.75;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('con todo compartido, el orden es comida, agua, deporte, sueño', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _day(
          waterGlasses: 6,
          sleepMinutes: 450,
          activityCount: 1,
          activityMinutes: 40,
          activities: const <PalActivity>[
            PalActivity(name: 'Caminata', minutes: 40, kcal: 180),
          ],
        ),
      ),
    );
    await _settle(tester);

    expect(_y(tester, 'COMIDA'), lessThan(_y(tester, 'AGUA')));
    expect(_y(tester, 'AGUA'), lessThan(_y(tester, 'DEPORTE')));
    expect(_y(tester, 'DEPORTE'), lessThan(_y(tester, 'SUEÑO')));

    // Las comidas quedan adentro de Comida, por momento del día.
    expect(_y(tester, 'COMIDA'), lessThan(_y(tester, 'Desayuno')));
    expect(_y(tester, 'Desayuno'), lessThan(_y(tester, 'Almuerzo')));
    expect(_y(tester, 'Almuerzo'), lessThan(_y(tester, 'AGUA')));

    expect(tester.takeException(), isNull);
  });

  testWidgets('lo que no se comparte no deja su categoría vacía', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_day()));
    await _settle(tester);

    expect(find.text('AGUA'), findsNothing);
    expect(find.text('SUEÑO'), findsNothing);
    // El agregado de actividad se comparte siempre, así que Deporte está —y
    // dice que todavía no se movió, que también es información del día.
    expect(find.text('DEPORTE'), findsOneWidget);
    expect(find.text('Todavía no'), findsWidgets);
    expect(find.text('COMIDA'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
