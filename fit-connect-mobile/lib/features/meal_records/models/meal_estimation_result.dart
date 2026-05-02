import 'package:json_annotation/json_annotation.dart';

part 'meal_estimation_result.g.dart';

@JsonSerializable()
class MealEstimationResult {
  final List<EstimatedFood> foods;
  final EstimationTotals totals;

  const MealEstimationResult({required this.foods, required this.totals});

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
