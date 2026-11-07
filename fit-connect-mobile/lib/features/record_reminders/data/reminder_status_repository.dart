import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestList, SupabaseClient;
import 'package:timezone/timezone.dart' as tz;

import 'package:fit_connect_mobile/features/record_reminders/domain/reminder_planner.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

/// リマインダーの予約に要る「今日の記録」と「運動の予定日」を読む（設計 §3・§4.2）。
///
/// 読むのはクライアント本人の行だけ（既存の RLS の範囲）。失敗は呼び出し元へ投げる
/// （呼び出し元が同じ日に読めた最後の結果へ戻す）。
class ReminderStatusRepository {
  /// [client] はテストで偽のサーバーへ向けたクライアントを渡すためのもの（省略時はアプリ共通のクライアント）
  ReminderStatusRepository({SupabaseClient? client})
      : _supabase = client ?? SupabaseService.client;

  final SupabaseClient _supabase;

  /// meal_records.meal_type → 項目（間食 snack はリマインダーの対象外）
  static const _mealKinds = {
    'breakfast': ReminderKind.breakfast,
    'lunch': ReminderKind.lunch,
    'dinner': ReminderKind.dinner,
  };

  /// 今日（[nowJst] の日本時間の日）すでに記録した項目（weight / breakfast / lunch / dinner）。
  ///
  /// - weight: weight_records が1行以上（source を問わない。ヘルスケアの取り込みも含む）
  /// - breakfast / lunch / dinner: meal_records.meal_type がその種類の行が1行以上
  ///
  /// recorded_at は `[今日 00:00 JST, 翌日 00:00 JST)` を時差付きの UTC の ISO 文字列にして
  /// 半開区間で比べる（時差のない文字列は UTC として読まれるため）
  Future<Set<ReminderKind>> fetchRecordedToday({
    required String clientId,
    required tz.TZDateTime nowJst,
  }) async {
    final range = jstDayRangeUtc(nowJst);
    final fromIso = range.startUtc.toUtc().toIso8601String();
    final toIso = range.endUtc.toUtc().toIso8601String();

    final results = await Future.wait<PostgrestList>([
      // 有無だけ分かればよいので1行まで
      _supabase
          .from('weight_records')
          .select('id')
          .eq('client_id', clientId)
          .gte('recorded_at', fromIso)
          .lt('recorded_at', toIso)
          .limit(1),
      // 種類の集合が要るので件数は絞らない（対象の3種類・1日分・1列だけ）
      _supabase
          .from('meal_records')
          .select('meal_type')
          .eq('client_id', clientId)
          .gte('recorded_at', fromIso)
          .lt('recorded_at', toIso)
          .inFilter('meal_type', _mealKinds.keys.toList()),
    ]);
    final weightRows = results[0];
    final mealRows = results[1];

    final recorded = <ReminderKind>{};
    if (weightRows.isNotEmpty) recorded.add(ReminderKind.weight);
    for (final row in mealRows) {
      final kind = _mealKinds[row['meal_type']];
      if (kind != null) recorded.add(kind);
    }
    return recorded;
  }

  /// [fromDateKey]〜[toDateKey]（日本時間の 'YYYY-MM-DD'、両端を含む）のうち、
  /// 未完了（status = 'pending'）のセルフガイドの割り当てがある日付。
  ///
  /// セルフガイドの見分け方は WorkoutRepository と同じ（workout_plans を embed して
  /// plan_type = 'self_guided' のものだけを残す。プランを読めない行は除く）
  Future<Set<String>> fetchPendingWorkoutDates({
    required String clientId,
    required String fromDateKey,
    required String toDateKey,
  }) async {
    final rows = await _supabase
        .from('workout_assignments')
        .select('assigned_date, workout_plans(plan_type)')
        .eq('client_id', clientId)
        .eq('status', 'pending')
        .gte('assigned_date', fromDateKey)
        .lte('assigned_date', toDateKey);

    return {
      for (final row in rows)
        if (_isSelfGuided(row) && row['assigned_date'] is String)
          row['assigned_date'] as String,
    };
  }

  static bool _isSelfGuided(Map<String, dynamic> row) {
    final plan = row['workout_plans'];
    return plan is Map && plan['plan_type'] == 'self_guided';
  }
}
