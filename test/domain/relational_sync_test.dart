// La persistencia relacional: que lo que sube sea lo que baja.
//
// Lo que se prueba acá no es "el cliente llama a Supabase" —eso necesita un
// servidor— sino el contrato que sí podemos verificar en frío: que la puerta
// no deje escribir antes de decidir qué hacer con lo remoto, que un teléfono
// vacío no pise la base, y que el documento que devuelve la lectura tenga la
// forma que `LocalStore` sabe leer. Esa forma es el punto de todo: si se
// desalinea, los datos vuelven mutilados y nadie se entera.

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/core/error/app_error.dart';
import 'package:nutrimat/data/local/local_store.dart';
import 'package:nutrimat/data/remote/relational_sync_client.dart';
import 'package:nutrimat/data/repositories/local_repository.dart';
import 'package:nutrimat/domain/enums/enums.dart';
import 'package:nutrimat/domain/models/meal.dart';
import 'package:nutrimat/domain/repositories/auth_gateway.dart';
import 'package:nutrimat/domain/services/relational_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth implements AuthGateway {
  AuthAccount? account = const AuthAccount(id: 'u1', email: 'yo@test');

  @override
  AuthAccount? get currentAccount => account;
  @override
  bool get hasSession => account != null;
  @override
  Stream<AuthAccount?> get changes => const Stream<AuthAccount?>.empty();
  @override
  Future<AuthAccount> signIn({required String email, required String password}) =>
      throw UnimplementedError();
  @override
  Future<AuthAccount?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();
  @override
  Future<void> signOut() async => account = null;
  @override
  Future<void> sendPasswordReset(String email) async {}
}

class _FakeClient implements RelationalSyncClient {
  int pushes = 0;
  Map<String, dynamic>? paraTraer;
  AppError? fallaCon;

  @override
  Future<Map<String, int>> push({
    required String userId,
    required LocalStore store,
  }) async {
    if (fallaCon != null) throw fallaCon!;
    pushes++;
    return <String, int>{'meals': store.meals.length};
  }

  @override
  Future<Map<String, dynamic>?> pull({
    required String userId,
    required LocalStore store,
  }) async {
    if (fallaCon != null) throw fallaCon!;
    return paraTraer;
  }

  @override
  Future<Map<String, int>> counts(String userId) async => <String, int>{};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late LocalRepository repo;
  late _FakeClient client;
  late _FakeAuth auth;

  RelationalSyncService build() => RelationalSyncService(
    client: client,
    auth: auth,
    store: store,
    debounce: Duration.zero,
  );

