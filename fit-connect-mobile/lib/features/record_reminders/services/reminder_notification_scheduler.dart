import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:fit_connect_mobile/features/record_reminders/domain/reminder_planner.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';

/// 記録のリマインダーの通知を端末に予約する（設計 §4・§9。FLN の薄い包み。テストでは差し替える）
abstract class ReminderNotificationScheduler {
  /// 端末に予約済みの通知のうち、リマインダーの ID（7000〜7099）のものだけ
  Future<List<PendingReminder>> pendingReminders();

  /// [reminder] を予約する（同じ ID の予約は置き換わる）
  Future<void> schedule(PlannedReminder reminder);

  /// [id] の予約と表示中の通知を取り消す
  Future<void> cancel(int id);

  /// リマインダーの ID の、予約と表示中の通知をすべて取り消す（ほかの ID の通知には触れない）
  Future<void> cancelAllReminders();
}

/// flutter_local_notifications（NotificationService のプラグイン）で予約する。
///
/// どのメソッドも先にローカル通知の初期化（時間帯の Asia/Tokyo 固定を含む）を待つ。
/// iOS/Android 以外では何もしない（予約一覧は空）
class FlnReminderNotificationScheduler
    implements ReminderNotificationScheduler {
  const FlnReminderNotificationScheduler();

  FlutterLocalNotificationsPlugin get _plugin =>
      NotificationService.localNotifications;

  /// ローカル通知の初期化を待ち、予約できる端末（iOS/Android）なら true
  Future<bool> _ready() async {
    await NotificationService.ensureLocalNotificationsInitialized();
    // iOS/Androidのみ
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return true;
  }

  /// 通知の見た目（Android はチャンネル「記録のリマインダー」・既定の重要度、iOS は既定）
  static NotificationDetails _details() {
    const channel = NotificationService.recordReminderChannel;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      // 既定（フォアグラウンドでもバナーを出す）
      iOS: const DarwinNotificationDetails(),
    );
  }

  @override
  Future<List<PendingReminder>> pendingReminders() async {
    if (!await _ready()) return const [];
    final requests = await _plugin.pendingNotificationRequests();
    return [
      for (final request in requests)
        if (isReminderNotificationId(request.id))
          PendingReminder(id: request.id, payload: request.payload),
    ];
  }

  @override
  Future<void> schedule(PlannedReminder reminder) async {
    if (!await _ready()) return;
    await _plugin.zonedSchedule(
      reminder.id,
      reminder.title,
      reminder.body,
      reminder.fireAt,
      _details(),
      // 予約時刻（日本時間）を絶対時刻として扱う（端末の時間帯に従わない）
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // 正確な時刻のアラームの権限は使わない（省電力で数分遅れることがある）
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!await _ready()) return;
    await _plugin.cancel(id);
  }

  @override
  Future<void> cancelAllReminders() async {
    if (!await _ready()) return;

    // プラグインの cancelAll() は使わない（ほかの通知まで消えるため）。リマインダーの ID だけを1件ずつ消す
    final ids = <int>{
      for (final request in await _plugin.pendingNotificationRequests())
        if (isReminderNotificationId(request.id)) request.id,
    };
    // 表示中の通知（取れない OS もあるので、失敗しても予約の分は消す）
    try {
      for (final notification in await _plugin.getActiveNotifications()) {
        final id = notification.id;
        if (id != null && isReminderNotificationId(id)) ids.add(id);
      }
    } catch (e) {
      debugPrint('[ReminderNotificationScheduler] 表示中の通知の取得エラー（無視）: $e');
    }

    for (final id in ids) {
      try {
        await _plugin.cancel(id);
      } catch (e) {
        debugPrint('[ReminderNotificationScheduler] 通知 $id の取り消しエラー: $e');
      }
    }
  }
}
