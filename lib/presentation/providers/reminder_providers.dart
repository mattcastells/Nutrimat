import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/reminder_service.dart';

/// Se sobrescribe en `bootstrap.dart`. Null si la plataforma no admite
/// notificaciones locales.
final reminderSchedulerProvider = Provider<ReminderScheduler?>((ref) => null);

/// Si Android tiene permitidas las notificaciones de la app. Se invalida al
/// volver a la pantalla, porque se puede haber cambiado desde Ajustes.
final notificationPermissionProvider = FutureProvider<bool>((ref) async {
  final scheduler = ref.watch(reminderSchedulerProvider);
  return await scheduler?.hasPermission() ?? false;
});
