import 'package:flutter/services.dart';

import '../../core/utils/dates.dart';
import '../../core/utils/formats.dart';
import '../../domain/models/summaries.dart';

/// Publica las calorías restantes del día para el widget de la pantalla de
/// inicio del teléfono.
///
/// El widget vive fuera del proceso de la app —es un `RemoteViews` que dibuja
/// el launcher, y se dibuja también con la app cerrada—, así que no puede
/// preguntarle nada a Dart. Lo que hay es un dato guardado: acá se escribe y en
/// Kotlin se lee.
///
/// **Se manda texto ya formateado, no números.** El widget no reimplementa el
/// formato de miles ni la redacción: "1.234" y "Te quedan" salen de `Fmt` y de
/// las mismas palabras que usa Inicio, así que no pueden desincronizarse. Lo
/// único que Kotlin decide por su cuenta es si el dato sigue siendo de hoy.
class HomeWidgetPublisher {
  const HomeWidgetPublisher();

  static const MethodChannel _channel = MethodChannel(
    'io.nutrimat.app/widget',
  );

  /// Escribe el estado del día y le pide al sistema que redibuje el widget.
  ///
  /// Nunca lanza. Un widget que no se actualiza es una molestia; un registro de
  /// comida que falla porque el widget no se pudo actualizar sería un error de
  /// prioridades. En una plataforma sin el canal nativo (o en los tests) es un
  /// no-op silencioso.
  Future<void> publish(DailySummary summary) async {
    try {
      await _channel.invokeMethod<void>('publish', _payload(summary));
    } on MissingPluginException {
      // Sin lado nativo: no hay widget que actualizar.
    } on PlatformException {
      // Ídem. No hay nada que reintentar ni nada que contarle a nadie.
    }
  }

  /// Lo que ve el widget. Público para poder verificarlo sin plataforma nativa
  /// de por medio: es donde vive la decisión de qué se muestra.
  static Map<String, Object> payloadFor(DailySummary summary) =>
      _payload(summary);

  static Map<String, Object> _payload(DailySummary summary) {
    final balance = summary.balance;
    final remaining = balance.remainingKcal;

    // Sin objetivo cargado, "te quedan −1.123" sería un número inventado: el
    // widget dice que falta configurarlo y manda a la app.
    if (summary.baseTarget <= 0) {
      return <String, Object>{
        'date': isoDate(summary.date),
        'value': '—',
        'label': 'Sin objetivo configurado',
        'detail': 'Abrí Nutrimat para elegir uno',
      };
    }

    return <String, Object>{
      'date': isoDate(summary.date),
      'value': Fmt.integer(remaining.abs()),
      // Las mismas palabras que la tarjeta de Inicio y el anillo (D-17): el
      // exceso se cuenta, no se reta.
      'label': balance.isOverBudget ? 'kcal de más' : 'kcal restantes',
      'detail':
          'Comió ${Fmt.integer(summary.consumedKcal)} '
          'de ${Fmt.integer(balance.adjustedTarget)}',
    };
  }
}
