// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meal_estimation_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MealEstimationResult _$MealEstimationResultFromJson(
        Map<String, dynamic> json) =>
    MealEstimationResult(
      foods: (json['foods'] as List<dynamic>)
          .map((e) => EstimatedFood.fromJson(e as Map<String, dynamic>))
          .toList(),
      totals: EstimationTotals.fromJson(json['totals'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$MealEstimationResultToJson(
        MealEstimationResult instance) =>
    <String, dynamic>{
      'foods': instance.foods,
      'totals': instance.totals,
    };

EstimatedFood _$EstimatedFoodFromJson(Map<String, dynamic> json) =>
    EstimatedFood(
      name: json['name'] as String,
      calories: (json['calories'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      carbsG: (json['carbs_g'] as num).toDouble(),
    );

Map<String, dynamic> _$EstimatedFoodToJson(EstimatedFood instance) =>
    <String, dynamic>{
      'name': instance.name,
      'calories': instance.calories,
      'protein_g': instance.proteinG,
      'fat_g': instance.fatG,
      'carbs_g': instance.carbsG,
    };

EstimationTotals _$EstimationTotalsFromJson(Map<String, dynamic> json) =>
    EstimationTotals(
      calories: (json['calories'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      carbsG: (json['carbs_g'] as num).toDouble(),
    );

Map<String, dynamic> _$EstimationTotalsToJson(EstimationTotals instance) =>
    <String, dynamic>{
      'calories': instance.calories,
      'protein_g': instance.proteinG,
      'fat_g': instance.fatG,
      'carbs_g': instance.carbsG,
    };
