import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';

/// カルテ（ノート）画面の表示文字の整形。
///
/// 正本（record-screens.js の `NoteCard` / more-screens.js の `NoteDetailScreen`）の書式:
/// 日付「9月8日（火）」、セッション「9月8日（火）19:00 · パーソナル」（全角の括弧・時は 0 埋めなし）。
/// 表示だけの整形で、データ層には触れない。

const List<String> _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

String _two(int n) => n.toString().padLeft(2, '0');

/// 「9月8日（火）」。[now] と年が違うときだけ「2025年12月20日（土）」と年を付ける
String formatNoteDate(DateTime date, {required DateTime now}) {
  final yearPrefix = date.year != now.year ? '${date.year}年' : '';
  return '$yearPrefix${date.month}月${date.day}日（${_weekdayLabels[date.weekday - 1]}）';
}

/// 紐づくセッションの 1 行「9月8日（火）19:00 · パーソナル」。種別が無ければ日時だけ。
///
/// - 年はセッションの年が [now] と違うときだけ付く
/// - 種別は `sessionTypeLabel` を通す（'other' は「その他」）
String formatLinkedSessionLabel(
  LinkedSession session, {
  required DateTime now,
}) {
  final d = session.sessionDate;
  final yearPrefix = d.year != now.year ? '${d.year}年' : '';
  final dateTime =
      '$yearPrefix${d.month}月${d.day}日（${_weekdayLabels[d.weekday - 1]}）${d.hour}:${_two(d.minute)}';
  final type = sessionTypeLabel(session.sessionType);
  return type == null ? dateTime : '$dateTime · $type';
}
