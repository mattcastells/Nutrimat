import 'rounding.dart';

/// Un punto de una serie temporal.
class SeriesPoint {
  const SeriesPoint(this.date, this.value);

  final DateTime date;
  final double value;
}

/// Media móvil (§15).
///
/// `mediaMovil(n)[i] = promedio de la ventana [i−n+1 … i]`.
/// Con ventana incompleta se calcula con los que haya, **mínimo 2** puntos.
List<SeriesPoint> movingAverage(List<SeriesPoint> points, int window) {
  if (window < 1) return const <SeriesPoint>[];
  final out = <SeriesPoint>[];
  for (var i = 0; i < points.length; i++) {
    final start = (i - window + 1).clamp(0, points.length);
    final slice = points.sublist(start, i + 1);
    if (slice.length < 2) continue;
    final sum = slice.fold<double>(0, (acc, p) => acc + p.value);
    out.add(SeriesPoint(points[i].date, sum / slice.length));
  }
  return out;
}

/// Tendencia semanal: regresión lineal por mínimos cuadrados sobre los últimos
/// 14 días de la media móvil. `trendKgPerWeek = pendienteDiaria × 7` (§15).
///
/// Con menos de 3 puntos no se calcula: devuelve `null` y la UI muestra
/// "Necesitamos unos días más de registro para mostrar una tendencia".
double? weightTrendKgPerWeek(List<SeriesPoint> points) {
  if (points.length < 3) return null;

  final smoothed = movingAverage(points, 7);
  final source = smoothed.length >= 3 ? smoothed : points;
  final window = source.length > 14
      ? source.sublist(source.length - 14)
      : source;
  if (window.length < 3) return null;

  final firstDay = window.first.date;
  var sumX = 0.0;
  var sumY = 0.0;
  var sumXy = 0.0;
  var sumXx = 0.0;
  for (final p in window) {
    final x = p.date.difference(firstDay).inDays.toDouble();
    sumX += x;
    sumY += p.value;
    sumXy += x * p.value;
    sumXx += x * x;
  }
  final n = window.length;
  final denominator = n * sumXx - sumX * sumX;
  if (denominator == 0) return null;

  final slopePerDay = (n * sumXy - sumX * sumY) / denominator;
  return roundTo(slopePerDay * 7, 2);
}
