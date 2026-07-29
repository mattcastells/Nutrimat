import '../../core/utils/dates.dart';
import '../enums/enums.dart';

/// Registro de peso. Uno por día: registrar de nuevo actualiza (D-16).
class WeightLog {
  const WeightLog({
    required this.id,
    required this.weightKg,
    required this.localDate,
    required this.loggedAt,
    this.source = 'manual',
    this.notes,
    this.photoPath,
    this.syncStatus = SyncStatus.synced,
  });

  final String id;
  final double weightKg;
  final DateTime localDate;
  final DateTime loggedAt;
  final String source;
  final String? notes;
  final String? photoPath;
  final SyncStatus syncStatus;

  WeightLog copyWith({
    double? weightKg,
    DateTime? loggedAt,
    String? notes,
    SyncStatus? syncStatus,
  }) => WeightLog(
    id: id,
    weightKg: weightKg ?? this.weightKg,
    localDate: localDate,
    loggedAt: loggedAt ?? this.loggedAt,
    source: source,
    notes: notes ?? this.notes,
    photoPath: photoPath,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'weightKg': weightKg,
    'localDate': isoDate(localDate),
    'loggedAt': loggedAt.toIso8601String(),
    'source': source,
    'notes': notes,
    'photoPath': photoPath,
    'syncStatus': syncStatus.wire,
  };

  static WeightLog fromJson(Map<String, dynamic> j) => WeightLog(
    id: j['id'] as String,
    weightKg: (j['weightKg'] as num).toDouble(),
    localDate: DateTime.parse(j['localDate'] as String),
    loggedAt: DateTime.parse(j['loggedAt'] as String),
    source: j['source'] as String? ?? 'manual',
    notes: j['notes'] as String?,
    photoPath: j['photoPath'] as String?,
    syncStatus: SyncStatus.values.firstWhere(
      (e) => e.wire == j['syncStatus'],
      orElse: () => SyncStatus.synced,
    ),
  );
}

/// Medida corporal (S-26). Cada métrica trae su propio rango válido.
class BodyMeasurement {
  const BodyMeasurement({
    required this.id,
    required this.metric,
    required this.value,
    required this.localDate,
    this.notes,
  });

  final String id;
  final MeasurementMetric metric;
  final double value;
  final DateTime localDate;
  final String? notes;

  String get unit => metric.unitLabel;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'metric': metric.wire,
    'value': value,
    'localDate': isoDate(localDate),
    'notes': notes,
  };

  static BodyMeasurement fromJson(Map<String, dynamic> j) => BodyMeasurement(
    id: j['id'] as String,
    metric: MeasurementMetric.fromWire(j['metric'] as String),
    value: (j['value'] as num).toDouble(),
    localDate: DateTime.parse(j['localDate'] as String),
    notes: j['notes'] as String?,
  );
}

/// Integración de salud. Health Connect es la única del MVP (D-21) y su
/// pantalla solo se muestra en Android.
class HealthIntegration {
  const HealthIntegration({
    required this.id,
    required this.provider,
    required this.status,
    this.permissions = const <String>[],
    this.lastSyncAt,
    this.syncCursor,
    this.lastError,
    this.connectedAt,
    this.importedCount = 0,
  });

  final String id;
  final HealthProvider provider;
  final IntegrationStatus status;
  final List<String> permissions;
  final DateTime? lastSyncAt;
  final String? syncCursor;
  final String? lastError;
  final DateTime? connectedAt;
  final int importedCount;

  bool get isConnected =>
      status == IntegrationStatus.connected ||
      status == IntegrationStatus.syncing;

  HealthIntegration copyWith({
    IntegrationStatus? status,
    List<String>? permissions,
    DateTime? lastSyncAt,
    String? lastError,
    DateTime? connectedAt,
    int? importedCount,
    bool clearError = false,
  }) => HealthIntegration(
    id: id,
    provider: provider,
    status: status ?? this.status,
    permissions: permissions ?? this.permissions,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    syncCursor: syncCursor,
    lastError: clearError ? null : (lastError ?? this.lastError),
    connectedAt: connectedAt ?? this.connectedAt,
    importedCount: importedCount ?? this.importedCount,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'provider': provider.wire,
    'status': status.wire,
    'permissions': permissions,
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'syncCursor': syncCursor,
    'lastError': lastError,
    'connectedAt': connectedAt?.toIso8601String(),
    'importedCount': importedCount,
  };

  static HealthIntegration fromJson(Map<String, dynamic> j) => HealthIntegration(
    id: j['id'] as String,
    provider: HealthProvider.healthConnect,
    status: IntegrationStatus.values.firstWhere(
      (e) => e.wire == j['status'],
      orElse: () => IntegrationStatus.notConnected,
    ),
    permissions: (j['permissions'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => e as String)
        .toList(),
    lastSyncAt: j['lastSyncAt'] == null
        ? null
        : DateTime.parse(j['lastSyncAt'] as String),
    syncCursor: j['syncCursor'] as String?,
    lastError: j['lastError'] as String?,
    connectedAt: j['connectedAt'] == null
        ? null
        : DateTime.parse(j['connectedAt'] as String),
    importedCount: j['importedCount'] as int? ?? 0,
  );
}
