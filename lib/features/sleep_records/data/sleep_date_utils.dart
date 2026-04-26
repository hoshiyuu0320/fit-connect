/// JST (UTC+9) の日付キーを 'YYYY-MM-DD' 文字列で返す。
/// docs/tasks/lessons.md 参照: DateTime比較は文字列化で行う（タイムゾーン問題回避）。
String jstDateKey(DateTime dateTime) {
  final jst = dateTime.toUtc().add(const Duration(hours: 9));
  return '${jst.year.toString().padLeft(4, '0')}-'
      '${jst.month.toString().padLeft(2, '0')}-'
      '${jst.day.toString().padLeft(2, '0')}';
}

/// 今日の JST 日付キー
String todayJstDateKey() => jstDateKey(DateTime.now());

/// 今日から [daysBack] 日前の JST 日付キー
String jstDateKeyDaysAgo(int daysBack) =>
    jstDateKey(DateTime.now().subtract(Duration(days: daysBack)));
