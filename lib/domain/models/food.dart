import '../enums/enums.dart';

/// Una porción con nombre del alimento ("1 taza", "1 rebanada").
class FoodPortion {
  const FoodPortion({required this.label, required this.grams});

  final String label;
  final double grams;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'label': label,
    'grams': grams,
  };

  static FoodPortion fromJson(Map<String, dynamic> j) => FoodPortion(
    label: j['label'] as String,
    grams: (j['grams'] as num).toDouble(),
  );
}

/// Alimento del catálogo propio o de un catálogo externo (10-types §Food).
///
/// Un alimento creado por el usuario es privado; los de catálogos externos se
/// cachean en una tabla pública de solo lectura (RN-18).
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.source,
    required this.servingSize,
    required this.servingUnit,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.userId,
    this.brand,
    this.barcode,
    this.externalId,
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
    this.portions = const <FoodPortion>[],
    this.isFavorite = false,
    this.nutrientWarning = false,
  });

  final String id;
  final String? userId;
  final String name;
  final String? brand;
  final String? barcode;
  final FoodSource source;
  final String? externalId;

  /// Tamaño de la porción de referencia, en [servingUnit].
  final double servingSize;
  final String servingUnit;

  /// Valores **por porción de referencia**.
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;
  final List<FoodPortion> portions;
  final bool isFavorite;

  /// Marca de auditoría cuando los macros no cuadran con las kcal (§5).
  final bool nutrientWarning;

  /// "Yogur natural · La Serenísima".
  String get displayName => brand == null ? name : '$name · $brand';

  /// kcal por 100 g, para la tabla nutricional de S-17.
  double get kcalPer100g =>
      servingSize <= 0 ? 0 : kcal / servingSize * 100;

  Food copyWith({
    String? name,
    String? brand,
    bool? isFavorite,
    int? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) => Food(
    id: id,
    userId: userId,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    barcode: barcode,
    source: source,
    externalId: externalId,
    servingSize: servingSize,
    servingUnit: servingUnit,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    fiberG: fiberG,
    sugarG: sugarG,
    sodiumMg: sodiumMg,
    portions: portions,
    isFavorite: isFavorite ?? this.isFavorite,
    nutrientWarning: nutrientWarning,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'userId': userId,
    'name': name,
    'brand': brand,
    'barcode': barcode,
    'source': source.wire,
    'externalId': externalId,
    'servingSize': servingSize,
    'servingUnit': servingUnit,
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'fiberG': fiberG,
    'sugarG': sugarG,
    'sodiumMg': sodiumMg,
    'portions': portions.map((p) => p.toJson()).toList(),
    'isFavorite': isFavorite,
    'nutrientWarning': nutrientWarning,
  };

  static Food fromJson(Map<String, dynamic> j) => Food(
    id: j['id'] as String,
    userId: j['userId'] as String?,
    name: j['name'] as String,
    brand: j['brand'] as String?,
    barcode: j['barcode'] as String?,
    source: FoodSource.values.firstWhere(
      (e) => e.wire == j['source'],
      orElse: () => FoodSource.user,
    ),
    externalId: j['externalId'] as String?,
    servingSize: (j['servingSize'] as num).toDouble(),
    servingUnit: j['servingUnit'] as String,
    kcal: j['kcal'] as int,
    proteinG: (j['proteinG'] as num).toDouble(),
    carbsG: (j['carbsG'] as num).toDouble(),
    fatG: (j['fatG'] as num).toDouble(),
    fiberG: (j['fiberG'] as num?)?.toDouble(),
    sugarG: (j['sugarG'] as num?)?.toDouble(),
    sodiumMg: (j['sodiumMg'] as num?)?.toDouble(),
    portions: (j['portions'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => FoodPortion.fromJson(e as Map<String, dynamic>))
        .toList(),
    isFavorite: j['isFavorite'] as bool? ?? false,
    nutrientWarning: j['nutrientWarning'] as bool? ?? false,
  );
}
