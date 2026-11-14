import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/home/providers/notification_navigation_provider.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/record_reminder_sync.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';
import 'package:fit_connect_mobile/services/notification_tap_dispatcher.dart';

import '../record_reminders/fake_record_reminder_sync.dart';

/// ログアウトしたときの片付け（記録のリマインダー・取っておいた通知のタップ・通知を押したときの「開く先」）のテスト。
///
/// - AuthNotifier.signOut（アカウント削除からも呼ばれる）と app.dart の残ったセッションのサインアウトは、
///   auth のサインアウトの後に片付ける（signOutAndClearState。サインアウトに失敗しても片付ける）
/// - signOut() を通らない signedOut（gotrue の自動のログアウト）でも、AuthNotifier が片付ける
///
/// Supabase は未ログインの状態で初期化する（セッションが無いので signOut は通信しない）。
/// ログインしている状態は setInitialSession で作る。そのときの /logout は、TestWidgetsFlutterBinding が
/// HTTP をすべて 400 にするので失敗する（オフラインでサーバーに届かないときと同じく、端末のセッションは消えて
/// signOut は例外を投げる）。
const _userId = '11111111-1111-1111-1111-111111111111';

/// 通信せずにログインしている状態にする（access_token が JWT でないので期限切れにならない）
Future<void> _signInWithoutNetwork() =>
    Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': 'test-access-token',
      'token_type': 'bearer',
      'refresh_token': 'test-refresh-token',
      'user': {
        'id': _userId,
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));

NotificationTapDispatcher get _taps =>
    NotificationService.tapDispatcherForTesting;

