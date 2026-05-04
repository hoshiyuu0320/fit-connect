// lib/features/meal_records/data/meal_estimation_api.dart
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

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
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return MealEstimationResult.fromJson(data);
      }
      throw MealEstimationException(
        MealEstimationErrorCode.estimationFailed,
        'Unexpected success body: ${data.runtimeType}',
      );
    } on FunctionException catch (e) {
      // functions_client は non-2xx で例外を投げる。Edge Function の {error, message} は e.details に入る
      final details = e.details;
      final errCode = (details is Map && details['error'] is String)
          ? details['error'] as String
          : null;
      final msg = (details is Map && details['message'] is String)
          ? details['message'] as String
          : (e.reasonPhrase ?? 'Unknown error');
      switch (errCode) {
        case 'FORBIDDEN':
          throw MealEstimationException(MealEstimationErrorCode.forbidden, msg);
        case 'RATE_LIMIT':
          throw MealEstimationException(MealEstimationErrorCode.rateLimit, msg);
        case 'INVALID_INPUT':
          throw MealEstimationException(MealEstimationErrorCode.invalidInput, msg);
        case 'ESTIMATION_FAILED':
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
