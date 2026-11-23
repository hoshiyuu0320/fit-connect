import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';

// 記録の連続をホームでどう見せるかを決める純関数（設計 §4・§6.1）。
// Flutter・Supabase・時計には依存しない（「今日」は status.asOfDate）。

/// ホームの「記録の連続」の行に出す状態
sealed class RecordStreakView {
  const RecordStreakView();
}

/// 今日記録済み。[days] は今日を含む連続日数（1 以上）
final class RecordStreakRecordedToday extends RecordStreakView {
  const RecordStreakRecordedToday({required this.days})
      : assert(days >= 1, 'days は 1 以上');

  final int days;

  @override
  bool operator ==(Object other) =>
      other is RecordStreakRecordedToday && other.days == days;

  @override
  int get hashCode => Object.hash(RecordStreakRecordedToday, days);

  @override
  String toString() => 'RecordStreakRecordedToday($days)';
}

/// 今日まだ記録していないが、昨日まで続いている。[days] は昨日までの連続日数（1 以上）。
/// 今日の分は今日が終わるまで切れない（今日記録すると [days] + 1 日）
final class RecordStreakAlive extends RecordStreakView {
  const RecordStreakAlive({required this.days})
      : assert(days >= 1, 'days は 1 以上');

  final int days;

  @override
  bool operator ==(Object other) =>
      other is RecordStreakAlive && other.days == days;

  @override
  int get hashCode => Object.hash(RecordStreakAlive, days);

  @override
  String toString() => 'RecordStreakAlive($days)';
}

/// 続いていない（今日まだ記録しておらず、昨日も記録していない）。今日記録すると 1 日目
final class RecordStreakNone extends RecordStreakView {
  const RecordStreakNone();

  @override
  bool operator ==(Object other) => other is RecordStreakNone;

  @override
  int get hashCode => (RecordStreakNone).hashCode;

  @override
  String toString() => 'RecordStreakNone()';
}

/// [status] からホームに出す状態を決める（設計 §4）。
///
/// [countedTodayByTags]: 今日（[status] の asOfDate と同じ日）に記録になるタグを送り、その先取りが
/// まだ効くか（送ってから 60 秒以内。設計 §6.3）。送った記録はサーバーが少し遅れて作るので、
/// まだ DB に無くても今日記録済みとして扱う。
///
/// - 今日記録済み（DB か送ったタグ）→ [RecordStreakRecordedToday]（昨日までの日数 + 1）
/// - 今日まだで、昨日まで 1 日以上続いている → [RecordStreakAlive]（昨日までの日数）
/// - それ以外 → [RecordStreakNone]
///
/// 昨日までの日数が負（DB は返さない）のときは 0 として扱う
RecordStreakView recordStreakViewOf(
  RecordStreakStatus status, {
  required bool countedTodayByTags,
}) {
  final untilYesterday =
      status.streakUntilYesterday < 0 ? 0 : status.streakUntilYesterday;
  if (status.recordedToday || countedTodayByTags) {
    return RecordStreakRecordedToday(days: untilYesterday + 1);
  }
  if (untilYesterday >= 1) return RecordStreakAlive(days: untilYesterday);
  return const RecordStreakNone();
}
