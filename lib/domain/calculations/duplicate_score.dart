import 'dart:math' as math;

/// Motivos que explican un puntaje de duplicado, para mostrarlos en el diálogo.
enum DuplicateReason {
  externalId('Mismo registro del proveedor'),
  timeOverlap('Se solapan en el horario'),
  sameType('Mismo tipo de actividad'),
  similarDuration('Duración parecida'),
  similarCalories('Calorías parecidas');

  const DuplicateReason(this.label);
  final String label;
}

/// Entrada mínima para puntuar un par de actividades (§12).
class DuplicateInput {
  const DuplicateInput({
    required this.activityTypeId,
    required this.startedAt,
    required this.durationMinutes,
    required this.estimatedCalories,
    this.distanceMeters,
    this.externalSource,
    this.externalId,
  });

  final String activityTypeId;
  final DateTime startedAt;
  final int durationMinutes;
  final int estimatedCalories;
  final int? distanceMeters;
  final String? externalSource;
  final String? externalId;

  DateTime get endedAt => startedAt.add(Duration(minutes: durationMinutes));
}

class DuplicateScore {
  const DuplicateScore({required this.score, required this.reasons});

  final double score;
  final List<DuplicateReason> reasons;

  /// ≥ 0,85 → duplicado probable: `needs_review` + `DuplicateActivityDialog`.
  bool get isProbableDuplicate => score >= DuplicateThresholds.probable;

  /// 0,60–0,85 → sospecha: se guarda y se marca "Revisar", sin interrumpir.
  bool get isSuspicious =>
      score >= DuplicateThresholds.suspicious &&
      score < DuplicateThresholds.probable;
}

abstract final class DuplicateThresholds {
  static const double probable = 0.85;
  static const double suspicious = 0.60;

  /// Solo se comparan actividades con menos de 4 h de diferencia de inicio.
  static const Duration comparisonWindow = Duration(hours: 4);
}

/// Puntaje 0–1 de duplicado (§12). ★
///
/// **Nunca** borra sola: el resultado alimenta un diálogo donde decide la
/// persona (D-07).
DuplicateScore duplicateScore(DuplicateInput a, DuplicateInput b) {
  // Duplicado exacto del proveedor: se resuelve por update, no por diálogo.
  if (a.externalSource != null &&
      a.externalId != null &&
      a.externalSource == b.externalSource &&
      a.externalId == b.externalId) {
    return const DuplicateScore(
      score: 1.0,
      reasons: <DuplicateReason>[DuplicateReason.externalId],
    );
  }

  final startDelta = a.startedAt.difference(b.startedAt).abs();
  if (startDelta > DuplicateThresholds.comparisonWindow) {
    return const DuplicateScore(score: 0, reasons: <DuplicateReason>[]);
  }

  final reasons = <DuplicateReason>[];

  // Solape temporal sobre la duración del más corto.
  final overlapStart = a.startedAt.isAfter(b.startedAt)
      ? a.startedAt
      : b.startedAt;
  final overlapEnd = a.endedAt.isBefore(b.endedAt) ? a.endedAt : b.endedAt;
  final overlapMinutes = overlapEnd.difference(overlapStart).inSeconds / 60;
  final shortest = math.min(a.durationMinutes, b.durationMinutes);
  final overlap = shortest <= 0
      ? 0.0
      : (overlapMinutes / shortest).clamp(0.0, 1.0);
  if (overlap > 0) reasons.add(DuplicateReason.timeOverlap);

  final sameType = a.activityTypeId == b.activityTypeId ? 1.0 : 0.0;
  if (sameType == 1.0) reasons.add(DuplicateReason.sameType);

  final maxDuration = math.max(a.durationMinutes, b.durationMinutes);
  final durationSim = maxDuration <= 0
      ? 0.0
      : 1 - (a.durationMinutes - b.durationMinutes).abs() / maxDuration;
  if (durationSim >= 0.8) reasons.add(DuplicateReason.similarDuration);

  final maxCalories = math.max(a.estimatedCalories, b.estimatedCalories);
  final caloriesSim = maxCalories <= 0
      ? 0.0
      : 1 - (a.estimatedCalories - b.estimatedCalories).abs() / maxCalories;
  if (caloriesSim >= 0.8) reasons.add(DuplicateReason.similarCalories);

  const wOverlap = 0.45;
  const wSameType = 0.20;
  const wDuration = 0.15;
  const wCalories = 0.12;
  const wDistance = 0.08;

  final hasDistance = a.distanceMeters != null && b.distanceMeters != null;
  double distanceSim = 0;
  if (hasDistance) {
    final maxDistance = math.max(a.distanceMeters!, b.distanceMeters!);
    distanceSim = maxDistance <= 0
        ? 0.0
        : 1 - (a.distanceMeters! - b.distanceMeters!).abs() / maxDistance;
  }

  var score =
      wOverlap * overlap +
      wSameType * sameType +
      wDuration * durationSim +
      wCalories * caloriesSim;

  if (hasDistance) {
    score += wDistance * distanceSim;
  } else {
    // Sin distancia, su peso se reparte proporcionalmente entre los demás.
    const remaining = wOverlap + wSameType + wDuration + wCalories;
    score = score / remaining;
  }

  return DuplicateScore(
    score: score.clamp(0.0, 1.0),
    reasons: reasons,
  );
}