/// 受け口が無い間に押された通知（取っておかれる）
void _tapWhileNoHandler() => _taps
    .dispatch(const NotificationTap('record_reminder', 'weight@202611080730'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  late FakeRecordReminderSync sync;
  late ProviderContainer container;
  late List<String> log;
  late StreamSubscription<AuthState> authEvents;

  setUp(() async {
    sync = FakeRecordReminderSync();
    container = ProviderContainer(overrides: [
      recordReminderSyncProvider.overrideWithValue(sync),
    ]);
    addTearDown(container.dispose);
    // autoDispose なので購読して保つ
    container.listen(authNotifierProvider, (_, __) {});
    await container.read(authNotifierProvider.future);

    // サインアウト（signedOut）と、リマインダーの取り消しの順を記録する
    log = sync.log;
    authEvents = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) log.add('signedOut');
    });
    addTearDown(authEvents.cancel);
    // 購読すると直前のイベント（前のテストのサインアウトなど）が届く（AuthNotifier はそれでも片付ける）
    // ので、捨ててから始める
    await pumpEventQueue();
    log.clear();
    sync.cancelAllCalls = 0;
  });

  tearDown(() async {
    NotificationService.setNotificationTapHandler(null);
    NotificationService.clearPendingTap();
    // ログインしたままのテストがあれば、次のテストのためにセッションを消す（/logout の失敗は無視）
    if (Supabase.instance.client.auth.currentSession != null) {
      try {
        await Supabase.instance.client.auth.signOut();
      } on AuthException catch (_) {}
    }
  });

  group('AuthNotifier.signOut（ログアウト・アカウント削除）', () {
    test('サインアウトしてから記録のリマインダーを消し、取っておいたタップと「開く先」を捨てる（終わるまで待つ）', () async {
      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenMessagesWithDraft('#体重 '));
      _tapWhileNoHandler();

      await container.read(authNotifierProvider.notifier).signOut();

      expect(sync.cancelAllCalls, greaterThanOrEqualTo(1));
      expect(container.read(notificationNavigationProvider), isNull);
      expect(_taps.pendingTap, isNull);
      await pumpEventQueue();
      expect(log, contains('signedOut'));
    });

    test(
        'ログインしている状態から: セッションが消えた後（currentUser が null）に記録のリマインダーを消す。'
        '/logout に届かず signOut が失敗しても、消してから例外を投げる', () async {
      await _signInWithoutNetwork();
      expect(Supabase.instance.client.auth.currentUser?.id, _userId);
      // cancelAll が呼ばれた時点のログインしているユーザー（前の順では、まだ _userId だった）
      final usersAtCancel = <String?>[];
      sync.onCancelAll = () =>
          usersAtCancel.add(Supabase.instance.client.auth.currentUser?.id);
      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenPlanTab());
      _tapWhileNoHandler();

      await expectLater(
        container.read(authNotifierProvider.notifier).signOut(),
        throwsA(isA<AuthException>()),
      );

      expect(Supabase.instance.client.auth.currentUser, isNull);
      expect(usersAtCancel, isNotEmpty);
      expect(usersAtCancel, everyElement(isNull));
      expect(container.read(notificationNavigationProvider), isNull);
      expect(_taps.pendingTap, isNull);
    });

    test('リマインダーを消すのに失敗しても、例外を投げない（サインアウトは済んでいる）', () async {
      sync.cancelAllError = Exception('platform');

      await expectLater(
        container.read(authNotifierProvider.notifier).signOut(),
        completes,
      );
      await pumpEventQueue();

      expect(sync.cancelAllCalls, greaterThanOrEqualTo(1));
      expect(log, contains('signedOut'));
    });
  });

  group('signOut() を通らない signedOut（gotrue の自動のログアウト）', () {
    test('記録のリマインダーを消し、取っておいたタップと「開く先」を捨てる（次のログインへ渡さない）', () async {
      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenMessagesWithDraft('#食事:夕食 '));
      _tapWhileNoHandler();
      expect(_taps.pendingTap, isNotNull);

      // リフレッシュトークンが使えないときなどに gotrue が出すのと同じ signedOut
      // （AuthNotifier.signOut は通らない）
      await Supabase.instance.client.auth.signOut();
      await pumpEventQueue();

      expect(sync.cancelAllCalls, 1);
      expect(_taps.pendingTap, isNull);
      expect(container.read(notificationNavigationProvider), isNull);

      // 次のログインで受け口が設定されても、ログアウト前に押された通知は渡さない
      final delivered = <(String, String?)>[];
      NotificationService.setNotificationTapHandler(
          (type, id) => delivered.add((type, id)));
      await pumpEventQueue();
      expect(delivered, isEmpty);
    });

    test('片付けに失敗しても、認証の流れへ例外を投げない（残りは片付ける）', () async {
      sync.cancelAllError = Exception('platform');
      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenPlanTab());
      _tapWhileNoHandler();

      await Supabase.instance.client.auth.signOut();
      await pumpEventQueue();

      expect(sync.cancelAllCalls, 1);
      expect(_taps.pendingTap, isNull);
      expect(container.read(notificationNavigationProvider), isNull);
    });

    test('signedOut 以外（起動時のセッション・ログインなど）では片付けない（起動時に取っておいたタップは残る）', () async {
      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenPlanTab());
      _tapWhileNoHandler();

      // 起動時のセッションの復元（initialSession）
      await _signInWithoutNetwork();
      await pumpEventQueue();

      expect(sync.cancelAllCalls, 0);
      expect(_taps.pendingTap, isNotNull);
      expect(
          container.read(notificationNavigationProvider), const OpenPlanTab());
    });
  });

  group('signOutAndClearState（サインアウトと片付けの順番）', () {
    test('auth のサインアウトの後に記録のリマインダーを消し、その後で取っておいたタップと「開く先」を捨てる', () async {
      final order = <String>[];
      sync.onCancelAll = () {
        order.add('cancelAll');
        // 取り消している間に押された通知（受け口が無い）も捨てる
        _tapWhileNoHandler();
      };

      await signOutAndClearState(
        signOut: () async => order.add('signOut'),
        reminderSync: sync,
        invalidateNotificationNavigation: () => order.add('navigation'),
      );

      expect(order, ['signOut', 'cancelAll', 'navigation']);
      expect(_taps.pendingTap, isNull);
    });

    test('auth のサインアウトが例外を投げても、記録のリマインダーを消して片付けてから、その例外を投げる', () async {
      final order = <String>[];
      sync.onCancelAll = () => order.add('cancelAll');
      _tapWhileNoHandler();

      await expectLater(
        signOutAndClearState(
          signOut: () async {
            order.add('signOut');
            throw Exception('offline');
          },
          reminderSync: sync,
          invalidateNotificationNavigation: () => order.add('navigation'),
        ),
        throwsException,
      );

      expect(order, ['signOut', 'cancelAll', 'navigation']);
      expect(_taps.pendingTap, isNull);
    });

    test('記録のリマインダーを消すのに失敗しても、例外を投げずに残りを片付ける', () async {
      sync.cancelAllError = Exception('platform');
      var navigationInvalidated = false;
      _tapWhileNoHandler();

      await expectLater(
        signOutAndClearState(
          signOut: () async {},
          reminderSync: sync,
          invalidateNotificationNavigation: () => navigationInvalidated = true,
        ),
        completes,
      );

      expect(sync.cancelAllCalls, 1);
      expect(navigationInvalidated, isTrue);
      expect(_taps.pendingTap, isNull);
    });
  });
}