  Future<void> cargarUnaComida() async {
    await repo.saveMeal(
      Meal(
        id: 'm1',
        slot: MealSlot.lunch,
        loggedAt: DateTime(2026, 7, 29, 13),
        localDate: DateTime(2026, 7, 29),
        name: 'Milanesa',
        items: const <MealItem>[
          MealItem(
            id: 'i1',
            name: 'Milanesa',
            quantity: 1,
            unit: 'unidad',
            kcal: 300,
            proteinG: 20,
            carbsG: 15,
            fatG: 16,
            position: 0,
          ),
        ],
        source: MealSource.manual,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
    await repo.signIn('yo@test');
    client = _FakeClient();
    auth = _FakeAuth();
  });

  group('la puerta antes de escribir', () {
    test('sin abrirla no escribe nada', () async {
      await cargarUnaComida();
      final service = build();

      service.markDirty();
      await service.push();

      expect(client.pushes, 0);
      service.dispose();
    });

    test('se abre aunque la lectura falle por red', () async {
      // Si quedara cerrada por un problema de conexión, la app dejaría de
      // persistir para siempre y en silencio.
      client.fallaCon = const AppError(
        code: ApiErrorCode.offline,
        message: 'sin conexión',
      );
      final service = build();

      await service.openAfterPull(localIsEmpty: true, apply: (_) async {});

      expect(service.canPush, isTrue);
      service.dispose();
    });

    test('con datos locales no trae nada de la base', () async {
      await cargarUnaComida();
      client.paraTraer = <String, dynamic>{'profile': <String, dynamic>{}};
      final service = build();
      var aplicado = false;

      final traido = await service.openAfterPull(
        localIsEmpty: false,
        apply: (_) async => aplicado = true,
      );

      expect(traido, isFalse);
      expect(aplicado, isFalse, reason: 'pisar lo local es el mismo error al revés');
      service.dispose();
    });
  });

  group('un teléfono vacío no vacía la base', () {
    test('sin datos locales no escribe, aunque la puerta esté abierta', () async {
      final service = build();
      await service.openAfterPull(localIsEmpty: true, apply: (_) async {});

      await service.push();

      expect(client.pushes, 0);
      service.dispose();
    });

    test('con un registro real sí escribe', () async {
      final service = build();
      await service.openAfterPull(localIsEmpty: true, apply: (_) async {});
      await cargarUnaComida();

      await service.push();

      expect(client.pushes, 1);
      expect(service.state, isA<SyncIdle>());
      service.dispose();
    });
  });

  group('el documento que devuelve la base lo entiende el store', () {
    test('una comida traída de las tablas se lee entera', () async {
      // Es el contrato central: la lectura relacional devuelve la misma forma
      // que el documento local, así que la reconstruye el mismo lector
      // tolerante y no hay un segundo lugar donde equivocarse.
      client.paraTraer = <String, dynamic>{
        'schemaVersion': LocalStore.schemaVersion,
        'profile': <String, dynamic>{
          'id': 'u1',
          'biologicalSex': 'male',
          'activityLevel': 'moderate',
          'timezone': 'America/Argentina/Buenos_Aires',
          'unitSystem': 'metric',
          'themeMode': 'system',
          'locale': 'es',
          'exerciseCreditPercentage': 0,
          'exerciseCreditEnabled': true,
          'showNetCalories': false,
          'createdAt': '2026-07-01T10:00:00.000',
          'updatedAt': '2026-07-01T10:00:00.000',
        },
        'meals': <dynamic>[
          <String, dynamic>{
            'id': 'm9',
            'slot': 'dinner',
            'loggedAt': '2026-07-29T21:00:00.000Z',
            'localDate': '2026-07-29',
            'name': 'Guiso',
            'source': 'manual',
            'isFavorite': false,
            'syncStatus': 'synced',
            'createdAt': '2026-07-29T21:00:00.000Z',
            'updatedAt': '2026-07-29T21:00:00.000Z',
            'items': <dynamic>[
              <String, dynamic>{
                'id': 'i9',
                'name': 'Guiso de lentejas',
                'quantity': 1,
                'unit': 'porcion',
                'kcal': 420,
                'proteinG': 18,
                'carbsG': 60,
                'fatG': 10,
                'position': 0,
              },
            ],
          },
        ],
        'weightLogs': <dynamic>[
          <String, dynamic>{
            'id': 'w9',
            'weightKg': 81.4,
            'localDate': '2026-07-29',
            'loggedAt': '2026-07-29T09:00:00.000Z',
            'source': 'manual',
            'syncStatus': 'synced',
          },
        ],
      };

      final service = build();
      final traido = await service.openAfterPull(
        localIsEmpty: true,
        apply: repo.importDocument,
      );

      expect(traido, isTrue);
      expect(store.meals, hasLength(1));
      expect(store.meals.first.title, 'Guiso');
      expect(store.meals.first.items.first.kcal, 420);
      expect(store.weightLogs.first.weightKg, 81.4);
      expect(store.lastRestore.isClean, isTrue,
          reason: 'si la forma no coincide, los datos vuelven mutilados');
      service.dispose();
    });

    test('la base sin contenido no borra lo que hay en el teléfono', () async {
      await cargarUnaComida();
      client.paraTraer = null; // el cliente devuelve null cuando no hay filas
      final service = build();

      await service.openAfterPull(
        localIsEmpty: false,
        apply: repo.importDocument,
      );

      expect(store.meals, hasLength(1));
      service.dispose();
    });
  });

  test('un fallo de escritura no rompe nada y queda dicho', () async {
    final service = build();
    await service.openAfterPull(localIsEmpty: true, apply: (_) async {});
    await cargarUnaComida();
    client.fallaCon = const AppError(
      code: ApiErrorCode.server,
      message: 'la base dijo que no',
    );

    await service.push();

    expect(service.state, isA<SyncFailed>());
    // El dato sigue en el teléfono: la persistencia local no depende de esto.
    expect(store.meals, hasLength(1));
    service.dispose();
  });
}
