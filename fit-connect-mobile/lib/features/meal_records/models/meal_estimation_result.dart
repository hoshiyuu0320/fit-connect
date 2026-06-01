import 'package:json_annotation/json_annotation.dart';

part 'meal_estimation_result.g.dart';

@JsonSerializable()
class MealEstimationResult {
  final List<EstimatedFood> foods;
  final EstimationTotals totals;

  /// スクショ取り込み時に Claude が検出したアプリ名（例: 'あすけん', 'unknown'）。
  /// 料理写真・テキスト推定では null。
  @JsonKey(name: 'app_name')
  final String? appName;

  const MealEstimationResult({
    required this.foods,
    required this.totals,
    this.appName,
  });

  factory MealEstimationResult.fromJson(Map<String, dynamic> json) =>
      _$MealEstimationResultFromJson(json);
  Map<String, dynamic> toJson() => _$MealEstimationResultToJson(this);
}

@JsonSerializable()
class EstimatedFood {
  final String name;
  final double calories;
  @JsonKey(name: 'protein_g')
  final double proteinG;
  @JsonKey(name: 'fat_g')
  final double fatG;
  @JsonKey(name: 'carbs_g')
  final double carbsG;

  const EstimatedFood({
    required this.name,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  factory EstimatedFood.fromJson(Map<String, dynamic> json) =>
      _$EstimatedFoodFromJson(json);
  Map<String, dynamic> toJson() => _$EstimatedFoodToJson(this);
}

@JsonSerializable()
class EstimationTotals {
  final double calories;
  @JsonKey(name: 'protein_g')
  final double proteinG;
  @JsonKey(name: 'fat_g')
  final double fatG;
  @JsonKey(name: 'carbs_g')
  final double carbsG;

  const EstimationTotals({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  EstimationTotals copyWith({double? calories, double? proteinG, double? fatG, double? carbsG}) =>
      EstimationTotals(
        calories: calories ?? this.calories,
        proteinG: proteinG ?? this.proteinG,
        fatG: fatG ?? this.fatG,
        carbsG: carbsG ?? this.carbsG,
      );

  factory EstimationTotals.fromJson(Map<String, dynamic> json) =>
      _$EstimationTotalsFromJson(json);
  Map<String, dynamic> toJson() => _$EstimationTotalsToJson(this);
}
