import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/home/providers/notification_navigation_provider.dart';

/// 通知を押したときの「開く先」の要求（notificationNavigationProvider）のテスト。
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  NotificationNavigation notifier() =>
      container.read(notificationNavigationProvider.notifier);

  test('はじめは要求なし', () {
    expect(container.read(notificationNavigationProvider), isNull);
    expect(notifier().consume(), isNull);
  });

  test('request で置き、consume で取り出すと消える', () {
    notifier().request(const OpenMessagesWithDraft('#体重 '));
    expect(container.read(notificationNavigationProvider),
        const OpenMessagesWithDraft('#体重 '));

    expect(notifier().consume(), const OpenMessagesWithDraft('#体重 '));
    expect(container.read(notificationNavigationProvider), isNull);
    expect(notifier().consume(), isNull);
  });

  test('実行前に次の要求が来たら、新しい要求に置き換える', () {
    notifier().request(const OpenMessagesWithDraft('#食事:朝食 '));
    notifier().request(const OpenPlanTab());

    expect(notifier().consume(), const OpenPlanTab());
    expect(notifier().consume(), isNull);
  });

  test('監視する画面が無くても要求は消えない（keepAlive）', () async {
    notifier().request(const OpenPlanTab());
    // autoDispose なら、監視が無いまま次のイベントで破棄される
    await Future<void>.delayed(Duration.zero);
    await container.pump();

    expect(container.read(notificationNavigationProvider), const OpenPlanTab());
  });

  test('監視している側には、置いたときと消したときに知らせる', () {
    final changes = <NotificationNavigationRequest?>[];
    container.listen<NotificationNavigationRequest?>(
      notificationNavigationProvider,
      (previous, next) => changes.add(next),
    );

    notifier().request(const OpenMessagesWithDraft('#食事:夕食 '));
    notifier().consume();
    // 何も無いときの consume は知らせない
    notifier().consume();

    expect(changes, [const OpenMessagesWithDraft('#食事:夕食 '), null]);
  });

  test('要求の比較は中身で行う', () {
    expect(const OpenMessagesWithDraft('#体重 '),
        OpenMessagesWithDraft(['#体重', ' '].join()));
    expect(const OpenMessagesWithDraft('#体重 '),
        isNot(const OpenMessagesWithDraft('#食事:昼食 ')));
    expect(const OpenPlanTab(), isNot(const OpenMessagesWithDraft('')));
  });

  /// 通知タップ（NotificationService が payload を ':' で分けた type と id）→ 開く先
  group('notificationNavigationRequestFor', () {
    test('体重・食事のリマインダーは、メッセージタブを入力欄にタグ入りで開く', () {
      expect(
        notificationNavigationRequestFor(
            'record_reminder', 'weight@202611070730'),
        const OpenMessagesWithDraft('#体重 '),
      );
      expect(
        notificationNavigationRequestFor(
            'record_reminder', 'breakfast@202611070900'),
        const OpenMessagesWithDraft('#食事:朝食 '),
      );
      expect(
        notificationNavigationRequestFor(
            'record_reminder', 'lunch@202611071300'),
        const OpenMessagesWithDraft('#食事:昼食 '),
      );
      expect(
        notificationNavigationRequestFor(
            'record_reminder', 'dinner@202611072000'),
        const OpenMessagesWithDraft('#食事:夕食 '),
      );
    });

    test('運動のリマインダーは、プランタブを開く', () {
      expect(
        notificationNavigationRequestFor(
            'record_reminder', 'workout@202611071800'),
        const OpenPlanTab(),
      );
    });

    test('時刻の部分が無くても項目で決める', () {
      expect(notificationNavigationRequestFor('record_reminder', 'dinner'),
          const OpenMessagesWithDraft('#食事:夕食 '));
    });

    test('知らない項目・id なしは何もしない', () {
      expect(
        notificationNavigationRequestFor(
            'record_reminder', 'sleep@202611070700'),
        isNull,
      );
      expect(notificationNavigationRequestFor('record_reminder', null), isNull);
      expect(notificationNavigationRequestFor('record_reminder', ''), isNull);
    });

    test('ほかの通知（メッセージ・セッション・ヘルスケア同期エラー）はこれまでどおり何もしない', () {
      expect(notificationNavigationRequestFor('message', 'abc-123'), isNull);
      expect(
          notificationNavigationRequestFor('session_reminder', 'abc'), isNull);
      expect(
          notificationNavigationRequestFor('health_sync_error', null), isNull);
      expect(notificationNavigationRequestFor('unknown', 'dinner@202611072000'),
          isNull);
    });
  });
}
