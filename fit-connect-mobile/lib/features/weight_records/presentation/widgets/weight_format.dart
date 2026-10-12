/// 体重まわりの表示整形（記録タブの「サマリ」「体重」で共通）。
///
/// 日本語ロケールのデータ（`initializeDateFormatting`）に依存しないよう、
/// 曜日は自前の表で出す。
library;

import 'dart:math' as math;

const List<String> _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

/// `9月13日（日）`
String formatJpDate(DateTime d) =>
    '${d.month}月${d.day}日（${_weekdays[d.weekday - 1]}）';

/// `9月13日（日）7:30`
String formatJpDateTime(DateTime d) {
  final minute = d.minute.toString().padLeft(2, '0');
  return '${formatJpDate(d)}${d.hour}:$minute';
}

/// `9/13`（グラフの x ラベル）
String formatMonthDay(DateTime d) => '${d.month}/${d.day}';

/// 期間の範囲。同じ月なら `9月1日〜13日`、月をまたぐなら `6月13日〜9月13日`、
/// 同じ日なら `9月13日`。
String formatJpRange(DateTime start, DateTime end) {
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return '${start.month}月${start.day}日';
  }
  if (start.year == end.year && start.month == end.month) {
    return '${start.month}月${start.day}日〜${end.day}日';
  }
  return '${start.month}月${start.day}日〜${end.month}月${end.day}日';
}

/// 体重（kg）を小数 1 桁で。`62.4`
String formatKg(double value) => value.toStringAsFixed(1);

/// 符号つきの差（kg）。小数 1 桁で丸めて 0 なら符号なしの `0.0`。`+1.4` / `-0.8`
///
/// 増減の良し悪しは符号では決めない（色分けしない）。
String formatSignedKg(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == 0) return '0.0';
  final text = rounded.abs().toStringAsFixed(1);
  return rounded > 0 ? '+$text' : '-$text';
}

/// 折れ線グラフの x ラベルを出す点の位置。最初と最後を含め、最大 4 つを等間隔に選ぶ
/// （正本: 7 点のうち 9/1・9/5・9/9・9/13）。
Set<int> chartLabelIndices(int count) {
  if (count <= 0) return const {};
  if (count == 1) return const {0};
  final labels = math.min(count, 4);
  return {
    for (var k = 0; k < labels; k++) ((k * (count - 1)) / (labels - 1)).round(),
  };
}
