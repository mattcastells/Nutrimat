import 'rounding.dart';

/// Un día con registro, para el cálculo de adherencia.
class AdherenceDay {
  const AdherenceDay({required this.consumed, required this.target});

  final int consumed;
  final int target;
}

/// Adherencia (§16).
///
/// ```
/// diaAdherente = |consumidas − objetivo| ≤ objetivo × 0,10
/// adherencia%  = round(diasAdherentes ÷ diasConRegistro × 100)
/// ```
///
/// Los días sin ningún registro no cuentan ni a favor ni en contra: no se
/// penaliza no registrar (RN-14). Con menos de 3 días con registro devuelve
/// `null` y la UI no muestra el porcentaje.
int? adherencePct(List<AdherenceDay> days, {double tolerance = 0.10}) {
  final withRecords = days.where((d) => d.consumed > 0 && d.target > 0).toList();
  if (withRecords.length < 3) return null;

  final adherent = withRecords
      .where((d) => (d.consumed - d.target).abs() <= d.target * tolerance)
      .length;
  return roundHalfUp(adherent / withRecords.length * 100);
}

/// IMC (§14). Se muestra **sin categorías moralizantes** (RN-14): el número y
/// un enlace neutral "Qué significa".
double bmi({required double weightKg, required double heightCm}) {
  final meters = heightCm / 100;
  return roundTo(weightKg / (meters * meters), 1);
}

/// Progreso de un objetivo de actividad (§18).
/// `progreso% = min(100, round(valorActual ÷ objetivo × 100))`.
/// Nunca altera el objetivo calórico (RN-09).
int activityGoalProgressPct({
  required num currentValue,
  required num targetValue,
}) {
  if (targetValue <= 0) return 0;
  final pct = roundHalfUp(currentValue / targetValue * 100);
  return pct > 100 ? 100 : pct;
}
