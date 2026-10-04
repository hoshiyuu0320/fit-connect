import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 睡眠画面の表示文字の整形（日付・時刻・時間）。
///
/// 正本（record-screens.js）の書式に合わせる:
/// 日付は「9月13日（日）」（全角の括弧・空白なし）、時刻は「7:32」（時は 0 埋めしない）、
/// 時間は「6時間50分」、グラフの値ラベルは「6:50」。
/// 表示だけの整形で、データ層には触れない。

const List<String> _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

String _two(int n) => n.toString().padLeft(2, '0');

/// `yyyy-MM-dd`（JST の日付キー）→ その日の 0 時の [DateTime]。形式が不正なら null
DateTime? parseSleepDateKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// 曜日の 1 文字（月〜日）
String sleepWeekdayLabel(DateTime date) => _weekdayLabels[date.weekday - 1];

/// 「9月13日（日）」。[now] と年が違うときだけ「2025年9月13日（日）」と年を付ける
String formatSleepDate(DateTime date, {DateTime? now}) {
  final yearPrefix =
      (now != null && date.year != now.year) ? '${date.year}年' : '';
  return '$yearPrefix${date.month}月${date.day}日（${sleepWeekdayLabel(date)}）';
}

/// 「7:32」（時は 0 埋めしない）
String formatSleepClock(DateTime dateTime) =>
    '${dateTime.hour}:${_two(dateTime.minute)}';

/// 「9月13日（日）7:32」
String formatSleepDateTime(DateTime dateTime, {DateTime? now}) =>
    '${formatSleepDate(dateTime, now: now)}${formatSleepClock(dateTime)}';

/// 分 → 「6:50」（グラフの値ラベル）
String formatSleepHm(int minutes) => '${minutes ~/ 60}:${_two(minutes % 60)}';

/// 分 → 「6時間58分」（60 分未満は「45分」）。睡眠の履歴・平均で使う
String formatSleepDuration(int minutes) =>
    FcSleepStageBar.formatMinutes(minutes);

/// 分 → 数値と単位の組（`7 時間 30 分`）。「昨夜の睡眠」の大きな数値で使う
List<FcNumPart> sleepDurationParts(int minutes) {
  if (minutes < 60) return [FcNumPart('$minutes', '分')];
  return [
    FcNumPart('${minutes ~/ 60}', '時間'),
    FcNumPart(_two(minutes % 60), '分'),
  ];
}
