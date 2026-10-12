// 記録タブ（食事・運動）で共通の日付・時刻の書き方。
//
// 正本 `record-screens.js` の表記:
//   日付   「9月13日（日）」
//   日時   「9月13日（日）12:30」（時は 0 埋めしない: 8:10）
//
// `DateFormat('...', 'ja')` はロケール初期化が要るため使わず、曜日は自前で持つ。
// 運動タブも使うので、基盤（lib/shared）へ昇格してほしい（最終報告に記載）。

const List<String> _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// 曜日 1 文字（月〜日）
String recordWeekdayLabel(DateTime date) =>
    _weekdayLabels[(date.weekday - 1) % 7];

/// 「9月13日（日）」
String recordDateLabel(DateTime date) =>
    '${date.month}月${date.day}日（${recordWeekdayLabel(date)}）';

/// 「12:30」「8:10」（時は 0 埋めしない）
String recordTimeLabel(DateTime date) =>
    '${date.hour}:${date.minute.toString().padLeft(2, '0')}';

/// 「9月13日（日）12:30」
String recordDateTimeLabel(DateTime date) =>
    '${recordDateLabel(date)}${recordTimeLabel(date)}';

/// 「9/7〜9/13」（週の範囲）
String recordWeekRangeLabel(DateTime weekStart) {
  final end = weekStart.add(const Duration(days: 6));
  return '${weekStart.month}/${weekStart.day}〜${end.month}/${end.day}';
}

/// 日付だけにした値（時刻を落とす）
DateTime recordDayOf(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// その日を含む週の月曜日（時刻なし）
DateTime recordWeekStartOf(DateTime date) {
  final day = recordDayOf(date);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

/// 月末の 23:59:59（月カレンダー・月の一覧の問い合わせ用）
DateTime recordMonthEndOf(DateTime month) =>
    DateTime(month.year, month.month + 1, 0, 23, 59, 59);

/// 週末（日曜）の 23:59:59（週ストリップの問い合わせ用）
DateTime recordWeekEndOf(DateTime weekStart) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + 6, 23, 59, 59);
