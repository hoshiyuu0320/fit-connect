// lib/features/meal_records/data/meal_estimation_api.dart
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

/// - [rateLimit]: 日次上限超過（429 'RATE_LIMIT'）。画像リクエストのみ拒否
/// - [freeQuotaExceeded]: Freeプランの月次プール使い切り（429 'FREE_QUOTA_EXCEEDED'）。全ブロック
/// - [monthlyQuotaExceeded]: 有料プランの顧客あたり月次上限超過（429 'MONTHLY_QUOTA_EXCEEDED'）。
///   画像リクエストのみ拒否（テキスト推定は通る）
enum MealEstimationErrorCode {
  forbidden,
  rateLimit,
  freeQuotaExceeded,
  monthlyQuotaExceeded,
  invalidInput,
  estimationFailed,
  emptyResult,
  network,
}

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
    List<String> imageUrls = const [],
    String inputKind = 'photo', // 'photo' | 'screenshot'
  }) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'estimate-meal-nutrition',
        body: {
          'meal_type': mealType,
          'content': content,
          if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
          'input_kind': inputKind,
        },
      ).timeout(const Duration(seconds: 45));

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
      throw MealEstimationException(codeFromServerError(errCode), msg);
    } on MealEstimationException {
      rethrow;
    } catch (e) {
      throw MealEstimationException(MealEstimationErrorCode.network, e.toString());
    }
  }

  /// Edge Function の {error: '...'} 文字列を [MealEstimationErrorCode] にマップする。
  /// 未知のコード・欠落時は estimationFailed にフォールバック。
  @visibleForTesting
  static MealEstimationErrorCode codeFromServerError(String? errCode) {
    switch (errCode) {
      case 'FORBIDDEN':
        return MealEstimationErrorCode.forbidden;
      case 'RATE_LIMIT':
        return MealEstimationErrorCode.rateLimit;
      case 'FREE_QUOTA_EXCEEDED':
        return MealEstimationErrorCode.freeQuotaExceeded;
      case 'MONTHLY_QUOTA_EXCEEDED':
        return MealEstimationErrorCode.monthlyQuotaExceeded;
      case 'INVALID_INPUT':
        return MealEstimationErrorCode.invalidInput;
      case 'EMPTY_RESULT':
        return MealEstimationErrorCode.emptyResult;
      case 'ESTIMATION_FAILED':
      default:
        return MealEstimationErrorCode.estimationFailed;
    }
  }
}
