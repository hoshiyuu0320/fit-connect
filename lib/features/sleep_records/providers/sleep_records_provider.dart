import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';

part 'sleep_records_provider.g.dart';

/// 睡眠レコードリスト
@riverpod
class SleepRecords extends _$SleepRecords {
  @override
  Future<List<SleepRecord>> build({int limit = 30}) async {
    final clientId = ref.watch(currentClientIdProvider);
    if (clientId == null) return [];

    final res = await SupabaseService.client
        .from('sleep_records')
        .select()
        .eq('client_id', clientId)
        .order('recorded_date', ascending: false)
        .limit(limit);

    return (res as List)
        .map((e) => SleepRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// HealthKit同期時 - 客観データを UPSERT、wakeup_rating は保持
  /// wakeup_rating をペイロードに含めないことで、既存評価を保護
  Future<void> upsertObjectiveData({
    required String recordedDate,
    required DateTime bedTime,
    required DateTime wakeTime,
    required int totalSleepMinutes,
    required int deepMinutes,
    required int lightMinutes,
    required int remMinutes,
    required int awakeMinutes,
  }) async {
    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) return;

    await SupabaseService.client.from('sleep_records').upsert(
      {
        'client_id': clientId,
        'recorded_date': recordedDate,
        'bed_time': bedTime.toUtc().toIso8601String(),
        'wake_time': wakeTime.toUtc().toIso8601String(),
        'total_sleep_minutes': totalSleepMinutes,
        'deep_minutes': deepMinutes,
        'light_minutes': lightMinutes,
        'rem_minutes': remMinutes,
        'awake_minutes': awakeMinutes,
        'source': 'healthkit',
      },
      onConflict: 'client_id,recorded_date',
    );

    ref.invalidateSelf();
    ref.invalidate(todaySleepRecordProvider);
    ref.invalidate(recentSleepRecordsProvider);
  }

  /// 手動評価 UPSERT - 既存レコードあれば rating のみ更新、無ければ manual で新規作成
  Future<void> upsertWakeupRating({
    required String recordedDate,
    required WakeupRating rating,
  }) async {
    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) throw StateError('No client id');

    final ratingValue = rating.index + 1; // groggy=1, okay=2, refreshed=3

    // 既存確認
    final existing = await SupabaseService.client
        .from('sleep_records')
        .select('id')
        .eq('client_id', clientId)
        .eq('recorded_date', recordedDate)
        .maybeSingle();

    if (existing == null) {
      // 新規作成: source='manual'
      await SupabaseService.client.from('sleep_records').insert({
        'client_id': clientId,
        'recorded_date': recordedDate,
        'wakeup_rating': ratingValue,
        'source': 'manual',
      });
    } else {
      // 既存更新: wakeup_rating のみ、source は保持
      await SupabaseService.client
          .from('sleep_records')
          .update({'wakeup_rating': ratingValue})
          .eq('id', existing['id'] as String);
    }

    ref.invalidateSelf();
    ref.invalidate(todaySleepRecordProvider);
    ref.invalidate(recentSleepRecordsProvider);
  }
}

/// 今日の睡眠レコード（1件のみ）
@riverpod
Future<SleepRecord?> todaySleepRecord(TodaySleepRecordRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return null;

  final today = todayJstDateKey();
  final res = await SupabaseService.client
      .from('sleep_records')
      .select()
      .eq('client_id', clientId)
      .eq('recorded_date', today)
      .maybeSingle();

  return res == null ? null : SleepRecord.fromJson(res);
}

/// 直近 N 日間の睡眠レコード（週間グラフ用）
@riverpod
Future<List<SleepRecord>> recentSleepRecords(
  RecentSleepRecordsRef ref, {
  int days = 7,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return [];

  final from = jstDateKeyDaysAgo(days - 1); // daysDayAgo が0なら今日
  final res = await SupabaseService.client
      .from('sleep_records')
      .select()
      .eq('client_id', clientId)
      .gte('recorded_date', from)
      .order('recorded_date', ascending: true);

  return (res as List)
      .map((e) => SleepRecord.fromJson(e as Map<String, dynamic>))
      .toList();
}
