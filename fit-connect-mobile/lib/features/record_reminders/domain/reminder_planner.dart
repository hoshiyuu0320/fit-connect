import 'package:timezone/timezone.dart' as tz;

import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';

// 記録のリマインダーの予約内容を決める純関数（設計 §4・§4.1・§4.2・§9）。
// Flutter・Supabase・FLN には依存しない。
//
// 時間帯は Asia/Tokyo に固定する。日付・時刻は引数の location に関わらず日本時間に直して扱うので、
// 呼び出し元は先に timezone のデータベースを読み込んでおくこと（initializeTimeZones()。ここでは呼ばない）。

/// 予約する1件の通知
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.kind,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// 通知 ID（[reminderNotificationId]）
  final int id;
  final ReminderKind kind;

  /// 鳴らす時刻（Asia/Tokyo）
  final tz.TZDateTime fireAt;
  final String title;
  final String body;

  /// [reminderPayload]（例 'record_reminder:dinner@202611072000'）
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.kind == kind &&
      other.fireAt == fireAt &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, kind, fireAt, title, body, payload);

  @override
  String toString() => 'PlannedReminder($id, $payload)';
}

/// 端末に予約済みの通知（FLN の予約一覧から作る）
class PendingReminder {
  const PendingReminder({required this.id, this.payload});

  final int id;
  final String? payload;

  @override
  bool operator ==(Object other) =>
      other is PendingReminder && other.id == id && other.payload == payload;

  @override
  int get hashCode => Object.hash(id, payload);

  @override
  String toString() => 'PendingReminder($id, $payload)';
}

/// 予約し直しで行う操作。
///
/// [cancelIds] を取り消してから [toSchedule] を予約すること。時刻を変えた項目は
/// 同じ ID が両方に入るので、予約の後に取り消すと新しい予約まで消える。
class ReminderDiff {
  const ReminderDiff({required this.cancelIds, required this.toSchedule});

  /// 取り消す通知 ID（予約一覧の順）
  final List<int> cancelIds;

  /// 予約する通知（[planReminders] の順）
  final List<PlannedReminder> toSchedule;

  /// 何もしなくてよいか
  bool get isEmpty => cancelIds.isEmpty && toSchedule.isEmpty;

  @override
  String toString() =>
      'ReminderDiff(cancelIds: $cancelIds, toSchedule: $toSchedule)';
}

/// リマインダー専用の通知 ID の先頭。7000〜7099 を使う
/// （ヘルスケア同期エラーは 9001、FCM のフォアグラウンド表示は hashCode）
const int reminderIdBase = 7000;

/// リマインダー専用の通知 ID の末尾
const int _reminderIdLast = reminderIdBase + 99;

/// 一度に予約できる日数の上限。ID の日付の部分は通し日数の下1桁（% 10）なので、
/// 連続する10日までなら日ごとに ID が重ならない（11日目は1日目と同じ ID になる）
const int _maxReminderDays = 10;

/// payload の種別。NotificationService は payload を ':' で分けて
/// type（これ）と id（'dinner@202611072000'）にする
const String reminderPayloadType = 'record_reminder';

/// 時間帯（設計 §4。端末の時間帯には従わない）
const String _reminderTimeZone = 'Asia/Tokyo';

tz.Location get _jst => tz.getLocation(_reminderTimeZone);

/// [time] を日本時間に直す（すでに日本時間ならそのまま同じ時刻）
tz.TZDateTime _inJst(tz.TZDateTime time) => tz.TZDateTime.from(time, _jst);

/// 通知 ID（`7000 + ([dateJst] の日本時間の日付の通し日数 % 10) * 10 + kind.index`）。
///
/// 今日からの日数ではなく日付で決めるので、別の日に予約し直しても同じ日の通知は同じ ID
/// （payload も同じ）のまま残り、毎日増えるのは新しい1日分だけになる。
/// 時刻と [dateJst] の location には依らない（日本時間の暦日だけを見る）
int reminderNotificationId(tz.TZDateTime dateJst, ReminderKind kind) =>
    reminderIdBase + (_jstEpochDay(dateJst) % 10) * 10 + kind.index;

/// [dateJst] の日本時間の暦日の、1970-01-01 からの通し日数
int _jstEpochDay(tz.TZDateTime dateJst) {
  final t = _inJst(dateJst);
  return DateTime.utc(t.year, t.month, t.day)
      .difference(DateTime.utc(1970))
      .inDays;
}

/// リマインダー専用の範囲（7000〜7099）の ID か
bool isReminderNotificationId(int id) =>
    id >= reminderIdBase && id <= _reminderIdLast;

