// lib/features/meal_records/data/meal_estimation_api.dart
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

enum MealEstimationErrorCode { forbidden, rateLimit, invalidInput, estimationFailed, network }

class MealEstimationException implements Exception {
  final MealEstimationErrorCode code;
  final String message;
  MealEstimationException(this.code, this.message);
  @override
  String toString() => 'MealEstimationException($code): $message';
}

class MealEstimationApi {
  static Future<MealEstimationResult> estimate({
    required String mealType, // 'breakfast' | 'lunch' | 'dinner' | 'snack'
    required String content,
  }) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'estimate-meal-nutrition',
        body: {
          'meal_type': mealType,
          'content': content,
          'image_urls': const <String>[],
        },
      );

      final status = response.status;
      final data = response.data;
      if (status >= 200 && status < 300 && data is Map<String, dynamic>) {
        return MealEstimationResult.fromJson(data);
      }

      // エラーマッピング
      final errCode = (data is Map && data['error'] is String) ? data['error'] as String : null;
      final msg = (data is Map && data['message'] is String) ? data['message'] as String : 'Unknown error';
      switch (errCode) {
        case 'FORBIDDEN':
          throw MealEstimationException(MealEstimationErrorCode.forbidden, msg);
        case 'RATE_LIMIT':
          throw MealEstimationException(MealEstimationErrorCode.rateLimit, msg);
        case 'INVALID_INPUT':
          throw MealEstimationException(MealEstimationErrorCode.invalidInput, msg);
        default:
          throw MealEstimationException(MealEstimationErrorCode.estimationFailed, msg);
      }
    } on MealEstimationException {
      rethrow;
    } catch (e) {
      throw MealEstimationException(MealEstimationErrorCode.network, e.toString());
    }
  }
}
