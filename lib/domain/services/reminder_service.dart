import '../models/reminder.dart';

/// Programa y cancela los recordatorios en el sistema.
///
/// Es una interfaz para que el resto de la app no dependa del plugin, y para
/// que los tests puedan verificar qué se programa sin tocar Android.
abstract interface class ReminderScheduler {
  /// Pide permiso de notificaciones. En Android 13+ hay que pedirlo; antes se
  /// da por concedido.
  Future<bool> requestPermission();

  Future<bool> hasPermission();

  /// Deja programado exactamente lo que dice la lista y **nada más**: lo que
  /// estaba antes se cancela.
  ///
  /// Reemplazar en vez de agregar es lo que evita que cambiar un horario deje
  /// sonando el viejo para siempre.
  Future<void> apply(List<Reminder> reminders);

  Future<void> cancelAll();
}
