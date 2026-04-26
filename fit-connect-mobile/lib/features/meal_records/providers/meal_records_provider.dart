import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/features/meal_records/data/meal_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

part 'meal_records_provider.g.dart';

/// MealRepositoryのProvider
@riverpod
MealRepository mealRepository(MealRepositoryRef ref) {
  return MealRepository();
}

/// 食事記録リストを取得するProvider
@riverpod
class MealRecords extends _$MealRecords {
  @override
  Future<List<MealRecord>> build({
    PeriodFilter period = PeriodFilter.month,
    String? mealType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final clientId = ref.watch(currentClientIdProvider);
    if (clientId == null) return [];

    final repository = ref.watch(mealRepositoryProvider);
    return repository.getMealRecords(
      clientId: clientId,
      period: period,
      mealType: mealType,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// 食事記録を追加
  Future<void> addRecord({
    required String mealType,
    String? notes,
    List<String>? images,
    double? calories,
    DateTime? recordedAt,
  }) async {
    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) throw Exception('Client not found');

    final repository = ref.read(mealRepositoryProvider);
    await repository.createMealRecord(
      clientId: clientId,
      mealType: mealType,
      notes: notes,
      images: images,
      calories: calories,
      recordedAt: recordedAt,
    );

    ref.invalidateSelf();
  }

  /// 食事記録を更新
  Future<void> updateRecord({
    required String id,
    String? mealType,
    String? notes,
    List<String>? images,
    double? calories,
    DateTime? recordedAt,
  }) async {
    final repository = ref.read(mealRepositoryProvider);
    await repository.updateMealRecord(
      id: id,
      mealType: mealType,
      notes: notes,
      images: images,
      calories: calories,
      recordedAt: recordedAt,
    );

    ref.invalidateSelf();
  }

  /// 食事記録を削除
  Future<void> deleteRecord(String id) async {
    final repository = ref.read(mealRepositoryProvider);
    await repository.deleteMealRecord(id);

    ref.invalidateSelf();
  }
}

/// 今日の食事記録数を取得するProvider
@riverpod
Future<int> todayMealCount(TodayMealCountRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return 0;

  final repository = ref.watch(mealRepositoryProvider);
  return repository.getTodayMealCount(clientId);
}

/// 月間の食事記録カウント（カレンダー用）を取得するProvider
@riverpod
Future<Map<DateTime, int>> mealRecordCounts(
  MealRecordCountsRef ref, {
  required DateTime startDate,
  required DateTime endDate,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return {};

  final repository = ref.watch(mealRepositoryProvider);
  return repository.getMealRecordCounts(
    clientId: clientId,
    startDate: startDate,
    endDate: endDate,
  );
}
