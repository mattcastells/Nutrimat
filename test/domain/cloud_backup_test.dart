// El servicio de respaldo con un cliente falso: verifica que agrupe los
// cambios, que un fallo no rompa nada y que no se pierda un cambio llegado a
// mitad de una subida.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrimat/core/error/app_error.dart';
import 'package:nutrimat/data/remote/cloud_backup_client.dart';
import 'package:nutrimat/domain/repositories/auth_gateway.dart';
import 'package:nutrimat/domain/services/cloud_backup_service.dart';

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

class _FakeClient implements CloudBackupClient {
  final List<String> uploads = <String>[];
  AppError? failWith;
  AppError? downloadFailsWith;

  /// Se completa a mano para poder tener una subida "en curso".
  Completer<void>? gate;

  @override
  Future<void> upload({
    required String userId,
    required String documentJson,
  }) async {
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    uploads.add(documentJson);
  }

  @override
  Future<String?> download(String userId) async {
    if (downloadFailsWith != null) throw downloadFailsWith!;
    return '{"restored":true}';
  }

  @override
  Future<CloudBackupInfo?> info(String userId) async => null;

}

void main() {
  late _FakeClient client;
  late _FakeAuth auth;
  var document = '{"v":1}';

  /// Por defecto el teléfono tiene datos: subir con el teléfono vacío es un
  /// caso aparte y tiene sus propios tests.
  var localHasData = true;

  CloudBackupService build({Duration debounce = Duration.zero}) =>
      CloudBackupService(
        client: client,
        auth: auth,
        readDocument: () => document,
        localHasData: () => localHasData,
        debounce: debounce,
      );

  /// Servicio listo para subir. La puerta la abre `openAfterRestore`, así que
  /// los tests que no la prueban tienen que pasar por ahí igual.
  Future<CloudBackupService> ready({Duration debounce = Duration.zero}) async {
    final service = build(debounce: debounce);
    await service.openAfterRestore(localIsEmpty: false, apply: (_) async {});
    return service;
  }

  setUp(() {
    client = _FakeClient();
    auth = _FakeAuth();
    document = '{"v":1}';
    localHasData = true;
  });

  test('sin sesión no sube nada', () async {
    auth.account = null;
    final service = build();
    service.markDirty();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(client.uploads, isEmpty);
    service.dispose();
  });

  test('varios cambios seguidos suben una sola vez', () async {
    final service = await ready(debounce: const Duration(milliseconds: 30));
    // Cuatro vasos de agua en dos segundos: un solo respaldo, no cuatro.
    service
      ..markDirty()
      ..markDirty()
      ..markDirty()
      ..markDirty();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(client.uploads, hasLength(1));
    service.dispose();
  });

  test('un fallo deja el estado en error y no lanza', () async {
    client.failWith = const AppError(
      code: ApiErrorCode.offline,
      message: 'sin conexión',
    );
    final service = await ready();
    await service.flush();
    expect(service.state, isA<BackupFailed>());
    expect(client.uploads, isEmpty);
    service.dispose();
  });

  test('después de fallar, el próximo cambio vuelve a intentar', () async {
    client.failWith = const AppError(
      code: ApiErrorCode.offline,
      message: 'sin conexión',
    );
    final service = await ready();
    await service.flush();
    expect(service.state, isA<BackupFailed>());

    client.failWith = null;
    await service.flush();
    expect(client.uploads, hasLength(1));
    expect(service.state, isA<BackupIdle>());
    service.dispose();
  });

  test('un cambio durante la subida no se pierde', () async {
    final gate = Completer<void>();
    final service = await ready();
    client.gate = gate;

    final first = service.flush();
    // Llega un cambio mientras la primera subida está en vuelo.
    document = '{"v":2}';
    service.markDirty();

    client.gate = null;
    gate.complete();
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Lo último subido tiene que ser el documento nuevo, no el viejo.
    expect(client.uploads.last, '{"v":2}');
    service.dispose();
  });

  test('restaurar devuelve el documento guardado', () async {
    final service = await ready();
    expect(await service.restore(), '{"restored":true}');
    service.dispose();
  });

  group('la puerta antes de subir', () {
    // El bug más grave que tuvimos: reinstalar, entrar, y que el documento
    // vacío del alta pisara el respaldo bueno a los pocos segundos.
    test('sin abrir la puerta no sube nada', () async {
      final service = build();
      service.markDirty();
      await service.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.uploads, isEmpty);
      service.dispose();
    });

    test('con el teléfono vacío trae el respaldo y recién ahí habilita', () async {
      final service = build();
      String? aplicado;
      final restored = await service.openAfterRestore(
        localIsEmpty: true,
        apply: (json) async => aplicado = json,
      );

      expect(restored, isTrue);
      expect(aplicado, '{"restored":true}');

      await service.flush();
      expect(client.uploads, hasLength(1));
      service.dispose();
    });

    test('con datos locales no restaura, pero habilita igual', () async {
      final service = build();
      var aplicado = false;
      final restored = await service.openAfterRestore(
        localIsEmpty: false,
        apply: (_) async => aplicado = true,
      );

      expect(restored, isFalse);
      expect(aplicado, isFalse, reason: 'pisar lo local sería el mismo error al revés');

      await service.flush();
      expect(client.uploads, hasLength(1));
      service.dispose();
    });
  });

  group('un documento vacío nunca pisa el respaldo', () {
    // La puerta sola no alcanza: `openAfterRestore` la abre igual cuando la
    // descarga falla —a propósito, para no dejar de respaldar en silencio—,
    // y ahí el teléfono vacío tenía vía libre para borrar la copia buena.
    test('con el teléfono vacío no sube, aunque la puerta esté abierta',
        () async {
      final service = await ready();
      localHasData = false;

      service.markDirty();
      await service.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.uploads, isEmpty);
      expect(service.state, isA<BackupHeldEmpty>());
      service.dispose();
    });

    test('si la restauración falla por red, tampoco sube el vacío', () async {
      client.downloadFailsWith = const AppError(
        code: ApiErrorCode.offline,
        message: 'sin conexión',
      );
      final service = build();
      localHasData = false;

      // El teléfono está vacío y la descarga se cae: la puerta se abre igual.
      await service.openAfterRestore(localIsEmpty: true, apply: (_) async {});
      expect(service.canUpload, isTrue);

      await service.flush();
      expect(client.uploads, isEmpty, reason: 'habría borrado el respaldo');
      service.dispose();
    });

    test('en cuanto hay un dato real, vuelve a subir', () async {
      final service = await ready();
      localHasData = false;
      await service.flush();
      expect(client.uploads, isEmpty);

      localHasData = true;
      await service.flush();
      expect(client.uploads, hasLength(1));
      service.dispose();
    });
  });
}
