import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';

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

  test('MealRecord.aiFoods deserializes typed EstimatedFood list', () {
    final json = {
      'id': '00000000-0000-0000-0000-000000000001',
      'client_id': '00000000-0000-0000-0000-000000000002',
      'meal_type': 'lunch',
      'recorded_at': '2026-05-02T12:00:00Z',
      'created_at': '2026-05-02T12:00:00Z',
      'updated_at': '2026-05-02T12:00:00Z',
      'source': 'message',
      'estimated_by_ai': true,
      'calories': 850,
      'protein_g': 32,
      'fat_g': 28,
      'carbs_g': 95,
      'ai_foods': [
        {'name': '牛丼大盛り', 'calories': 850, 'protein_g': 32, 'fat_g': 28, 'carbs_g': 95},
      ],
    };
    final record = MealRecord.fromJson(json);
    expect(record.estimatedByAi, isTrue);
    expect(record.aiFoods, hasLength(1));
    expect(record.aiFoods!.first, isA<EstimatedFood>());
    expect(record.aiFoods!.first.name, '牛丼大盛り');
    expect(record.proteinG, 32);
  });
}
