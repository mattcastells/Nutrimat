import '../enums/enums.dart';

/// Perfil de la persona usuaria (10-types §UserProfile).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.biologicalSex,
    required this.activityLevel,
    required this.timezone,
    required this.unitSystem,
    required this.themeMode,
    required this.locale,
    required this.exerciseCreditPercentage,
    required this.exerciseCreditEnabled,
    required this.showNetCalories,
    this.waterGoalGlasses = 8,
    this.glassSizeMl = 250,
    required this.profileCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.avatarPath,
    this.birthDate,
    this.heightCm,
    this.isDemo = false,
    this.email,
    this.deletionRequestedAt,
  });

  factory UserProfile.empty(String id) => UserProfile(
    id: id,
    biologicalSex: BiologicalSex.unspecified,
    activityLevel: ActivityLevel.moderate,
    timezone: 'America/Argentina/Buenos_Aires',
    unitSystem: UnitSystem.metric,
    themeMode: ThemeModeSetting.system,
    locale: 'es',
    // 0 % por defecto (D-02).
    exerciseCreditPercentage: 0,
    exerciseCreditEnabled: true,
    showNetCalories: false,
    waterGoalGlasses: 8,
    glassSizeMl: 250,
    profileCompleted: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final String id;
  final String? displayName;
  final String? avatarPath;
  final BiologicalSex biologicalSex;
  final DateTime? birthDate;
  final double? heightCm;
  final ActivityLevel activityLevel;
  final String timezone;
  final UnitSystem unitSystem;
  final ThemeModeSetting themeMode;
  final String locale;

  /// 0–100. Cuánto del gasto estimado se suma al presupuesto diario (RN-02).
  final int exerciseCreditPercentage;
  final bool exerciseCreditEnabled;
  final bool showNetCalories;

  /// Meta diaria de vasos. 8 es la referencia popular, no una regla médica:
  /// por eso se puede cambiar y no se castiga no llegar.
  final int waterGoalGlasses;

  /// Solo afecta el equivalente en ml que se muestra; el historial guarda
  /// vasos, así que cambiarlo no reescribe el pasado.
  final int glassSizeMl;
  final bool profileCompleted;
  final bool isDemo;
  final String? email;
  final DateTime? deletionRequestedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Porcentaje efectivo: 0 si el ajuste está desactivado.
  int get effectiveCreditPercentage =>
      exerciseCreditEnabled ? exerciseCreditPercentage : 0;

  UserProfile copyWith({
    String? displayName,
    String? avatarPath,
    BiologicalSex? biologicalSex,
    DateTime? birthDate,
    double? heightCm,
    ActivityLevel? activityLevel,
    String? timezone,
    UnitSystem? unitSystem,
    ThemeModeSetting? themeMode,
    String? locale,
    int? exerciseCreditPercentage,
    bool? exerciseCreditEnabled,
    bool? showNetCalories,
    int? waterGoalGlasses,
    int? glassSizeMl,
    bool? profileCompleted,
    bool? isDemo,
    String? email,
    DateTime? deletionRequestedAt,
    DateTime? updatedAt,
  }) => UserProfile(
    id: id,
    displayName: displayName ?? this.displayName,
    avatarPath: avatarPath ?? this.avatarPath,
    biologicalSex: biologicalSex ?? this.biologicalSex,
    birthDate: birthDate ?? this.birthDate,
    heightCm: heightCm ?? this.heightCm,
    activityLevel: activityLevel ?? this.activityLevel,
    timezone: timezone ?? this.timezone,
    unitSystem: unitSystem ?? this.unitSystem,
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    exerciseCreditPercentage:
        exerciseCreditPercentage ?? this.exerciseCreditPercentage,
    exerciseCreditEnabled:
        exerciseCreditEnabled ?? this.exerciseCreditEnabled,
    showNetCalories: showNetCalories ?? this.showNetCalories,
    waterGoalGlasses: waterGoalGlasses ?? this.waterGoalGlasses,
    glassSizeMl: glassSizeMl ?? this.glassSizeMl,
    profileCompleted: profileCompleted ?? this.profileCompleted,
    isDemo: isDemo ?? this.isDemo,
    email: email ?? this.email,
    deletionRequestedAt: deletionRequestedAt ?? this.deletionRequestedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'displayName': displayName,
    'avatarPath': avatarPath,
    'biologicalSex': biologicalSex.wire,
    'birthDate': birthDate?.toIso8601String(),
    'heightCm': heightCm,
    'activityLevel': activityLevel.wire,
    'timezone': timezone,
    'unitSystem': unitSystem.wire,
    'themeMode': themeMode.wire,
    'locale': locale,
    'exerciseCreditPercentage': exerciseCreditPercentage,
    'exerciseCreditEnabled': exerciseCreditEnabled,
    'showNetCalories': showNetCalories,
    'waterGoalGlasses': waterGoalGlasses,
    'glassSizeMl': glassSizeMl,
    'profileCompleted': profileCompleted,
    'isDemo': isDemo,
    'email': email,
    'deletionRequestedAt': deletionRequestedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static UserProfile fromJson(Map<String, dynamic> j) => UserProfile(
    id: j['id'] as String,
    displayName: j['displayName'] as String?,
    avatarPath: j['avatarPath'] as String?,
    biologicalSex: BiologicalSex.fromWire(j['biologicalSex'] as String),
    birthDate: j['birthDate'] == null
        ? null
        : DateTime.parse(j['birthDate'] as String),
    heightCm: (j['heightCm'] as num?)?.toDouble(),
    activityLevel: ActivityLevel.fromWire(j['activityLevel'] as String),
    timezone: j['timezone'] as String,
    unitSystem: UnitSystem.values.firstWhere(
      (e) => e.wire == j['unitSystem'],
      orElse: () => UnitSystem.metric,
    ),
    themeMode: ThemeModeSetting.values.firstWhere(
      (e) => e.wire == j['themeMode'],
      orElse: () => ThemeModeSetting.system,
    ),
    locale: j['locale'] as String,
    exerciseCreditPercentage: j['exerciseCreditPercentage'] as int,
    exerciseCreditEnabled: j['exerciseCreditEnabled'] as bool,
    showNetCalories: j['showNetCalories'] as bool,
    waterGoalGlasses: (j['waterGoalGlasses'] as num?)?.toInt() ?? 8,
    glassSizeMl: (j['glassSizeMl'] as num?)?.toInt() ?? 250,
    profileCompleted: j['profileCompleted'] as bool,
    isDemo: j['isDemo'] as bool? ?? false,
    email: j['email'] as String?,
    deletionRequestedAt: j['deletionRequestedAt'] == null
        ? null
        : DateTime.parse(j['deletionRequestedAt'] as String),
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}
