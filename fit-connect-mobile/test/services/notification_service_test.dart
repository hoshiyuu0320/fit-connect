import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:fit_connect_mobile/services/notification_service.dart';
import 'package:fit_connect_mobile/services/notification_tap_dispatcher.dart';

/// NotificationService のローカル通知の初期化と、通知タップの受け口のテスト。
///
/// flutter_local_notifications（Android 実装）の method channel を差し替えて、
/// ネイティブとのやり取りだけを偽物にする（Firebase には触れない）。
/// NotificationService は static なので、初期化はこのファイルで1回だけ（setUpAll）。
const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

/// アプリを起動したローカル通知（夕食のリマインダー）
const _launchId = 7024;
const _launchPayload = 'record_reminder:dinner@202611072000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  /// ネイティブから「通知が押された」を送る（onDidReceiveNotificationResponse）
  Future<void> tapFromNative({required int id, required String payload}) {
    return messenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('didReceiveNotificationResponse', {
          'notificationId': id,
          'payload': payload,
          'notificationResponseType': 0,
        }),
      ),
      (_) {},
    );
  }

  setUpAll(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {
            'notificationLaunchedApp': true,
            'notificationResponse': {
              'notificationId': _launchId,
              'payload': _launchPayload,
              'notificationResponseType': 0,
            },
          };
      }
      return null;
    });

    // 同時に呼んでも同じ初期化を待つ
    final first = NotificationService.ensureLocalNotificationsInitialized();
    final second = NotificationService.ensureLocalNotificationsInitialized();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(_channel, null);
  });

  tearDown(() => NotificationService.setNotificationTapHandler(null));

  group('ensureLocalNotificationsInitialized', () {
    test('プラグインの初期化・起動時の通知の確認は1回だけ。何度呼んでも増えない', () async {
      await NotificationService.ensureLocalNotificationsInitialized();

      expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
      expect(
        calls.where((c) => c.method == 'getNotificationAppLaunchDetails'),
        hasLength(1),
      );
    });

    test('Android の小アイコンは ic_stat_fit_connect のまま', () {
      final init = calls.firstWhere((c) => c.method == 'initialize');
      expect((init.arguments as Map)['defaultIcon'], 'ic_stat_fit_connect');
    });

    test('通知チャンネル: 既存の「重要な通知」と、記録のリマインダー（既定の重要度）を作る', () {
      final channels = calls
          .where((c) => c.method == 'createNotificationChannel')
          .map((c) => c.arguments as Map)
          .toList();

      expect(channels.map((c) => c['id']),
          ['high_importance_channel', 'record_reminder']);

      final important = channels[0];
      expect(important['name'], '重要な通知');
      expect(important['description'], 'このチャンネルは重要な通知に使用されます');
      expect(important['importance'], Importance.high.value);

      final reminder = channels[1];
      expect(reminder['name'], '記録のリマインダー');
      expect(reminder['description'], '記録を忘れないためのお知らせ');
      expect(reminder['importance'], Importance.defaultImportance.value);
      expect(NotificationService.recordReminderChannel.id, 'record_reminder');
    });

    test('時間帯を Asia/Tokyo に固定する', () {
      expect(tz.local.name, 'Asia/Tokyo');
    });
  });

  group('通知タップの受け口', () {
    test('起動時の通知は受け口が設定されるまで取っておき、同じ通知のタップが続いても1回だけ渡す', () async {
      // 受け口が無い間に起動時の通知を確かめた（setUpAll）ので、取ってある
      expect(
        NotificationService.tapDispatcherForTesting.pendingTap,
        const NotificationTap('record_reminder', 'dinner@202611072000'),
      );

      final taps = <(String, String?)>[];
      NotificationService.setNotificationTapHandler(
          (type, id) => taps.add((type, id)));
      await Future<void>.delayed(Duration.zero);
      expect(taps, [('record_reminder', 'dinner@202611072000')]);

      // プラグインが同じタップを onDidReceiveNotificationResponse でも知らせた場合
      await tapFromNative(id: _launchId, payload: _launchPayload);
      expect(taps, hasLength(1));

      // 別の通知のタップは、来たときにそのまま渡す
      await tapFromNative(
        id: 7000,
        payload: 'record_reminder:weight@202611080730',
      );
      expect(taps, [
        ('record_reminder', 'dinner@202611072000'),
        ('record_reminder', 'weight@202611080730'),
      ]);
    });

    test('onNotificationTap への代入（app.dart の書き方）でも、取っておいたタップを渡す', () async {
      // 受け口が無い間のタップ
      await tapFromNative(id: 9001, payload: 'health_sync_error');
      expect(NotificationService.onNotificationTap, isNull);

      final taps = <(String, String?)>[];
      void handler(String type, String? id) => taps.add((type, id));
      NotificationService.onNotificationTap = handler;

      expect(NotificationService.onNotificationTap, same(handler));
      await Future<void>.delayed(Duration.zero);
      expect(taps, [('health_sync_error', null)]);
    });

    test('clearPendingTap: 受け口が無い間のタップを捨てる（ログアウトしたとき。次の受け口へ渡さない）', () async {
      await tapFromNative(
        id: 7043,
        payload: 'record_reminder:dinner@202611072000',
      );
      expect(NotificationService.tapDispatcherForTesting.pendingTap, isNotNull);

      NotificationService.clearPendingTap();

      final taps = <(String, String?)>[];
      NotificationService.setNotificationTapHandler(
          (type, id) => taps.add((type, id)));
      await Future<void>.delayed(Duration.zero);
      expect(NotificationService.tapDispatcherForTesting.pendingTap, isNull);
      expect(taps, isEmpty);
    });
  });
}
