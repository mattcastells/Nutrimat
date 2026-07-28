import 'dart:math' as math;

/// Redondeo `round_half_up` al entero (11-calculation-rules.md, transversales).
///
/// No se acumula error: se redondea **una sola vez**, al final del cálculo.
int roundHalfUp(double value) {
  if (value.isNaN || value.isInfinite) {
    throw ArgumentError.value(value, 'value', 'no es un número finito');
  }
  final floor = value.floorToDouble();
  return (value - floor >= 0.5 ? floor + 1 : floor).toInt();
}

/// Redondeo a `decimals` decimales, medio arriba.
double roundTo(double value, int decimals) {
  final factor = math.pow(10, decimals).toDouble();
  return roundHalfUp(value * factor) / factor;
}