/// 通知の payload（`record_reminder:<kind.key>@<予約時刻の日本時間 yyyyMMddHHmm>`）
String reminderPayload(ReminderKind kind, tz.TZDateTime fireAt) {
  final t = _inJst(fireAt);
  final stamp = '${_pad(t.year, 4)}${_pad(t.month)}${_pad(t.day)}'
      '${_pad(t.hour)}${_pad(t.minute)}';
  return '$reminderPayloadType:${kind.key}@$stamp';
}

/// payload（'record_reminder:dinner@...'）から項目を読む。リマインダー以外・知らない項目は null
ReminderKind? reminderKindFromPayload(String payload) {
  const prefix = '$reminderPayloadType:';
  if (!payload.startsWith(prefix)) return null;
  return reminderKindFromTapId(payload.substring(prefix.length));
}

/// NotificationService が payload を分けた後の id（'dinner@...'）から項目を読む。
/// '@' より前をキーとして読む（'@' が無ければ全体）。知らないキー・null は null
ReminderKind? reminderKindFromTapId(String? id) {
  if (id == null) return null;
  final at = id.indexOf('@');
  return ReminderKind.fromKey(at < 0 ? id : id.substring(0, at));
}

/// 予約すべき通知（「あるべき予約」）を、鳴らす時刻の順（同時刻は ReminderKind の並び）で返す。
///
/// - 今日（日本時間）から [days] 日分（今日を含む）。オンの項目を日ごとに1件ずつ
/// - 鳴らす時刻が [now] より後のものだけ（同時刻は含めない）
/// - 今日（dayOffset 0）だけ、[recordedToday] にある項目を除く
/// - 運動は、その日の日本時間の日付（'YYYY-MM-DD'）が [pendingWorkoutDates] にある日だけ
///
/// ID は日付で決まる（[reminderNotificationId]）。[days] は 0〜10、範囲外は RangeError
List<PlannedReminder> planReminders({
  required RecordReminderSettings settings,
  required tz.TZDateTime now,
  required Set<ReminderKind> recordedToday,
  required Set<String> pendingWorkoutDates,
  int days = 7,
}) {
  // ID の日付の部分は通し日数 % 10 なので、11日以上を予約すると窓の中で同じ ID が2件になる
  RangeError.checkValueInInterval(days, 0, _maxReminderDays, 'days');

  final jst = _jst;
  final nowJst = tz.TZDateTime.from(now, jst);
  final planned = <PlannedReminder>[];

  for (var dayOffset = 0; dayOffset < days; dayOffset++) {
    for (final kind in ReminderKind.values) {
      final setting = settings.settingOf(kind);
      if (!setting.enabled) continue;
      if (dayOffset == 0 && recordedToday.contains(kind)) continue;

      // 日の繰り上がり（月末・年末）は TZDateTime（DateTime.utc）が正規化する。日本に夏時間は無い
      final fireAt = tz.TZDateTime(
        jst,
        nowJst.year,
        nowJst.month,
        nowJst.day + dayOffset,
        setting.time.hour,
        setting.time.minute,
      );
      if (!fireAt.isAfter(nowJst)) continue;
      if (kind == ReminderKind.workout &&
          !pendingWorkoutDates.contains(jstDateKeyOf(fireAt))) {
        continue;
      }

      planned.add(PlannedReminder(
        id: reminderNotificationId(fireAt, kind),
        kind: kind,
        fireAt: fireAt,
        title: kind.notificationTitle,
        body: kind.notificationBody,
        payload: reminderPayload(kind, fireAt),
      ));
    }
  }

  planned.sort((a, b) {
    final byTime = a.fireAt.compareTo(b.fireAt);
    return byTime != 0 ? byTime : a.kind.index.compareTo(b.kind.index);
  });
  return planned;
}

