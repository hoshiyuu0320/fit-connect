import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

class WeightRepository {
  final _supabase = SupabaseService.client;

  /// 体重記録を取得（期間フィルタ付き）
  Future<List<WeightRecord>> getWeightRecords({
    required String clientId,
    PeriodFilter? period,
  }) async {
    var query =
        _supabase.from('weight_records').select().eq('client_id', clientId);

    // 期間フィルタを適用
    if (period != null && period != PeriodFilter.all) {
      final startDate = period.getStartDate();
      query = query.gte('recorded_at', startDate.toIso8601String());
    }

    final response = await query.order('recorded_at', ascending: false);
    return (response as List)
        .map((json) => WeightRecord.fromJson(json))
        .toList();
  }

  /// 最新の体重記録を取得
  Future<WeightRecord?> getLatestWeightRecord(String clientId) async {
    final response = await _supabase
        .from('weight_records')
        .select()
        .eq('client_id', clientId)
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return WeightRecord.fromJson(response);
  }

  /// 体重記録を作成
  Future<WeightRecord> createWeightRecord({
    required String clientId,
    required double weight,
    String? notes,
    DateTime? recordedAt,
  }) async {
    final response = await _supabase
        .from('weight_records')
        .insert({
          'client_id': clientId,
          'weight': weight,
          'notes': notes,
          'recorded_at': (recordedAt ?? DateTime.now()).toIso8601String(),
          'source': 'manual',
        })
        .select()
        .single();

    return WeightRecord.fromJson(response);
  }

  /// 体重記録を作成（source指定あり、HealthKit連携用）
  Future<WeightRecord> createWeightRecordWithSource({
    required String clientId,
    required double weight,
    required DateTime recordedAt,
    required String source,
    String? notes,
  }) async {
    final response = await _supabase
        .from('weight_records')
        .insert({
          'client_id': clientId,
          'weight': weight,
          'notes': notes,
          'recorded_at': recordedAt.toIso8601String(),
          'source': source,
        })
        .select()
        .single();

    return WeightRecord.fromJson(response);
  }

  /// 体重記録を更新
  Future<WeightRecord> updateWeightRecord({
    required String id,
    double? weight,
    String? notes,
    DateTime? recordedAt,
  }) async {
    final updateData = <String, dynamic>{};
    if (weight != null) updateData['weight'] = weight;
    if (notes != null) updateData['notes'] = notes;
    if (recordedAt != null) {
      updateData['recorded_at'] = recordedAt.toIso8601String();
    }

    final response = await _supabase
        .from('weight_records')
        .update(updateData)
        .eq('id', id)
        .select()
        .single();

    return WeightRecord.fromJson(response);
  }

  /// 体重記録を削除
  Future<void> deleteWeightRecord(String id) async {
    await _supabase.from('weight_records').delete().eq('id', id);
  }

  /// 指定期間の統計を取得
  Future<Map<String, double>> getWeightStats({
    required String clientId,
    required PeriodFilter period,
  }) async {
    final records = await getWeightRecords(
      clientId: clientId,
      period: period,
    );

    if (records.isEmpty) {
      return {
        'average': 0.0,
        'min': 0.0,
        'max': 0.0,
        'change': 0.0,
      };
    }

    final weights = records.map((r) => r.weight).toList();
    final average = weights.reduce((a, b) => a + b) / weights.length;
    final min = weights.reduce((a, b) => a < b ? a : b);
    final max = weights.reduce((a, b) => a > b ? a : b);
    final change = records.first.weight - records.last.weight;

    return {
      'average': average,
      'min': min,
      'max': max,
      'change': change,
    };
  }
}
