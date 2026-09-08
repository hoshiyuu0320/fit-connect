/// セッションの表示整形ユーティリティ。
///
/// NextSessionCard（ホーム）/ SessionsScreen（一覧）/ 「変更を相談」の定型文で
/// 同じ整形規則を使うため、実装はこのファイル1箇所にだけ置く。
/// 表示と定型文で文面がズレると顧客とトレーナーの認識違いになるため、
/// 定型文も必ず表示に使ったラベルから組み立てること。
library;

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// 「9月10日(水) 18:00」形式に整形する（intl 未使用の既存の流儀に合わせる）。
///
/// - [now] は呼び出し側が1フレームにつき1回だけ取得したものを渡す
///   （行ごとに引き直すと日跨ぎで表示が食い違う）
/// - 年をまたぐと日付が曖昧になるため、[includeYear] が true か
///   セッションの年が [now] の年と違う場合は「2025年9月10日(水) 18:00」と年を付ける。
///   過去タブは最大50件で年をまたぐので includeYear: true で呼ぶこと
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

/// セッション種別の表示ラベル。
/// Web側は value と label が同一の日本語だが 'other' だけ英語なので変換する
/// （fit-connect/src/types/session.ts の SESSION_TYPE_OPTIONS）
String? sessionTypeLabel(String? sessionType) {
  if (sessionType == null || sessionType.isEmpty) return null;
  return sessionType == 'other' ? 'その他' : sessionType;
}

/// 「変更を相談」でメッセージ入力欄に入れる定型文。
/// [dateTimeLabel] は画面に表示しているラベルをそのまま渡す
/// （formatSessionDateTime の戻り値。表示と定型文を必ず一致させるため）
String buildSessionConsultDraft(String dateTimeLabel) {
  return '$dateTimeLabel のセッションについて相談です。';
}