/// 「あるべき予約」[planned] と端末の予約 [pending] の差分。
///
/// - ID と payload がどちらも同じ予約はそのまま残す（取り消さず、予約もしない）
/// - それ以外の 7000〜7099 の予約は取り消す（時刻を変えた項目は取り消してから予約し直す）
/// - 7000〜7099 以外の ID は無視する（ほかの通知には触れない）
///
/// [rescheduleAll] が true のときは [pending] を「予約済み」の根拠にしない（Android の起動時。
/// [pending] に OS のアラームが消えた予約が残っていることがある。RecordReminderSync.rescheduleAllOnSignIn）:
/// [planned] をすべて予約し直し（同じ ID の予約は置き換わるので、先に取り消さない）、
/// [planned] に無い ID の 7000〜7099 の予約だけを取り消す
ReminderDiff diffReminders(
  List<PlannedReminder> planned,
  List<PendingReminder> pending, {
  bool rescheduleAll = false,
}) {
  final plannedPayloads = {
    for (final reminder in planned) reminder.id: reminder.payload,
  };

  // そのまま残す予約（すべて予約し直すときは無い）
  final keptIds = <int>{};
  if (!rescheduleAll) {
    for (final reminder in pending) {
      if (!isReminderNotificationId(reminder.id)) continue;
      final plannedPayload = plannedPayloads[reminder.id];
      if (plannedPayload != null && plannedPayload == reminder.payload) {
        keptIds.add(reminder.id);
      }
    }
  }

  // 取り消さない ID: 残す予約。すべて予約し直すときは、予約し直す ID すべて（予約で置き換わる）
  final notCancelledIds =
      rescheduleAll ? plannedPayloads.keys.toSet() : keptIds;
  final cancelIds = <int>[];
  for (final reminder in pending) {
    final id = reminder.id;
    if (!isReminderNotificationId(id) || notCancelledIds.contains(id)) continue;
    if (!cancelIds.contains(id)) cancelIds.add(id);
  }

  return ReminderDiff(
    cancelIds: cancelIds,
    toSchedule: [
      for (final reminder in planned)
        if (!keptIds.contains(reminder.id)) reminder,
    ],
  );
}

/// サーバー（parse-message-tags の parseTagFromTags）がタグを読むときの形。
/// '#体重' / '#食事' / '#食事:朝食' など（前後の空白を含むものは記録にならない）
final _serverTagPattern = RegExp(r'^#(食事|運動|体重)(?::(.+))?$');

/// 送ったメッセージのタグから「今日記録した項目」を推定する（設計 §4.1）。
///
/// サーバーは `tags[0]` だけを記録にするので、最初のタグだけを見る（0件か1件の集合を返す）。
/// 判定はサーバー（parse-message-tags）と同じ:
/// - `#体重`（詳細があっても）→ weight
/// - `#食事:<詳細>` は詳細を「朝」→「昼」→「夕」か「晩」の順に調べて breakfast / lunch / dinner
/// - `#食事:間食` など上記を含まない詳細・詳細なしの `#食事`（サーバーでは snack）、
///   `#運動`、それ以外の形のタグ（'#meal' などの別名を含む）、タグなし → 空
///
/// アプリの parseMessageTags は別名（#meal / #weight / #exercise）を正準形に直して送るので、
/// 別名がそのまま tags に入ることは無い。
Set<ReminderKind> reminderKindsFromTags(List<String> tags) {
  if (tags.isEmpty) return <ReminderKind>{};
  final match = _serverTagPattern.firstMatch(tags.first);
  if (match == null) return <ReminderKind>{};

  switch (match.group(1)) {
    case '体重':
      return {ReminderKind.weight};
    case '食事':
      final detail = match.group(2);
      if (detail == null) return <ReminderKind>{};
      if (detail.contains('朝')) return {ReminderKind.breakfast};
      if (detail.contains('昼')) return {ReminderKind.lunch};
      if (detail.contains('夕') || detail.contains('晩')) {
        return {ReminderKind.dinner};
      }
      return <ReminderKind>{};
    default:
      return <ReminderKind>{};
  }
}

/// [nowJst] の日本時間の日（`[今日 00:00 JST, 翌日 00:00 JST)`）を UTC で返す。
///
/// DB の recorded_at とは `.gte(startUtc) / .lt(endUtc)` の半開区間で、
/// `toUtc().toIso8601String()`（時差付き）にして比べる。返す値は普通の UTC の DateTime。
({DateTime startUtc, DateTime endUtc}) jstDayRangeUtc(tz.TZDateTime nowJst) {
  final jst = _jst;
  final now = tz.TZDateTime.from(nowJst, jst);
  final start = tz.TZDateTime(jst, now.year, now.month, now.day);
  final end = tz.TZDateTime(jst, now.year, now.month, now.day + 1);
  // native は同じ瞬間の UTC の DateTime（TZDateTime のままだと DateTime との == が非対称になる）
  return (startUtc: start.native, endUtc: end.native);
}

/// [dateJst] の日本時間の日付 'YYYY-MM-DD'（workout_assignments.assigned_date と比べる形）
String jstDateKeyOf(tz.TZDateTime dateJst) {
  final t = _inJst(dateJst);
  return '${_pad(t.year, 4)}-${_pad(t.month)}-${_pad(t.day)}';
}

String _pad(int value, [int width = 2]) => value.toString().padLeft(width, '0');
