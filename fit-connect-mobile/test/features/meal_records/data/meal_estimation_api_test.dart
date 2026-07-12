import 'package:fit_connect_mobile/features/meal_records/data/meal_estimation_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MealEstimationApi.codeFromServerError', () {
    test('maps known server error strings to enum values', () {
      expect(
        MealEstimationApi.codeFromServerError('FORBIDDEN'),
        MealEstimationErrorCode.forbidden,
      );
      expect(
        MealEstimationApi.codeFromServerError('RATE_LIMIT'),
        MealEstimationErrorCode.rateLimit,
      );
      expect(
        MealEstimationApi.codeFromServerError('FREE_QUOTA_EXCEEDED'),
        MealEstimationErrorCode.freeQuotaExceeded,
      );
      expect(
        MealEstimationApi.codeFromServerError('MONTHLY_QUOTA_EXCEEDED'),
        MealEstimationErrorCode.monthlyQuotaExceeded,
      );
      expect(
        MealEstimationApi.codeFromServerError('INVALID_INPUT'),
        MealEstimationErrorCode.invalidInput,
      );
      expect(
        MealEstimationApi.codeFromServerError('EMPTY_RESULT'),
        MealEstimationErrorCode.emptyResult,
      );
      expect(
        MealEstimationApi.codeFromServerError('ESTIMATION_FAILED'),
        MealEstimationErrorCode.estimationFailed,
      );
    });

    test('falls back to estimationFailed for unknown or missing codes', () {
      expect(
        MealEstimationApi.codeFromServerError('SOMETHING_NEW'),
        MealEstimationErrorCode.estimationFailed,
      );
      expect(
        MealEstimationApi.codeFromServerError(null),
        MealEstimationErrorCode.estimationFailed,
      );
    });
  });
}
