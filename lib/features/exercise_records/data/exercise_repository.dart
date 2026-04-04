import 'package:fit_connect_mobile/features/exercise_records/models/exercise_record_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

class ExerciseRepository {
  final _supabase = SupabaseService.client;

  /// 運動記録を取得（期間フィルタ付き）
  Future<List<ExerciseRecord>> getExerciseRecords({
    required String clientId,
    PeriodFilter? period,
    String? exerciseType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query =
        _supabase.from('exercise_records').select().eq('client_id', clientId);

    // 期間フィルタを適用
    if (startDate != null || endDate != null) {
      // startDate/endDate が指定された場合は period を無視
      if (startDate != null) {
        query = query.gte('recorded_at', startDate.toUtc().toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('recorded_at', endDate.toUtc().toIso8601String());
      }
    } else if (period != null && period != PeriodFilter.all) {
      final periodStart = period.getStartDate();
      query = query.gte('recorded_at', periodStart.toIso8601String());
    }

    // 運動タイプフィルタを適用
    if (exerciseType != null) {
      query = query.eq('exercise_type', exerciseType);
    }

    final response = await query.order('recorded_at', ascending: false);
    return (response as List)
        .map((json) => ExerciseRecord.fromJson(json))
        .toList();
  }

  /// 指定期間の運動回数を取得（タイプ別）
  Future<Map<String, int>> getExerciseTypeCounts({
    required String clientId,
    required PeriodFilter period,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final records = await getExerciseRecords(
      clientId: clientId,
      period: period,
      startDate: startDate,
      endDate: endDate,
    );

    final counts = <String, int>{};
    for (final record in records) {
      counts[record.exerciseType] = (counts[record.exerciseType] ?? 0) + 1;
    }

    return counts;
  }

  /// 週間カレンダー用のデータを取得
  Future<Map<DateTime, List<String>>> getWeeklyExerciseData({
    required String clientId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _supabase
        .from('exercise_records')
        .select()
        .eq('client_id', clientId)
        .gte('recorded_at', startDate.toIso8601String())
        .lte('recorded_at', endDate.toIso8601String())
        .order('recorded_at', ascending: false);

    final records = (response as List)
        .map((json) => ExerciseRecord.fromJson(json))
        .toList();

    // 日付ごとに運動タイプをグループ化
    final data = <DateTime, List<String>>{};
    for (final record in records) {
      final date = DateTime(
        record.recordedAt.year,
        record.recordedAt.month,
        record.recordedAt.day,
      );
      if (!data.containsKey(date)) {
        data[date] = [];
      }
      data[date]!.add(record.exerciseType);
    }

    return data;
  }

  /// 運動記録を作成
  Future<ExerciseRecord> createExerciseRecord({
    required String clientId,
    required String exerciseType,
    String? memo,
    List<String>? images,
    int? duration,
    double? distance,
    double? calories,
    DateTime? recordedAt,
  }) async {
    final response = await _supabase
        .from('exercise_records')
        .insert({
          'client_id': clientId,
          'exercise_type': exerciseType,
          'memo': memo,
          'images': images,
          'duration': duration,
          'distance': distance,
          'calories': calories,
          'recorded_at': (recordedAt ?? DateTime.now()).toIso8601String(),
          'source': 'manual',
        })
        .select()
        .single();

    return ExerciseRecord.fromJson(response);
  }

  /// 運動記録を更新
  Future<ExerciseRecord> updateExerciseRecord({
    required String id,
    String? exerciseType,
    String? memo,
    List<String>? images,
    int? duration,
    double? distance,
    double? calories,
    DateTime? recordedAt,
  }) async {
    final updateData = <String, dynamic>{};
    if (exerciseType != null) updateData['exercise_type'] = exerciseType;
    if (memo != null) updateData['memo'] = memo;
    if (images != null) updateData['images'] = images;
    if (duration != null) updateData['duration'] = duration;
    if (distance != null) updateData['distance'] = distance;
    if (calories != null) updateData['calories'] = calories;
    if (recordedAt != null) {
      updateData['recorded_at'] = recordedAt.toIso8601String();
    }

    final response = await _supabase
        .from('exercise_records')
        .update(updateData)
        .eq('id', id)
        .select()
        .single();

    return ExerciseRecord.fromJson(response);
  }

  /// 運動記録を削除
  Future<void> deleteExerciseRecord(String id) async {
    await _supabase.from('exercise_records').delete().eq('id', id);
  }

  /// 月カレンダー用の日別運動回数を取得
  Future<Map<DateTime, int>> getExerciseRecordCounts({
    required String clientId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _supabase
        .from('exercise_records')
        .select('recorded_at')
        .eq('client_id', clientId)
        .gte('recorded_at', startDate.toUtc().toIso8601String())
        .lte('recorded_at', endDate.toUtc().toIso8601String());

    final counts = <DateTime, int>{};
    for (final row in (response as List)) {
      final recordedAt = DateTime.parse(row['recorded_at'] as String).toLocal();
      final date = DateTime(recordedAt.year, recordedAt.month, recordedAt.day);
      counts[date] = (counts[date] ?? 0) + 1;
    }
    return counts;
  }

  /// 期間内の消費カロリー合計を取得
  Future<double> getTotalCalories({
    required String clientId,
    required PeriodFilter period,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final records = await getExerciseRecords(
      clientId: clientId,
      period: period,
      startDate: startDate,
      endDate: endDate,
    );

    double total = 0;
    for (final record in records) {
      if (record.calories != null) {
        total += record.calories!;
      }
    }
    return total;
  }

  /// 今週の運動回数を取得
  Future<int> getWeeklyExerciseCount(String clientId) async {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startDate =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final response = await _supabase
        .from('exercise_records')
        .select('id')
        .eq('client_id', clientId)
        .gte('recorded_at', startDate.toIso8601String());

    return (response as List).length;
  }
}
