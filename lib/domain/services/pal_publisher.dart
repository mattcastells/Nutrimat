import 'dart:async';
import 'dart:convert';

import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../data/remote/pals_client.dart';
import '../models/pal.dart';
import '../repositories/auth_gateway.dart';

/// Publica el día propio para que lo vean los pals.
///
/// Sube la proyección: momento, título y calorías de cada comida, más minutos
/// y sesiones de actividad — eso siempre, como antes. Fotos, agua, sueño y el
/// detalle de cada actividad se suman solo si [PalSharingPrefs] los tiene
/// prendidos; si no, van vacíos/`null` aunque el dato exista en el teléfono.
/// Peso, medidas y los ítems de cada comida nunca salen de acá, prenda lo que
/// prenda la persona: eso no es una categoría configurable.
///
/// ## Por qué publica una ventana y no solo hoy
///
/// Hasta acá esto publicaba **únicamente `today()`**, y de ahí salían casi
/// todos los "lo que ve mi pal no es lo que tengo yo":
///
/// - La pantalla de un pal deja mirar [PalDayScreen] hasta 7 días atrás, pero
///   ninguna de esas fechas se volvía a escribir nunca. Cargar el almuerzo de
///   ayer, corregir una porción del martes o **borrar** una comida vieja no
///   llegaba: el pal seguía viendo la foto congelada del momento en que esa
///   fecha había sido hoy.
/// - Peor con el cambio de día: una comida registrada a las 23:58 dispara la
///   publicación a las 00:00:06, cuando `today()` ya es el día siguiente. Se
///   publicaba el día nuevo —vacío— y la comida no aparecía en ninguno de los
///   dos.
/// - Y un teléfono nuevo, o uno que acaba de restaurar de la nube, no tenía
///   cómo corregir lo que el servidor tuviera guardado de antes.
///
/// Ahora se arma la ventana entera —hoy y los [windowDays] anteriores—, se
/// compara contra lo último que se subió y **se manda solo lo que cambió**, en
/// un pedido. Un día sin novedades no gasta nada; uno que cambió se corrige,
/// sea cual sea su fecha.
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

  /// Cuántos días atrás se mantienen al día. Es el mismo número que muestra la
  /// pantalla del día de un pal (`palDayHistoryDays`) y el mismo que dejan ver
  /// las policies de agua, sueño y fotos: publicar más sería exponer días que
  /// nadie puede mirar.
  static const int windowDays = 7;

  /// Cuánto se espera antes de reintentar una publicación que falló.
  ///
  /// Antes no se reintentaba nunca: un corte de red en el momento justo dejaba
  /// el día viejo hasta el próximo cambio, que podía ser al día siguiente. Se
  /// reintenta unas pocas veces y con espera creciente, en silencio.
  static const Duration retryDelay = Duration(minutes: 2);
  static const int maxRetries = 3;

  Timer? _timer;
  bool _publishing = false;

  /// Si algo cambió **mientras** se publicaba. Sin esto, la cena registrada
  /// durante la subida del almuerzo no se publicaba nunca: `publish` salía por
  /// `_publishing` sin dejar rastro, y el día del pal quedaba viejo hasta el
  /// próximo cambio, que podía ser al día siguiente.
  bool _dirty = false;

  int _failures = 0;

  /// Lo último que se subió con éxito, por fecha. Es lo que evita reescribir
  /// ocho filas cada vez que alguien toma un vaso de agua.
  ///
  /// Solo se actualiza cuando el servidor aceptó: si la subida falla, el día
  /// sigue marcado como pendiente y el próximo intento —o el próximo cambio—
  /// lo vuelve a mandar. Es todo el mecanismo de reintento que hace falta.
  final Map<String, String> _lastSent = <String, String>{};

  /// De quién es lo que hay en [_lastSent]. Si entra otra cuenta en el mismo
  /// teléfono, lo anterior no dice nada de la nueva y hay que subir todo otra
  /// vez.
  String? _lastSentAccount;

  /// Un fallo no interrumpe nada: el próximo cambio vuelve a intentar. Que un
  /// pal vea el almuerzo diez minutos más tarde no es un problema.
  void markDirty() {
    if (_auth.currentAccount == null) return;
    _dirty = true;
    _failures = 0;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(publish()));
  }

  Future<void> publish() async {
    final account = _auth.currentAccount?.id;
    if (account == null) return;
    if (_publishing) {
      _dirty = true;
      return;
    }
    _publishing = true;
    _dirty = false;
    _timer?.cancel();

    var fallo = false;
    try {
      if (_lastSentAccount != account) {
        _lastSent.clear();
        _lastSentAccount = account;
      }

      // Se piden las preferencias en cada publicación, no se cachean: así un
      // interruptor que se acaba de apagar se respeta desde la próxima
      // comida, no desde el próximo reinicio de la app.
      final prefs = await _client.mySharingPrefs();

      final pendientes = <PalDay>[];
      final payloads = <String, String>{};
      final base = today();
      for (var i = 0; i <= windowDays; i++) {
        final date = base.subtract(Duration(days: i));
        final day = _buildDay(date, prefs);
        final key = isoDate(date);
        final payload = jsonEncode(day.toRow());
        if (_lastSent[key] == payload) continue;
        pendientes.add(day);
        payloads[key] = payload;
      }

      if (pendientes.isNotEmpty) {
        await _client.publishDays(pendientes);
        _lastSent.addAll(payloads);
      }
      // Fuera de la ventana no hay nada que mirar, y guardarlo para siempre
      // haría crecer el mapa un día por cada día de uso.
      _lastSent.removeWhere((key, _) => !_enVentana(key, base));
      _failures = 0;
    } on AppError {
      // Silencioso a propósito: esto es una comodidad social, no puede
      // interrumpir el registro de una comida ni pedir atención. Lo que sí
      // cambia es que ahora vuelve a intentar solo.
      fallo = true;
    } finally {
      _publishing = false;
    }

    if (_dirty) {
      await publish();
      return;
    }
    if (fallo && _failures < maxRetries) {
      _failures++;
      _timer?.cancel();
      _timer = Timer(retryDelay * _failures, () => unawaited(publish()));
    }
  }

  bool _enVentana(String isoKey, DateTime base) {
    final date = DateTime.tryParse(isoKey);
    if (date == null) return false;
    return !date.isBefore(base.subtract(const Duration(days: windowDays)));
  }

  void dispose() => _timer?.cancel();
}
