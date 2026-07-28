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
  Future<AuthAccount?> signUp({required String email, required String password}) =>
      throw UnimplementedError();
  @override
  Future<void> signOut() async => account = null;
  @override
  Future<void> sendPasswordReset(String email) async {}
}

class _FakeClient implements CloudBackupClient {
  final List<String> uploads = <String>[];
  AppError? failWith;

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
  Future<String?> download(String userId) async => '{"restored":true}';

  @override
  Future<CloudBackupInfo?> info(String userId) async => null;

}

void main() {
  late _FakeClient client;
  late _FakeAuth auth;
  var document = '{"v":1}';

  CloudBackupService build({Duration debounce = Duration.zero}) =>
      CloudBackupService(
        client: client,
        auth: auth,
        readDocument: () => document,
        debounce: debounce,
      );

  setUp(() {
    client = _FakeClient();
    auth = _FakeAuth();
    document = '{"v":1}';
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
    final service = build(debounce: const Duration(milliseconds: 30));
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
    final service = build();
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
    final service = build();
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
    client.gate = gate;
    final service = build();

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
    final service = build();
    expect(await service.restore(), '{"restored":true}');
    service.dispose();
  });
}
