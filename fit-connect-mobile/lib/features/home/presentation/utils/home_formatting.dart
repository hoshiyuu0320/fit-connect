/// ホーム画面の表示整形ユーティリティ。
///
/// 目標・最新コメント・今日のまとめで同じ規則（時刻、期限、今週の起点）を使うため、
/// 実装はこのファイル1箇所にだけ置く。体重（kg）と符号つきの差は記録タブと同じ
/// `weight_records/presentation/widgets/weight_format.dart`、トレーナー名は
/// `shared/utils/trainer_name.dart` を使う。
library;

/// 記録・メッセージの時刻を整形する。今日なら `7:30`、それ以外は `9月12日 7:30`。
String formatHomeTime(DateTime at, {required DateTime now}) {
  final local = at.toLocal();
  final clock = '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  final isToday = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return isToday ? clock : '${local.month}月${local.day}日 $clock';
}

/// 期限の表示。`12月31日まで`（年が違うときだけ `2027年1月15日まで`）
String formatDeadline(DateTime deadline, {required DateTime now}) {
  final year = deadline.year != now.year ? '${deadline.year}年' : '';
  return '$year${deadline.month}月${deadline.day}日まで';
}

/// 今週の起点（月曜）の表示。`今週（9/7〜）`
String formatWeekStartLabel(DateTime now) {
  final monday = now.subtract(Duration(days: now.weekday - 1));
  return '今週（${monday.month}/${monday.day}〜）';
}
