import 'dart:async';

import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../data/remote/pals_client.dart';
import '../models/pal.dart';
import '../repositories/auth_gateway.dart';

/// Publica el día propio para que lo vean los pals.
///
/// Sube la proyección: momento, nombre y calorías de cada comida, más minutos
/// y sesiones de actividad — eso siempre, como antes. Fotos, agua, sueño y el
/// detalle de cada actividad se suman solo si [PalSharingPrefs] los tiene
/// prendidos; si no, van vacíos/`null` aunque el dato exista en el teléfono.
/// Peso, medidas y los ítems de cada comida nunca salen de acá, prenda lo que
/// prenda la persona: eso no es una categoría configurable.
///
/// Se publica solo el día en curso: nadie mira hacia atrás el día de otro, y
/// subir el historial entero expondría meses de datos por una función que se
/// usa para ver si tu amigo almorzó.
class PalPublisher {
  PalPublisher({
    required PalsClient client,
    required AuthGateway auth,
    required PalDay Function(DateTime date, PalSharingPrefs prefs) buildDay,
    this.debounce = const Duration(seconds: 8),
  }) : _client = client,
       _auth = auth,
       _buildDay = buildDay;

  final PalsClient _client;
  final AuthGateway _auth;
  final PalDay Function(DateTime date, PalSharingPrefs prefs) _buildDay;

  /// Un poco más largo que el del respaldo: al armar una comida se agregan
  /// varios ítems seguidos y no tiene sentido publicar en cada uno.
  final Duration debounce;

  Timer? _timer;
  bool _publishing = false;

  /// Un fallo no se reintenta solo: el próximo cambio vuelve a intentar. Que
  /// un pal vea el almuerzo diez minutos más tarde no es un problema.
  void markDirty() {
    if (_auth.currentAccount == null) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(publish()));
  }

  Future<void> publish() async {
    if (_auth.currentAccount == null || _publishing) return;
    _publishing = true;
    _timer?.cancel();
    try {
      // Se piden las preferencias en cada publicación, no se cachean: así un
      // interruptor que se acaba de apagar se respeta desde la próxima
      // comida, no desde el próximo reinicio de la app.
      final prefs = await _client.mySharingPrefs();
      await _client.publishDay(_buildDay(today(), prefs));
    } on AppError {
      // Silencioso a propósito: esto es una comodidad social, no puede
      // interrumpir el registro de una comida ni pedir atención.
    } finally {
      _publishing = false;
    }
  }

  void dispose() => _timer?.cancel();
}
