// El informe en PDF: primero que las cuentas sean honestas, después que el
// archivo se genere de verdad.
//
// Lo primero importa porque un promedio mal calculado en un informe es peor que
// no tener informe: nadie lo va a revisar contra el historial. La regla es una
// sola y se prueba de tres maneras — **un día sin registrar no es un día de
// cero**, así que no entra en ningún promedio.
//
// Lo segundo importa porque todo el dibujo del PDF vive fuera del análisis
// estático: una fuente que no está en los assets o un gráfico con cero puntos
// no se ven hasta que alguien toca "Generar".

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/local/pdf_report.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:nutrimat/domain/enums/enums.dart';
import 'package:nutrimat/domain/models/meal.dart';
import 'package:nutrimat/domain/models/summaries.dart';
import 'package:nutrimat/domain/services/report_builder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // El informe escribe fechas largas ("martes 12 de agosto"), y eso pide los
  // símbolos del locale igual que en el arranque de la app.
  setUpAll(() => initializeDateFormatting(appLocale));

  late LocalRepository repo;
  final hoy = today();

  Meal comida(DateTime fecha, {int kcal = 600, double proteina = 40}) => Meal(
    id: 'm-${isoDate(fecha)}',
    slot: MealSlot.lunch,
    loggedAt: fecha,
    localDate: dateOnly(fecha),
    items: <MealItem>[
      MealItem(
        id: 'i-${isoDate(fecha)}',
        name: 'Milanesa con puré',
        quantity: 1,
        unit: 'porcion',
        kcal: kcal,
        proteinG: proteina,
        carbsG: 60,
        fatG: 20,
        position: 0,
      ),
    ],
    source: MealSource.manual,
    createdAt: fecha,
    updatedAt: fecha,
  );

  /// El mismo armado que hace la pantalla, para que el test cubra ese camino y
  /// no uno paralelo.
  NutritionReport informe({int days = 30}) {
    final to = today();
    final from = to.subtract(Duration(days: days - 1));
    return ReportBuilder.build(
      profile: repo.profile,
      goal: repo.currentGoalOrNull,
      progress: repo.progress(from: from, to: to),
      days: <DailySummary>[
        for (var i = 0; i < days; i++) repo.daily(from.add(Duration(days: i))),
      ],
      glassesOn: repo.glassesOn,
      sleepMinutesOn: (date) => repo.sleepOn(date)?.minutes,
      measurementsOf: repo.measurements,
      generatedAt: DateTime(2026, 8, 12),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
    await repo.signIn('yo@nutrimat.test');
  });

  group('promedios', () {
    test('sin nada registrado no hay promedios que mostrar', () {
      final r = informe();
      expect(r.daysWithRecords, 0);
      expect(r.calories.hasData, isFalse);
      expect(r.hasEnoughData, isFalse);
      expect(ReportBuilder.headline(r), isNull);
    });

    test('el promedio sale de los días con registro, no del período', () async {
      // Tres días de 600 kcal en un período de 30. El promedio es 600, no 60:
      // los 27 días que no se cargaron no son días de cero calorías.
      for (var i = 0; i < 3; i++) {
        await repo.saveMeal(comida(hoy.subtract(Duration(days: i))));
      }

      final r = informe();
      expect(r.daysWithRecords, 3);
      expect(r.calories.value, 600);
      expect(r.calories.days, 3);
      expect(r.coveragePct, 10);
    });

    test('los macros se promedian sobre los mismos días que las calorías',
        () async {
      for (var i = 0; i < 3; i++) {
        await repo.saveMeal(comida(hoy.subtract(Duration(days: i))));
      }

      final r = informe();
      final proteina = r.nutrients.firstWhere((n) => n.label == 'Proteínas');
      expect(proteina.average.value, 40);
      expect(proteina.average.days, r.calories.days);
    });

    test('el agua se promedia sobre los días que la tienen', () async {
      await repo.saveMeal(comida(hoy));
      await repo.saveMeal(comida(hoy.subtract(const Duration(days: 1))));
      // Un solo día con agua: el promedio son esos 8 vasos, no 8 repartidos
      // entre los dos días con comida.
      await repo.addGlasses(hoy, 8);

      final r = informe();
      expect(r.water.value, 8);
      expect(r.water.days, 1);
    });

    test('con dos pesos hay diferencia y con uno solo no hay curva', () async {
      await repo.logWeight(
        weightKg: 82,
        date: hoy.subtract(const Duration(days: 20)),
      );
      var r = informe();
      expect(r.weight!.first, 82);
      expect(r.weight!.delta, 0);

      await repo.logWeight(weightKg: 80.4, date: hoy);
      r = informe();
      expect(r.weight!.last, 80.4);
      expect(r.weight!.delta, closeTo(-1.6, 0.001));
    });
  });

  group('extremos y objetivo', () {
    test('con un solo día registrado no hay extremos que comparar', () async {
      await repo.saveMeal(comida(hoy));
      expect(ReportBuilder.calorieExtremes(informe()), isNull);
    });

    test('los extremos son el día más bajo y el más alto', () async {
      await repo.saveMeal(comida(hoy, kcal: 500));
      await repo.saveMeal(
        comida(hoy.subtract(const Duration(days: 1)), kcal: 2400),
      );

      final extremos = ReportBuilder.calorieExtremes(informe());
      expect(extremos!.$1.consumed, 500);
      expect(extremos.$2.consumed, 2400);
    });

    test('un día sin registro no cuenta como día dentro del objetivo',
        () async {
      await repo.saveMeal(comida(hoy, kcal: repo.currentGoalOrNull!.baseCalorieTarget));
      expect(ReportBuilder.daysWithinTarget(informe()), 1);
    });
  });

  group('el archivo', () {
    test('se genera un PDF de verdad, en los dos temas', () async {
      for (var i = 0; i < 5; i++) {
        final dia = hoy.subtract(Duration(days: i));
        await repo.saveMeal(comida(dia, kcal: 1800 + i * 60));
        await repo.logWeight(weightKg: 82 - i * 0.2, date: dia);
      }
      await repo.addGlasses(hoy, 6);

      for (final dark in <bool>[true, false]) {
        final bytes = await PdfReport(report: informe(), dark: dark).build();
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        // Un PDF con las tres fuentes embebidas y dos gráficos no baja de unos
        // cuantos kilobytes: si saliera de 2 kB sería una hoja en blanco.
        expect(bytes.length, greaterThan(20000));
      }
    });

    test('un período sin ningún registro también genera archivo', () async {
      // Nadie debería llegar acá —el botón se apaga sin registros— pero un
      // gráfico con cero puntos no puede tirar una excepción.
      final bytes = await PdfReport(report: informe(), dark: true).build();
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('con un solo peso no se intenta dibujar la curva', () async {
      await repo.saveMeal(comida(hoy));
      await repo.logWeight(weightKg: 80, date: hoy);
      final bytes = await PdfReport(report: informe(), dark: true).build();
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
