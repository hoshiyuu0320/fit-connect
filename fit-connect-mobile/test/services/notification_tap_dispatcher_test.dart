import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/services/notification_tap_dispatcher.dart';

/// 通知タップの受け渡し（受け口が無い間の取り置き・起動時の通知の重複）のテスト。
/// プラグインには触れない（NotificationService の中身だけを確かめる）。
void main() {
  /// 取っておいたタップをすぐ渡す（microtask を待たない）dispatcher
  NotificationTapDispatcher syncDispatcher({List<Object>? errors}) =>
      NotificationTapDispatcher(
        scheduleFlush: (callback) => callback(),
        onError: errors?.add,
      );

  group('NotificationTap.fromPayload', () {
    test('type:id の payload を type と id に分ける', () {
      expect(
        NotificationTap.fromPayload('record_reminder:dinner@202611072000'),
        const NotificationTap('record_reminder', 'dinner@202611072000'),
      );
      expect(
        NotificationTap.fromPayload('message:abc-123'),
        const NotificationTap('message', 'abc-123'),
      );
    });

    test(': の無い payload は type だけ（id は null）', () {
      expect(
        NotificationTap.fromPayload('health_sync_error'),
        const NotificationTap('health_sync_error', null),
      );
    });
  });

  group('受け口が無い間のタップ', () {
    test('受け口が無い間は渡さず、最後の1件だけを取っておく', () {
      final dispatcher = syncDispatcher();

      dispatcher.dispatch(const NotificationTap('message', 'm1'));
      dispatcher.dispatch(const NotificationTap('message', 'm2'));

      expect(dispatcher.pendingTap, const NotificationTap('message', 'm2'));
    });

    test('受け口を設定すると、取っておいたタップを1回だけ渡す', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatch(const NotificationTap('message', 'm1'));
      dispatcher.dispatch(const NotificationTap('message', 'm2'));
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      expect(taps, [('message', 'm2')]);
      expect(dispatcher.pendingTap, isNull);

      // 受け口を設定し直しても、渡し済みのタップは渡さない
      dispatcher.setHandler((type, id) => taps.add((type, id)));
      expect(taps, hasLength(1));
    });

    test('取っておいたタップは、受け口を設定した直後の microtask で渡す（設定した場所では呼ばない）', () async {
      final dispatcher = NotificationTapDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatch(const NotificationTap('record_reminder', 'weight@1'));
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      // build の中で設定しても、受け口は build の外で呼ばれる
      expect(taps, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(taps, [('record_reminder', 'weight@1')]);
    });

    test('渡す前に受け口が外されたら、渡さずに取っておいたままにする', () async {
      final dispatcher = NotificationTapDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatch(const NotificationTap('message', 'm1'));
      dispatcher.setHandler((type, id) => taps.add((type, id)));
      dispatcher.setHandler(null);
      await Future<void>.delayed(Duration.zero);

      expect(taps, isEmpty);
      expect(dispatcher.pendingTap, const NotificationTap('message', 'm1'));
    });

    test('渡す前に新しいタップが来たら、新しいタップだけを渡す（古いタップを後から渡さない）', () async {
      final dispatcher = NotificationTapDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatch(const NotificationTap('message', 'old'));
      dispatcher.setHandler((type, id) => taps.add((type, id)));
      dispatcher.dispatch(const NotificationTap('message', 'new'));
      await Future<void>.delayed(Duration.zero);

      expect(taps, [('message', 'new')]);
    });

    test('受け口がある間のタップは、来たときにそのまま渡す', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      dispatcher.dispatch(const NotificationTap('message', 'm1'));
      dispatcher.dispatch(const NotificationTap('message', 'm2'));

      expect(taps, [('message', 'm1'), ('message', 'm2')]);
      expect(dispatcher.pendingTap, isNull);
    });

    test('受け口を外すと、また取っておく', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));
      dispatcher.setHandler(null);

      dispatcher.dispatch(const NotificationTap('message', 'm1'));

      expect(taps, isEmpty);
      expect(dispatcher.pendingTap, const NotificationTap('message', 'm1'));
    });

    test('受け口が例外を投げても、次のタップは渡す（例外は onError へ）', () {
      final errors = <Object>[];
      final dispatcher = syncDispatcher(errors: errors);
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) {
        if (id == 'bad') throw StateError('boom');
        taps.add((type, id));
      });

      dispatcher.dispatch(const NotificationTap('message', 'bad'));
      dispatcher.dispatch(const NotificationTap('message', 'ok'));

      expect(errors, hasLength(1));
      expect(taps, [('message', 'ok')]);
    });
  });

  group('clearPendingTap（ログアウトしたとき）', () {
    test('取っておいたタップを捨て、受け口を設定しても渡さない', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatch(const NotificationTap('record_reminder', 'weight@1'));
      dispatcher.clearPendingTap();
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      expect(dispatcher.pendingTap, isNull);
      expect(taps, isEmpty);
    });

    test('受け口を設定した直後の microtask で渡す前に捨てたら、渡さない', () async {
      final dispatcher = NotificationTapDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatch(const NotificationTap('record_reminder', 'weight@1'));
      dispatcher.setHandler((type, id) => taps.add((type, id)));
      dispatcher.clearPendingTap();
      await Future<void>.delayed(Duration.zero);

      expect(taps, isEmpty);
    });

    test('受け口と、その後のタップには影響しない', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      dispatcher.clearPendingTap();
      dispatcher.dispatch(const NotificationTap('message', 'm1'));

      expect(taps, [('message', 'm1')]);
    });

    test('起動時の通知の重複の判定はそのまま（捨てた起動時の通知と同じタップが後から届いても渡さない）', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatchLaunchResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      dispatcher.clearPendingTap();
      dispatcher.setHandler((type, id) => taps.add((type, id)));
      dispatcher.dispatchLocalResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      expect(taps, isEmpty);

      // 別の通知のタップは渡す
      dispatcher.dispatchLocalResponse(
        notificationId: 7000,
        payload: 'record_reminder:weight@202611080730',
      );
      expect(taps, [('record_reminder', 'weight@202611080730')]);
    });
  });

  group('FCM とローカル通知は同じ経路', () {
    test('FCM の data は type / id で渡す。type が無ければ渡さない', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      dispatcher.dispatchRemoteData({'type': 'message', 'id': 'm1'});
      dispatcher.dispatchRemoteData({'type': 'session_reminder'});
      dispatcher.dispatchRemoteData({'id': 'no-type'});

      expect(taps, [('message', 'm1'), ('session_reminder', null)]);
    });

    test('ローカル通知の payload は type:id で渡す', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      dispatcher.dispatchLocalResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      dispatcher.dispatchLocalResponse(
        notificationId: 9001,
        payload: 'health_sync_error',
      );

      expect(taps, [
        ('record_reminder', 'dinner@202611072000'),
        ('health_sync_error', null),
      ]);
    });

    test('受け口が無い間は、FCM・ローカル通知のどちらでも最後の1件だけを取っておく', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatchRemoteData({'type': 'message', 'id': 'm1'});
      dispatcher.dispatchLocalResponse(
        notificationId: 7000,
        payload: 'record_reminder:weight@202611070730',
      );
      dispatcher.setHandler((type, id) => taps.add((type, id)));
      expect(taps, [('record_reminder', 'weight@202611070730')]);

      dispatcher.setHandler(null);
      dispatcher.dispatchLocalResponse(
        notificationId: 7001,
        payload: 'record_reminder:breakfast@202611070900',
      );
      dispatcher.dispatchRemoteData({'type': 'message', 'id': 'm2'});
      dispatcher.setHandler((type, id) => taps.add((type, id)));
      expect(taps.last, ('message', 'm2'));
      expect(taps, hasLength(2));
    });
  });

  group('アプリを起動したローカル通知', () {
    test('起動時の通知は受け口が設定されるまで取っておき、設定したときに渡す', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatchLaunchResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      expect(taps, isEmpty);

      dispatcher.setHandler((type, id) => taps.add((type, id)));
      expect(taps, [('record_reminder', 'dinner@202611072000')]);
    });

    test('起動時の通知と同じ通知のタップが後から届いても、渡すのは1回だけ', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      dispatcher.dispatchLaunchResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      dispatcher.dispatchLocalResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );

      expect(taps, [('record_reminder', 'dinner@202611072000')]);

      // 別の通知のタップは渡す
      dispatcher.dispatchLocalResponse(
        notificationId: 7000,
        payload: 'record_reminder:weight@202611080730',
      );
      expect(taps.last, ('record_reminder', 'weight@202611080730'));
      expect(taps, hasLength(2));
    });

    test('受け口が無い間に起動時の通知と同じタップが届いても、取っておいた1件を1回だけ渡す', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];

      dispatcher.dispatchLaunchResponse(
        notificationId: 7004,
        payload: 'record_reminder:workout@202611071800',
      );
      dispatcher.dispatchLocalResponse(
        notificationId: 7004,
        payload: 'record_reminder:workout@202611071800',
      );
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      expect(taps, [('record_reminder', 'workout@202611071800')]);
    });

    test('起動時の通知を確かめる前に同じ通知のタップが届いていたら、起動時の通知としては渡さない', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      dispatcher.dispatchLocalResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      dispatcher.dispatchLaunchResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );

      expect(taps, [('record_reminder', 'dinner@202611072000')]);
    });

    test('通知で起動していなければ何も渡さず、その後のタップはふつうに渡す', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      dispatcher.dispatchLaunchResponse();
      expect(taps, isEmpty);

      dispatcher.dispatchLocalResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      dispatcher.dispatchLocalResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      // 起動時の通知ではないタップは、同じ通知でも重複として捨てない
      expect(taps, hasLength(2));
    });

    test('起動時の通知を扱うのは最初の1回だけ', () {
      final dispatcher = syncDispatcher();
      final taps = <(String, String?)>[];
      dispatcher.setHandler((type, id) => taps.add((type, id)));

      dispatcher.dispatchLaunchResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );
      dispatcher.dispatchLaunchResponse(
        notificationId: 7024,
        payload: 'record_reminder:dinner@202611072000',
      );

      expect(taps, hasLength(1));
    });
  });
}
