import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:fit_connect_mobile/features/record_reminders/domain/reminder_planner.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/reminder_notification_scheduler.dart';

/// FlnReminderNotificationScheduler のテスト。
///
/// flutter_local_notifications の method channel を差し替えて、ネイティブとのやり取りだけを
/// 偽物にする（test/services/notification_service_test.dart と同じ形）。
/// ローカル通知の初期化（NotificationService）は static なので、このファイルで1回だけ走る。
const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  /// 端末の予約（pendingNotificationRequests の応答）
  var pendingOnDevice = <Map<String, Object?>>[];

  /// 表示中の通知（getActiveNotifications の応答）
  var activeOnDevice = <Map<String, Object?>>[];

  /// 渡すと getActiveNotifications が失敗する（取れない OS）
  PlatformException? activeError;

  const scheduler = FlnReminderNotificationScheduler();

  Iterable<MethodCall> callsOf(String method) =>
      calls.where((c) => c.method == method);

  /// 明日の夕食（20:00 JST）のリマインダー（FLN は過去の時刻を受け付けないので、今の時計から作る）
  PlannedReminder tomorrowDinner() {
    final tokyo = tz.getLocation('Asia/Tokyo');
    final today = tz.TZDateTime.now(tokyo);
    final fireAt =
        tz.TZDateTime(tokyo, today.year, today.month, today.day + 1, 20);
    const kind = ReminderKind.dinner;
    return PlannedReminder(
      id: reminderNotificationId(fireAt, kind),
      kind: kind,
      fireAt: fireAt,
      title: kind.notificationTitle,
      body: kind.notificationBody,
      payload: reminderPayload(kind, fireAt),
    );
  }

  setUpAll(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'pendingNotificationRequests':
          return pendingOnDevice;
        case 'getActiveNotifications':
          final error = activeError;
          if (error != null) throw error;
          return activeOnDevice;
      }
      return null;
    });
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(_channel, null);
  });

  setUp(() {
    calls.clear();
    pendingOnDevice = [];
    activeOnDevice = [];
    activeError = null;
  });

  // 初期化は最初の呼び出しで1回だけ走るので、このテストを最初に置く
  test('先にローカル通知の初期化（時間帯の Asia/Tokyo 固定を含む）を待つ', () async {
    await scheduler.pendingReminders();

    final methods = calls.map((c) => c.method).toList();
    expect(methods, contains('initialize'));
    expect(methods.indexOf('initialize'),
        lessThan(methods.indexOf('pendingNotificationRequests')));
    expect(tz.local.name, 'Asia/Tokyo');

    // 2回目からは初期化しない
    calls.clear();
    await scheduler.pendingReminders();
    expect(calls.map((c) => c.method), ['pendingNotificationRequests']);
  });

  test('pendingReminders はリマインダーの ID（7000〜7099）の予約だけを返す', () async {
    pendingOnDevice = [
      {
        'id': 7043,
        'title': '夕食の記録',
        'body': '夕食を記録しましょう',
        'payload': 'record_reminder:dinner@202611072000',
      },
      {'id': 9001, 'title': 't', 'body': 'b', 'payload': 'health_sync_error'},
      {'id': 6999, 'title': 't', 'body': 'b', 'payload': null},
      {'id': 7100, 'title': 't', 'body': 'b', 'payload': null},
      {
        'id': 7000,
        'title': '体重の記録',
        'body': '今日の体重を記録しましょう',
        'payload': 'record_reminder:weight@202611130730',
      },
    ];

    expect(await scheduler.pendingReminders(), const [
      PendingReminder(id: 7043, payload: 'record_reminder:dinner@202611072000'),
      PendingReminder(id: 7000, payload: 'record_reminder:weight@202611130730'),
    ]);
  });

  test('schedule は記録のリマインダーのチャンネル・inexactAllowWhileIdle で、日本時間の時刻に1回だけ予約する',
      () async {
    final reminder = tomorrowDinner();

    await scheduler.schedule(reminder);

    final args = callsOf('zonedSchedule').single.arguments as Map;
    expect(args['id'], reminder.id);
    expect(args['title'], '夕食の記録');
    expect(args['body'], '夕食を記録しましょう');
    expect(args['payload'], reminder.payload);
    expect(args['payload'], startsWith('record_reminder:dinner@'));
    // 時刻は Asia/Tokyo の 20:00（端末の時間帯ではない）
    expect(args['timeZoneName'], 'Asia/Tokyo');
    expect(
        args['scheduledDateTime'], '${jstDateKeyOf(reminder.fireAt)}T20:00:00');
    // 毎日繰り返す通知ではない
    expect(args.containsKey('matchDateTimeComponents'), isFalse);

    final android = args['platformSpecifics'] as Map;
    expect(android['channelId'], 'record_reminder');
    expect(android['channelName'], '記録のリマインダー');
    expect(android['channelDescription'], '記録を忘れないためのお知らせ');
    expect(android['importance'], Importance.defaultImportance.value);
    expect(android['priority'], Priority.defaultPriority.value);
    // 正確な時刻のアラームの権限は使わない
    expect(android['scheduleMode'],
        AndroidScheduleMode.inexactAllowWhileIdle.name);
  });

  test('cancel は指定した ID だけを取り消す', () async {
    await scheduler.cancel(7043);

    expect(calls.map((c) => c.method), ['cancel']);
    expect((calls.single.arguments as Map)['id'], 7043);
  });

  test(
      'cancelAllReminders は予約と表示中のリマインダーの ID だけを1件ずつ取り消す（プラグインの cancelAll は使わない）',
      () async {
    pendingOnDevice = [
      {
        'id': 7043,
        'title': 't',
        'body': 'b',
        'payload': 'record_reminder:dinner@202611072000'
      },
      {'id': 9001, 'title': 't', 'body': 'b', 'payload': 'health_sync_error'},
      {
        'id': 7012,
        'title': 't',
        'body': 'b',
        'payload': 'record_reminder:lunch@202611141300'
      },
    ];
    activeOnDevice = [
      // 表示中のリマインダー（予約一覧からは消えている）
      {'id': 7099, 'channelId': 'record_reminder'},
      // FCM のフォアグラウンド表示（hashCode）・ヘルスケア同期エラー
      {'id': 123456789, 'channelId': 'high_importance_channel'},
      {'id': 9001, 'channelId': 'high_importance_channel'},
      // 予約一覧と重なる分・ID の無い通知
      {'id': 7043, 'channelId': 'record_reminder'},
      {'id': null},
    ];

    await scheduler.cancelAllReminders();

    expect(
      callsOf('cancel').map((c) => (c.arguments as Map)['id']),
      [7043, 7012, 7099],
    );
    expect(callsOf('cancelAll'), isEmpty);
  });

  test('表示中の通知を取れない端末でも、予約の分は取り消す（例外を投げない）', () async {
    pendingOnDevice = [
      {
        'id': 7043,
        'title': 't',
        'body': 'b',
        'payload': 'record_reminder:dinner@202611072000'
      },
    ];
    activeError = PlatformException(code: 'unsupported_os_version');

    await expectLater(scheduler.cancelAllReminders(), completes);

    expect(callsOf('cancel').map((c) => (c.arguments as Map)['id']), [7043]);
  });

  test('iOS/Android 以外では何もしない（予約一覧は空）', () async {
    pendingOnDevice = [
      {
        'id': 7043,
        'title': 't',
        'body': 'b',
        'payload': 'record_reminder:dinner@202611072000'
      },
    ];
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      expect(await scheduler.pendingReminders(), isEmpty);
      await scheduler.schedule(tomorrowDinner());
      await scheduler.cancel(7043);
      await scheduler.cancelAllReminders();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    expect(calls, isEmpty);
  });

  // iOS の実装に差し替えるので最後に置く（終わったら Android に戻す）
  test('iOS では既定の通知（DarwinNotificationDetails）・絶対時刻（absoluteTime）で予約する',
      () async {
    final reminder = tomorrowDinner();
    IOSFlutterLocalNotificationsPlugin.registerWith();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await scheduler.schedule(reminder);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    }

    final args = callsOf('zonedSchedule').single.arguments as Map;
    expect(args['id'], reminder.id);
    expect(args['payload'], reminder.payload);
    expect(args['timeZoneName'], 'Asia/Tokyo');
    expect(
      args['uiLocalNotificationDateInterpretation'],
      UILocalNotificationDateInterpretation.absoluteTime.index,
    );
    final darwin = args['platformSpecifics'] as Map;
    // Android のチャンネルではなく、iOS の既定（項目はすべて未指定 = プラグインの既定でバナーを出す）
    expect(darwin.containsKey('channelId'), isFalse);
    expect(darwin.values.whereType<Object>(), isEmpty);
  });
}
