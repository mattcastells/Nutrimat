import 'package:flutter/services.dart';

import '../../core/utils/dates.dart';
import '../../core/utils/formats.dart';
import '../../domain/models/summaries.dart';

/// Publica el día para el widget de la pantalla de inicio del teléfono.
///
/// El widget vive fuera del proceso de la app —es un `RemoteViews` que dibuja
/// el launcher, y se dibuja también con la app cerrada—, así que no puede
/// preguntarle nada a Dart. Lo que hay es un dato guardado: acá se escribe y en
/// Kotlin se lee.
///
/// **Se manda texto ya formateado, no números.** El widget no reimplementa el
/// formato de miles ni la redacción: "1.234" y "Te quedan" salen de `Fmt` y de
/// las mismas palabras que usa Inicio, así que no pueden desincronizarse. Las
/// dos excepciones son cuentas, no números formateados: los vasos de agua y el
/// porcentaje de cada macro, porque de eso el widget decide **cuánto dibuja**
/// (cuántas gotas, cuánta barra), no cómo se escribe.
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
  Future<void> publish(
    DailySummary summary, {
    required int glasses,
    required int waterGoal,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'publish',
        _payload(summary, glasses: glasses, waterGoal: waterGoal),
      );
    } on MissingPluginException {
      // Sin lado nativo: no hay widget que actualizar.
    } on PlatformException {
      // Ídem. No hay nada que reintentar ni nada que contarle a nadie.
    }
  }

  /// Lo que ve el widget. Público para poder verificarlo sin plataforma nativa
  /// de por medio: es donde vive la decisión de qué se muestra.
  static Map<String, Object> payloadFor(
    DailySummary summary, {
    required int glasses,
    required int waterGoal,
  }) => _payload(summary, glasses: glasses, waterGoal: waterGoal);

  static Map<String, Object> _payload(
    DailySummary summary, {
    required int glasses,
    required int waterGoal,
  }) {
    final balance = summary.balance;
    final remaining = balance.remainingKcal;
    final hasTarget = summary.baseTarget > 0;

    return <String, Object>{
      'date': isoDate(summary.date),

      // ── Calorías ──────────────────────────────────────────────────────
      // Sin objetivo cargado, "te quedan −1.123" sería un número inventado: el
      // widget dice que falta configurarlo y manda a la app.
      'value': hasTarget ? Fmt.integer(remaining.abs()) : '—',
      // Las mismas palabras que la tarjeta de Inicio y el anillo (D-17): el
      // exceso se cuenta, no se reta.
      'label': hasTarget
          ? (balance.isOverBudget ? 'kcal de más' : 'kcal restantes')
          : 'Sin objetivo configurado',
      'detail': hasTarget
          ? 'Comió ${Fmt.integer(summary.consumedKcal)} '
                'de ${Fmt.integer(balance.adjustedTarget)}'
          : 'Abrí Nutrimat para elegir uno',

      // ── Agua ──────────────────────────────────────────────────────────
      // Cuentas, no texto: el widget dibuja una gota por vaso.
      'waterGlasses': glasses,
      'waterGoal': waterGoal,

      // ── Macros ────────────────────────────────────────────────────────
      // Las tres, en el orden de Inicio: proteínas, carbohidratos, grasas.
      ..._macro('protein', 'P', summary.macros.protein),
      ..._macro('carbs', 'C', summary.macros.carbs),
      ..._macro('fat', 'G', summary.macros.fat),
    };
  }

  /// Una macro: su etiqueta ya escrita y cuánto de la barra pintar.
  ///
  /// El porcentaje se recorta a 100 para la barra, pero la etiqueta muestra los
  /// gramos de verdad: una barra llena con "180/140 g" al lado dice las dos
  /// cosas —que se pasó y cuánto—, mientras que una barra desbordada no diría
  /// ninguna.
  static Map<String, Object> _macro(
    String key,
    String initial,
    MacroProgress macro,
  ) {
    final current = macro.current.round();
    if (macro.target <= 0) {
      return <String, Object>{
        '${key}Label': '$initial $current g',
        '${key}Percent': 0,
      };
    }
    return <String, Object>{
      '${key}Label': '$initial $current/${macro.target}',
      '${key}Percent': (macro.fraction * 100).round().clamp(0, 100),
    };
  }
}
