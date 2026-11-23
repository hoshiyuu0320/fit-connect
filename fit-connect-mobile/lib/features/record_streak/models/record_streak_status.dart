import 'package:flutter/foundation.dart' show immutable;

/// 記録の連続の状態（get_record_streak の 1 行。設計 §4・§5.1）。
///
/// 日付は日本時間（Asia/Tokyo）で数える。画面に出す日数は recordStreakViewOf で決める
@immutable
class RecordStreakStatus {
  const RecordStreakStatus({
    required this.asOfDate,
    required this.recordedToday,
    required this.streakUntilYesterday,
  });

  /// get_record_streak の行（`as_of_date` / `recorded_today` / `streak_until_yesterday`）を読む。
  ///
  /// `as_of_date` は PostgREST が date を返す形（'YYYY-MM-DD'）のまま持つ。
  /// `streak_until_yesterday` は整数でなく数値（5.0 など）で来ても整数にする。
  /// 列が無い・型が違う行は例外（呼び出し元の provider がエラーになり、ホームは行を出さない）
  factory RecordStreakStatus.fromRow(Map<String, dynamic> row) {
    return RecordStreakStatus(
      asOfDate: row['as_of_date'] as String,
      recordedToday: row['recorded_today'] as bool,
      streakUntilYesterday: (row['streak_until_yesterday'] as num).toInt(),
    );
  }

  /// 基準の日（DB の今の日本時間の日付 'YYYY-MM-DD'）。「今日」はこの日
  final String asOfDate;

  /// 今日（[asOfDate]）に、数える記録があるか
  final bool recordedToday;

  /// 昨日から過去へ、記録した日が途切れずに続く日数（昨日に記録が無ければ 0）
  final int streakUntilYesterday;

  @override
  bool operator ==(Object other) =>
      other is RecordStreakStatus &&
      other.asOfDate == asOfDate &&
      other.recordedToday == recordedToday &&
      other.streakUntilYesterday == streakUntilYesterday;

  @override
  int get hashCode =>
      Object.hash(asOfDate, recordedToday, streakUntilYesterday);

  @override
  String toString() => 'RecordStreakStatus(asOfDate: $asOfDate, '
      'recordedToday: $recordedToday, '
      'streakUntilYesterday: $streakUntilYesterday)';
}
