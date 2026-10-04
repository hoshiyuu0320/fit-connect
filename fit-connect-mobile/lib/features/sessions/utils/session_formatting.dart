/// セッションの表示整形ユーティリティ。
///
/// NextSessionCard（ホーム）/ SessionsScreen（一覧）/ カルテ詳細 / 「変更を相談」の定型文で
/// 同じ整形規則を使うため、実装はこのファイル1箇所にだけ置く。
///
/// 日時の表記は 2 種類あり、用途で使い分ける（混ぜない）:
/// - 画面の表示: [formatSessionDateTimeDisplay] / [formatSessionDateDisplay]
///   （再デザインの表記「9月15日（火）19:00」。全角括弧・時刻の前にスペースなし）
/// - 定型文・通知: [formatSessionDateTime]（「9月15日(火) 19:00」。半角括弧・スペースあり。
///   「変更を相談」の定型文と push 通知本文 session_reminder_format.ts と同じ表記）
/// 曜日・年の付与規則はどちらも同じ。トレーナーに届く文面（定型文）は、
/// 表示用ではなく [formatSessionDateTime] から組み立てること。
library;

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// 「9月10日(水) 18:00」形式に整形する（intl 未使用の既存の流儀に合わせる）。
///
/// - [now] は呼び出し側が1フレームにつき1回だけ取得したものを渡す
///   （行ごとに引き直すと日跨ぎで表示が食い違う）
/// - 年をまたぐと日付が曖昧になるため、セッションの年が [now] の年と違う場合は
///   「2025年9月10日(水) 18:00」と年を付ける（過去タブが年をまたいでも曖昧にならない）。
///   [includeYear] が true なら同じ年でも常に付ける
String formatSessionDateTime(
  DateTime dateTime, {
  required DateTime now,
  bool includeYear = false,
}) {
  final weekday = _weekdayLabels[dateTime.weekday - 1];
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final yearPrefix =
      (includeYear || dateTime.year != now.year) ? '${dateTime.year}年' : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日($weekday) $hour:$minute';
}

/// 画面に表示する日時を「9月15日（火）19:00」形式に整形する（再デザインの表記）。
///
/// 全角括弧・時刻の前にスペースなし・時は 0 埋めなし（「7:30」）。
/// [formatSessionDateTime] とは別物で、あちらは「変更を相談」の定型文と
/// push 通知本文（session_reminder_format.ts）と揃えてある半角括弧の表記なので、
/// 画面の表示だけこちらを使う（定型文は引き続き [formatSessionDateTime] から作る）。
///
/// 年の付与規則は [formatSessionDateTime] と同じ（[includeYear] か、[now] と年が違うとき）。
String formatSessionDateTimeDisplay(
  DateTime dateTime, {
  required DateTime now,
  bool includeYear = false,
}) {
  final weekday = _weekdayLabels[dateTime.weekday - 1];
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final yearPrefix =
      (includeYear || dateTime.year != now.year) ? '${dateTime.year}年' : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日（$weekday）'
      '${dateTime.hour}:$minute';
}

/// 日付だけ（時刻なし）を「9月8日（火）」形式に整形する（カルテの作成日など）。
/// 年の付与規則は [formatSessionDateTimeDisplay] と同じ
String formatSessionDateDisplay(
  DateTime dateTime, {
  required DateTime now,
  bool includeYear = false,
}) {
  final weekday = _weekdayLabels[dateTime.weekday - 1];
  final yearPrefix =
      (includeYear || dateTime.year != now.year) ? '${dateTime.year}年' : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日（$weekday）';
}

/// セッション種別の表示ラベル。
/// Web側は value と label が同一の日本語だが 'other' だけ英語なので変換する
/// （fit-connect/src/types/session.ts の SESSION_TYPE_OPTIONS）
String? sessionTypeLabel(String? sessionType) {
  if (sessionType == null || sessionType.isEmpty) return null;
  return sessionType == 'other' ? 'その他' : sessionType;
}

/// 「変更を相談」でメッセージ入力欄に入れる定型文。
/// [dateTimeLabel] は [formatSessionDateTime] の戻り値を渡す
/// （push 通知本文と同じ半角括弧の表記。画面の表示は [formatSessionDateTimeDisplay]）
String buildSessionConsultDraft(String dateTimeLabel) {
  return '$dateTimeLabel のセッションについて相談です。';
}
