/// 記録のリマインダーの項目（設計 §3・§5）。
///
/// 並びは固定。`index` は通知 ID（`7000 + 日 * 10 + index`）にも使うので、
/// 並べ替えたり途中に足したりすると端末に予約済みの通知と食い違う（足すなら末尾、index は 9 まで）。
enum ReminderKind {
  weight(
    key: 'weight',
    label: '体重',
    defaultHour: 7,
    defaultMinute: 30,
    messageDraft: '#体重 ',
    notificationTitle: '体重の記録',
    notificationBody: '今日の体重を記録しましょう',
  ),
  breakfast(
    key: 'breakfast',
    label: '朝食',
    defaultHour: 9,
    defaultMinute: 0,
    messageDraft: '#食事:朝食 ',
    notificationTitle: '朝食の記録',
    notificationBody: '朝食を記録しましょう',
  ),
  lunch(
    key: 'lunch',
    label: '昼食',
    defaultHour: 13,
    defaultMinute: 0,
    messageDraft: '#食事:昼食 ',
    notificationTitle: '昼食の記録',
    notificationBody: '昼食を記録しましょう',
  ),
  dinner(
    key: 'dinner',
    label: '夕食',
    defaultHour: 20,
    defaultMinute: 0,
    messageDraft: '#食事:夕食 ',
    notificationTitle: '夕食の記録',
    notificationBody: '夕食を記録しましょう',
  ),
  workout(
    key: 'workout',
    label: '運動',
    caption: 'プランがある日だけ',
    defaultHour: 18,
    defaultMinute: 0,
    notificationTitle: '今日のワークアウト',
    notificationBody: '今日のプランのワークアウトがあります',
  );

  const ReminderKind({
    required this.key,
    required this.label,
    this.caption,
    required this.defaultHour,
    required this.defaultMinute,
    this.messageDraft,
    required this.notificationTitle,
    required this.notificationBody,
  });

  /// 保存（SharedPreferences の JSON）と通知の payload に使うキー。
  /// 変えると保存済みの設定と予約済みの通知が読めなくなる
  final String key;

  /// 画面の表示名
  final String label;

  /// 表示名の下に添える補足（運動だけ）
  final String? caption;

  /// 既定の時刻（日本時間）
  final int defaultHour;
  final int defaultMinute;

  /// 通知を押したときにメッセージの入力欄へ入れるタグ（末尾の空白込み）。
  /// 運動はプラン画面を開くので null
  final String? messageDraft;

  /// 通知のタイトル
  final String notificationTitle;

  /// 通知の本文（絵文字・「まだ記録されていません」は使わない）
  final String notificationBody;

  /// [key] に対応する項目。知らないキーは null
  static ReminderKind? fromKey(String key) {
    for (final kind in values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}
