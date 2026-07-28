import '../../core/error/app_error.dart';

/// Estimación por ritmo para caminata y carrera (§11).
///
/// Se usa cuando hay distancia y duración pero el tipo no da un MET confiable.
/// `estimationMethod = 'pace'`.
///
/// Cada tramo es semiabierto `[inferior, superior)` y lleva el MET de su borde
/// inferior, que es el punto del Compendium of Physical Activities que lo
/// ancla — 4/5/6/7 mph en carrera, 2/3/3,5/4 mph en caminata.
abstract final class PaceMet {
  /// Por encima de esta velocidad el dato se considera incoherente.
  static const double maxPlausibleKmh = 45;

  static double speedKmh({
    required int distanceMeters,
    required int durationMinutes,
  }) {
    if (durationMinutes <= 0) {
      throw const CalculationError(
        'estimateMetFromPace',
        'durationMinutes',
        'debe ser mayor que cero',
      );
    }
    if (distanceMeters <= 0) {
      throw const CalculationError(
        'estimateMetFromPace',
        'distanceMeters',
        'debe ser mayor que cero',
      );
    }
    return (distanceMeters / 1000) / (durationMinutes / 60);
  }

  static double _walkingMet(double kmh) {
    if (kmh < 4.0) return 2.8;
    if (kmh < 5.5) return 3.5;
    if (kmh < 6.5) return 4.3;
    return 5.0;
  }

  static double _runningMet(double kmh) {
    if (kmh < 8.0) return 6.0;
    if (kmh < 9.7) return 8.3;
    if (kmh < 11.3) return 9.8;
    if (kmh < 12.9) return 11.0;
    return 12.8;
  }
}

/// Devuelve el MET estimado por ritmo, o `null` si el dato es incoherente
/// (velocidad > 45 km/h) o el tipo no admite estimación por ritmo.
double? estimateMetFromPace({
  required int distanceMeters,
  required int durationMinutes,
  required String typeSlug,
}) {
  final kmh = PaceMet.speedKmh(
    distanceMeters: distanceMeters,
    durationMinutes: durationMinutes,
  );
  if (kmh > PaceMet.maxPlausibleKmh) return null;

  return switch (typeSlug) {
    'walking' || 'hiking' => PaceMet._walkingMet(kmh),
    'running' => PaceMet._runningMet(kmh),
    _ => null,
  };
}
