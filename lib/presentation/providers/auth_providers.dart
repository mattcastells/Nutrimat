import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/supabase_config.dart';
import '../../data/remote/pals_client.dart';
import '../../domain/models/pal.dart';
import '../../domain/repositories/auth_gateway.dart';
import '../../domain/services/cloud_backup_service.dart';
import '../../domain/services/photo_sync_service.dart';
import '../../domain/services/relational_sync_service.dart';

/// Se sobrescribe en `bootstrap.dart` con la implementación que corresponda:
/// Supabase si la compilación trae credenciales, local si no.
final authGatewayProvider = Provider<AuthGateway>(
  (ref) => throw UnimplementedError('authGatewayProvider sin inicializar'),
);

/// Cuenta con la que está abierta la sesión, o `null`.
///
/// Escucha el stream del gateway, así que se actualiza también cuando la
/// sesión caduca sola o cuando se cierra desde otro lado.
final authAccountProvider = StreamProvider<AuthAccount?>((ref) {
  final gateway = ref.watch(authGatewayProvider);
  return gateway.changes;
});

/// Cuenta actual de forma síncrona, para decidir a dónde va el splash sin
/// esperar un frame.
final currentAccountProvider = Provider<AuthAccount?>((ref) {
  final gateway = ref.watch(authGatewayProvider);
  return ref.watch(authAccountProvider).maybeWhen(
    data: (account) => account,
    orElse: () => gateway.currentAccount,
  );
});

/// `true` cuando la sesión es real contra el servidor. En `false` la app anda
/// igual, pero los datos no salen del teléfono.
final isCloudEnabledProvider = Provider<bool>(
  (ref) => SupabaseConfig.isConfigured,
);

/// Servicio de respaldo a la nube. Se sobrescribe en `bootstrap.dart` solo
/// cuando hay servidor; sin él, la app no respalda sola y lo dice en Ajustes.
final cloudBackupProvider = Provider<CloudBackupService?>((ref) => null);

/// Estado del respaldo para la UI.
final backupStateProvider = StreamProvider<BackupState>((ref) {
  final service = ref.watch(cloudBackupProvider);
  if (service == null) {
    return Stream<BackupState>.value(
      BackupUnavailable(
        SupabaseConfig.unavailableReason ?? 'Sin servidor configurado.',
      ),
    );
  }
  return service.states.transform(
    StreamTransformer<BackupState, BackupState>.fromHandlers(
      handleData: (data, sink) => sink.add(data),
    ),
  );
});

/// Persistencia relacional: las mismas cosas del respaldo, como filas en las
/// tablas. Null sin servidor.
final relationalSyncProvider = Provider<RelationalSyncService?>((ref) => null);

/// Sube y sirve las fotos del bucket. Null sin servidor: las fotos quedan
/// solo en este teléfono.
final photoSyncProvider = Provider<PhotoSyncService?>((ref) => null);

/// Vínculos con pals y sus días. Null sin servidor: la función no existe.
final palsClientProvider = Provider<PalsClient?>((ref) => null);

/// Los vínculos, recargables tras aceptar o quitar uno.
final palsProvider = FutureProvider<List<Pal>>((ref) async {
  final client = ref.watch(palsClientProvider);
  if (client == null) return <Pal>[];
  return client.list();
});

/// Código propio para que alguien te agregue.
final myPalCodeProvider = FutureProvider<String?>((ref) async {
  final client = ref.watch(palsClientProvider);
  return client?.myCode();
});
