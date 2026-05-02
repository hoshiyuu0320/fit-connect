import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';

void main() {
  test('parses Edge Function response', () {
    final json = {
      'foods': [
        {'name': '牛丼大盛り', 'calories': 850, 'protein_g': 32, 'fat_g': 28, 'carbs_g': 95},
      ],
      'totals': {'calories': 850, 'protein_g': 32, 'fat_g': 28, 'carbs_g': 95},
    };
    final result = MealEstimationResult.fromJson(json);
    expect(result.foods, hasLength(1));
    expect(result.foods.first.name, '牛丼大盛り');
    expect(result.totals.calories, 850);
    expect(result.totals.proteinG, 32);
  });
}
