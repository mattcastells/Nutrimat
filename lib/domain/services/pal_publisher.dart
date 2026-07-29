import 'dart:async';

import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../data/remote/pals_client.dart';
import '../models/pal.dart';
import '../repositories/auth_gateway.dart';

/// Publica el día propio para que lo vean los pals.
///
/// Sube **solo** la proyección: momento, nombre y calorías de cada comida, más
/// minutos y sesiones de actividad. El resto —peso, medidas, los ítems de cada
/// comida, las fotos— nunca sale del teléfono, así que no hay forma de que un
/// pal lo lea aunque quiera.
///
/// Se publica solo el día en curso: nadie mira hacia atrás el día de otro, y
/// subir el historial entero expondría meses de datos por una función que se
/// usa para ver si tu amigo almorzó.
class PalPublisher {
  PalPublisher({
    required PalsClient client,
    required AuthGateway auth,
    required PalDay Function(DateTime date) buildDay,
    this.debounce = const Duration(seconds: 8),
  }) : _client = client,
       _auth = auth,
       _buildDay = buildDay;

  final PalsClient _client;
  final AuthGateway _auth;
  final PalDay Function(DateTime date) _buildDay;

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
      await _client.publishDay(_buildDay(today()));
    } on AppError {
      // Silencioso a propósito: esto es una comodidad social, no puede
      // interrumpir el registro de una comida ni pedir atención.
    } finally {
      _publishing = false;
    }
  }

  void dispose() => _timer?.cancel();
}
