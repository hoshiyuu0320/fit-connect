/// プラン（ワークアウト）画面の表示用フォーマット。
///
/// 日付は正本（`plan-screens.js`）どおり、全角かっこ・曜日つきで表す。
/// 例: 「9月13日（日）」「9/11（金）」。
library;

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// 曜日 1 文字（月〜日）
String workoutWeekdayLabel(DateTime date) =>
    _weekdayLabels[(date.weekday - 1) % 7];

/// 「9月13日（日）」
String formatWorkoutLongDate(DateTime date) =>
    '${date.month}月${date.day}日（${workoutWeekdayLabel(date)}）';

/// 「9/11（金）」
String formatWorkoutShortDate(DateTime date) =>
    '${date.month}/${date.day}（${workoutWeekdayLabel(date)}）';

/// assigned_date（yyyy-MM-dd）を日付だけの [DateTime] にする
DateTime parseWorkoutAssignedDate(String dateStr) {
  final parts = dateStr.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// 重さの表示用（60.0 → 「60」、22.5 → 「22.5」）
String formatWorkoutWeight(double weight) {
  if (weight == weight.truncateToDouble()) return weight.toInt().toString();
  return weight.toString();
}
