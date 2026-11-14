import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';

/// gotrue はトークン更新が再試行可能な失敗（ネットワーク断・5xx →
/// AuthRetryableFetchException）のとき、セッションを消さずに onAuthStateChange へ
/// 「エラー」を流す（ログアウトは signedOut イベント＝値で別に届く）。
/// onAuthStateChange は BehaviorSubject なので、直近がエラーなら新しい購読者にも再送される。
/// AuthNotifier がそのエラーを受けていないと、未処理の非同期例外になる。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // テストごとに Supabase を作り直す（onAuthStateChange も新しくなる）。
  // 直近のエラーが残ったまま次のテストの購読者へ再送されるのを避ける
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 通信しない（セッションなし・自動更新なし）。AuthNotifier が Supabase.instance を触るだけ
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  tearDown(() async {
    await Supabase.instance.dispose();
  });

  /// gotrue がトークン更新の再試行可能な失敗のときに行うのと同じ通知を再現する。
  ///
  /// 本物の更新失敗は、期限切れのセッションを保存しておき、通信の失敗と数秒の再試行を
  /// 待たないと起こせない。しかも TestWidgetsFlutterBinding の下では HTTP が常に 400 を
  /// 返すので、通信断（再試行可能な失敗）は作れない。そこで、そのとき gotrue が呼ぶ
  /// notifyException を直接呼ぶ（@internal な API だが、確かめたいのは
  /// 「流れてきたエラーを AuthNotifier が受けること」）。
  void notifyRetryableRefreshFailure() {
    Supabase.instance.client.auth
        // ignore: invalid_use_of_internal_member
        .notifyException(AuthRetryableFetchException(message: 'offline'));
  }

  /// [body] を、未処理の非同期例外を集めるゾーンで実行し、集まった例外を返す。
  /// AuthNotifier の購読（listen）はこのゾーンで作られるので、購読側が受けなかった
  /// エラーはここへ届く（受けていれば何も集まらない）。
  Future<List<Object>> collectUncaughtErrors(
    Future<void> Function() body,
  ) async {
    final uncaught = <Object>[];
    await runZonedGuarded(body, (error, stack) => uncaught.add(error));
    return uncaught;
  }

  group('AuthNotifier の認証イベント購読', () {
    test('更新失敗（オフラインなど）のエラーが流れても、未処理の例外にならず認証状態は変わらない', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final changes = <AsyncValue<User?>>[];

      final uncaught = await collectUncaughtErrors(() async {
        // AuthNotifier.build がこのゾーンで購読を始める
        container.listen(authNotifierProvider, (_, next) => changes.add(next));
        await container.read(authNotifierProvider.future);
        await pumpEventQueue();
        // 初回の構築までは対象外。ここから先の状態の変化を見る
        changes.clear();

        notifyRetryableRefreshFailure();
        await pumpEventQueue();
      });

      expect(uncaught, isEmpty);
      // エラーにならず、作り直されてもいない（作り直すと Loading を経て通知が来る）
      expect(changes, isEmpty);
      final state = container.read(authNotifierProvider);
      expect(state, isA<AsyncData<User?>>());
      expect(state.hasError, isFalse);
    });

    test('エラーを流した後に購読を始めても（直近のエラーが再送されても）未処理の例外にならない', () async {
      // 購読者がいない間に流す → BehaviorSubject の直近のイベントがエラーになる
      notifyRetryableRefreshFailure();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final uncaught = await collectUncaughtErrors(() async {
        // AuthNotifier.build が購読を始め、直近のエラーが再送される
        container.listen(authNotifierProvider, (_, __) {});
        await container.read(authNotifierProvider.future);
        await pumpEventQueue();
      });

      expect(uncaught, isEmpty);
      final state = container.read(authNotifierProvider);
      expect(state, isA<AsyncData<User?>>());
      expect(state.hasError, isFalse);
    });
  });
}
