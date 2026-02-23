import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

class MealRepository {
  final _supabase = SupabaseService.client;

  /// 食事記録を取得（期間フィルタ付き）
  Future<List<MealRecord>> getMealRecords({
    required String clientId,
    PeriodFilter? period,
    String? mealType,
  }) async {
    var query =
        _supabase.from('meal_records').select().eq('client_id', clientId);

    // 期間フィルタを適用
    if (period != null && period != PeriodFilter.all) {
      final startDate = period.getStartDate();
      query = query.gte('recorded_at', startDate.toIso8601String());
    }

    // 食事タイプフィルタを適用
    if (mealType != null) {
      query = query.eq('meal_type', mealType);
    }

    final response = await query.order('recorded_at', ascending: false);
    return (response as List).map((json) => MealRecord.fromJson(json)).toList();
  }

  /// 指定日の食事記録数を取得（カレンダー表示用）
  Future<Map<DateTime, int>> getMealRecordCounts({
    required String clientId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _supabase
        .from('meal_records')
        .select()
        .eq('client_id', clientId)
        .gte('recorded_at', startDate.toIso8601String())
        .lte('recorded_at', endDate.toIso8601String());

    final records =
        (response as List).map((json) => MealRecord.fromJson(json)).toList();

    // 日付ごとにグループ化
    final counts = <DateTime, int>{};
    for (final record in records) {
      final date = DateTime(
        record.recordedAt.year,
        record.recordedAt.month,
        record.recordedAt.day,
      );
      counts[date] = (counts[date] ?? 0) + 1;
    }

    return counts;
  }

  /// 食事記録を作成
  Future<MealRecord> createMealRecord({
    required String clientId,
    required String mealType,
    String? notes,
    List<String>? images,
    double? calories,
    DateTime? recordedAt,
  }) async {
    final response = await _supabase
        .from('meal_records')
        .insert({
          'client_id': clientId,
          'meal_type': mealType,
          'notes': notes,
          'images': images,
          'calories': calories,
          'recorded_at': (recordedAt ?? DateTime.now()).toIso8601String(),
          'source': 'manual',
        })
        .select()
        .single();

    return MealRecord.fromJson(response);
  }

  /// 食事記録を更新
  Future<MealRecord> updateMealRecord({
    required String id,
    String? mealType,
    String? notes,
    List<String>? images,
    double? calories,
    DateTime? recordedAt,
  }) async {
    final updateData = <String, dynamic>{};
    if (mealType != null) updateData['meal_type'] = mealType;
    if (notes != null) updateData['notes'] = notes;
    if (images != null) updateData['images'] = images;
    if (calories != null) updateData['calories'] = calories;
    if (recordedAt != null) {
      updateData['recorded_at'] = recordedAt.toIso8601String();
    }

    final response = await _supabase
        .from('meal_records')
        .update(updateData)
        .eq('id', id)
        .select()
        .single();

    return MealRecord.fromJson(response);
  }

  /// 食事記録を削除
  Future<void> deleteMealRecord(String id) async {
    await _supabase.from('meal_records').delete().eq('id', id);
  }

  /// 今日の食事記録数を取得
  Future<int> getTodayMealCount(String clientId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final response = await _supabase
        .from('meal_records')
        .select('id')
        .eq('client_id', clientId)
        .gte('recorded_at', startOfDay.toIso8601String())
        .lt('recorded_at', endOfDay.toIso8601String());

    return (response as List).length;
  }
}
