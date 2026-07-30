// Qué muestra el widget de la pantalla de inicio del teléfono.
//
// El widget lo dibuja el launcher, con la app cerrada, leyendo lo último que la
// app dejó guardado. Eso trae un riesgo propio: un número viejo mostrado como
// si fuera de hoy. La defensa está partida en dos y las dos mitades se prueban
// donde viven — acá, que el texto y la **fecha** salgan del cálculo del día; en
// Kotlin, que un dato de otra fecha no se muestre.

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/core/utils/dates.dart';
import 'package:nutrimat/data/local/home_widget_publisher.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:nutrimat/domain/enums/enums.dart';
import 'package:nutrimat/domain/models/activity.dart';
import 'package:nutrimat/domain/models/goal.dart';
import 'package:nutrimat/domain/models/meal.dart';
import 'package:nutrimat/domain/models/summaries.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
  });

  Future<void> conObjetivo(int kcal) => repo.saveGoal(
    Goal(
      id: 'g-1',
      goalType: GoalType.maintain,
      rateKgPerWeek: 0,
      baseCalorieTarget: kcal,
      targetMethod: TargetMethod.manual,
      proteinG: 120,
      carbsG: 220,
      fatG: 70,
      macroMethod: 'default',
      startsOn: today().subtract(const Duration(days: 1)),
    ),
  );

  test('el dato lleva la fecha del día que describe', () async {
    await conObjetivo(2000);
    final payload = HomeWidgetPublisher.payloadFor(repo.daily(today()));

    // Sin esto el widget no puede saber si lo que tiene guardado sigue valiendo.
    expect(payload['date'], isoDate(today()));
  });

  test('sin comidas, quedan todas las calorías del objetivo', () async {
    await conObjetivo(2000);
    final payload = HomeWidgetPublisher.payloadFor(repo.daily(today()));

    expect(payload['value'], '2.000');
    expect(payload['label'], 'kcal restantes');
    expect(payload['detail'], 'Comió 0 de 2.000');
  });

  test('pasarse del objetivo se cuenta, no se reta', () async {
    await conObjetivo(2000);
    await repo.saveMeal(
      Meal(
        id: 'm-1',
        slot: MealSlot.lunch,
        loggedAt: DateTime.now(),
        localDate: today(),
        items: <MealItem>[
          const MealItem(
            id: 'i-1',
            name: 'Asado',
            quantity: 400,
            unit: 'g',
            kcal: 2300,
            proteinG: 90,
            carbsG: 0,
            fatG: 180,
            position: 0,
          ),
        ],
        source: MealSource.manual,
        syncStatus: SyncStatus.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final payload = HomeWidgetPublisher.payloadFor(repo.daily(today()));

    // El valor va en positivo y lo que cambia es la palabra: las mismas que usa
    // Inicio, sin rojo ni reto (D-17).
    expect(payload['value'], '300');
    expect(payload['label'], 'kcal de más');
  });

  test('sin objetivo no se inventa un número', () {
    // La app siempre tiene un objetivo de referencia
    // (`LocalRepository.defaultCalorieTarget`), así que este día no lo produce
    // el repositorio: es la guarda. Con `baseTarget` en 0, "te quedan −1.123"
    // sería un número que no significa nada, y el widget no tiene pantalla
    // donde aclararlo.
    final sinObjetivo = DailySummary(
      date: today(),
      baseTarget: 0,
      consumedKcal: 1123,
      exerciseEstimatedKcal: 0,
      exerciseAppliedKcal: 0,
      creditPercentage: 0,
      creditEnabled: false,
      macros: const MacroSet(
        protein: MacroProgress(current: 0, target: 0),
        carbs: MacroProgress(current: 0, target: 0),
        fat: MacroProgress(current: 0, target: 0),
      ),
      meals: const <Meal>[],
      activities: const <Activity>[],
      activityTotals: const ActivityTotals(minutes: 0, sessions: 0),
      isRestDay: false,
    );

    final payload = HomeWidgetPublisher.payloadFor(sinObjetivo);

    expect(payload['value'], '—');
    expect(payload['label'], 'Sin objetivo configurado');
    expect(payload['detail'], 'Abrí Nutrimat para elegir uno');
  });

  test('publicar sin plataforma nativa no revienta', () async {
    // En un test no hay canal del lado de Android. El widget es una comodidad:
    // no puede hacer fallar el registro de una comida.
    await conObjetivo(2000);
    await const HomeWidgetPublisher().publish(repo.daily(today()));
  });
}
