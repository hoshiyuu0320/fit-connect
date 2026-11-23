import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/app.dart';
import 'package:fit_connect_mobile/features/app_update/providers/force_update_provider.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/profile_setup_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/registration_complete_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/welcome_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/widgets/client_load_error_view.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/features/consent/data/consent_repository.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/main_screen.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/morning_dialog_provider.dart';

import 'features/home/home_test_support.dart'
    show normalHomeOverrides, sampleClient;

/// 同意済みの ConsentRepository。認証ゲートの同意ゲートが、同意ダイアログを出さずに通す。
/// Supabase には出ない
class _ConsentedRepository implements ConsentRepository {
  @override
  Future<bool> hasCurrentConsent(String userId) async => true;

  @override
  Future<void> recordConsent(String userId) async {}
}

/// 朝のダイアログを出さない判定（時刻・設定に依らず false）
class _NoMorningDialog extends MorningDialog {
  @override
  Future<bool> build() async => false;
}

/// クライアントを取得できたとき（MainScreen のホームが出る）に必要な差し替え。
/// Supabase・端末の機能には出ない。
///
/// ホームの provider は home_test_support.dart でまとめて差し替える。その中の
/// currentClientProvider は、pumpApp が後ろに置く差し替えが上書きする
/// （同じ provider の override が重なったら、後のものが効く）。
/// 残りは、取得できたときの認証ゲートの副作用の止め先
List<Override> _mainScreenOverrides() => [
      ...normalHomeOverrides(),
      // MainScreen の下部ナビが見る未読の有無（未読なし）
      unreadMessageCountProvider.overrideWith((ref) async => 0),
      // 同意ゲート: 同意済み（同意ダイアログを出さない）
      consentRepositoryProvider.overrideWithValue(_ConsentedRepository()),
      // 朝のダイアログ: 時刻・設定に依らず出さない
      morningDialogProvider.overrideWith(_NoMorningDialog.new),
    ];

/// 認証ゲート（lib/app.dart の MyApp → _AuthLoadingScreen）。本物の MyApp を出して確かめる。
///
/// ログイン済み（端末にセッションが残っている）で `clients` の取得に失敗した（オフラインなど）とき、
/// サインアウトせずに「読み込めませんでした」と再試行の画面を出すこと。
/// 行が無いとき（取得は成功して null）は、今まで通りサインアウトすること。
/// 取得できたあと（MainScreen のホームが出ている間）は、取り直しの失敗で画面を替えないこと。
///
/// 取得できた場合の MainScreen は、タブのうち今のタブ（ホーム）だけが作られる。
/// ホームの provider は home_test_support.dart でまとめて差し替える。
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // MyApp・各画面が Supabase.instance を触る（通信は testWidgets のモックで常に 400）
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  /// currentClientProvider（clients の取得）の差し替え先が呼ばれた回数
  late int fetchCount;

  /// clients の取得の結果。テストごとに差し替える（既定は失敗 = オフライン）
  late Future<Client?> Function() fetchClient;

  setUp(() async {
    fetchCount = 0;
    fetchClient = () => Future<Client?>.error(Exception('offline'));

    // コールドスタートで、端末に残っていたセッションが復元された状態にする
    // （起動時と同じ initialSession が流れる）。前のテストでサインアウトしていても、
    // ここで毎回セッションありに戻す。
    // access_token は JWT ではない文字列にしてある。有効期限を読み取れず「期限なし」扱いになるので、
    // トークンの自動更新は走らない（通信しない）
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'refresh_token': 'test-refresh-token',
        'user': {
          'id': 'client-1',
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });

  Session? currentSession() => Supabase.instance.client.auth.currentSession;

  /// 本物の MyApp を出す。clients の取得（currentClientProvider）と強制アップデートの判定を差し替える。
  /// [overrides] は、それに加える差し替え（取得できたときの MainScreen 用など）。
  /// [prepare] は、アプリを出す前に provider の状態を整えたいとき用。
  /// 作った container を返す
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    List<Override> overrides = const [],
    void Function(ProviderContainer container)? prepare,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        ...overrides,
        // 以下は [overrides] より後ろに置く（同じ provider が重なったら後のものが効く）
        // 強制アップデートの判定は通信しない（更新不要）
        forceUpdateProvider.overrideWith((ref) async => null),
        // clients の取得。呼ばれた回数を数え、結果はテストごとに決める
        currentClientProvider.overrideWith((ref) {
          fetchCount++;
          return fetchClient();
        }),
      ],
    );
    // ウィジェットの木が外れたあと（テストの本体が終わったあと）に破棄される
    addTearDown(container.dispose);
    prepare?.call(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    // 認証ストリームの最初のイベント → 認証ゲート → clients の取得（差し替え）の結果まで進める
    await tester.pumpAndSettle();
    return container;
  }

  /// アプリを背景に回す。テストが途中で失敗しても前面に戻す（他のテストに状態を持ち越さない）
  Future<void> pauseApp(WidgetTester tester) async {
    addTearDown(
      () => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  /// アプリを前面に戻す
  Future<void> resumeApp(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
  }

  /// サインアウトが終わる（signedOut が流れて、画面が替わる）まで進める。
  ///
  /// gotrue の signOut は、端末のセッションを先に消したあと、PKCE の保存先
  /// （SharedPreferencesGotrueAsyncStorage）の準備を待ってから signedOut を流す。
  /// その待ちの Future は setUpAll（実際の時計）で作られているので、testWidgets の偽の時計の中
  /// だけでは進まない。runAsync で実際のイベントループを一度回して進める
  Future<void> settleSignOut(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pumpAndSettle();
  }

  /// 確認ダイアログの中のボタン
  Finder dialogButton(String label) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, label),
      );

  group('clients の取得に失敗したとき（オフラインなど）', () {
    testWidgets('サインアウトせず、再試行の画面を出す（ウェルカムにならない・時間がたっても同じ）', (tester) async {
      await pumpApp(tester);

      expect(fetchCount, 1);
      expect(find.byType(ClientLoadErrorView), findsOneWidget);
      expect(find.text('ユーザー情報を読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      // サインアウトしていない（端末のセッションが残っている）
      expect(currentSession(), isNotNull);

      // 数フレーム・数秒進めても同じ（自動再試行の周期 15 秒より手前）
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.byType(ClientLoadErrorView), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(currentSession(), isNotNull);
      expect(tester.takeException(), isNull);
    });

    group('再試行', () {
      testWidgets('「再試行」で取り直す: 取得中は「読み込み中…」で押せず、失敗すると「再試行」に戻る', (tester) async {
        await pumpApp(tester);
        expect(fetchCount, 1);

        // 2 回目の取得は、結果を出さずに止めておく
        final second = Completer<Client?>();
        fetchClient = () => second.future;

        await tester.tap(find.text('再試行'));
        await tester.pump();
        await tester.pump();

        expect(fetchCount, 2);
        // 全画面の読み込みには替わらず、同じ画面のまま「再試行」が読み込み表示になる
        expect(find.byType(ClientLoadErrorView), findsOneWidget);
        expect(find.text('読み込み中…'), findsOneWidget);
        expect(find.text('再試行'), findsNothing);

        // 取得中に押しても、重ねて取りに行かない
        await tester.tap(find.text('読み込み中…'));
        await tester.pump();
        expect(fetchCount, 2);

        // 取得が失敗で終わると、「再試行」に戻る（サインアウトしない）
        second.completeError(Exception('still offline'));
        await tester.pumpAndSettle();

        expect(fetchCount, 2);
        expect(find.byType(ClientLoadErrorView), findsOneWidget);
        expect(find.text('再試行'), findsOneWidget);
        expect(find.text('読み込み中…'), findsNothing);
        expect(find.byType(WelcomeScreen), findsNothing);
        expect(currentSession(), isNotNull);
      });

      testWidgets('アプリが前面に戻ったとき、取得に失敗したままなら取り直す（背景に回っただけでは取り直さない）',
          (tester) async {
        await pumpApp(tester);
        expect(fetchCount, 1);

        await pauseApp(tester);
        expect(fetchCount, 1);
        // 背景に回っている間に時間がたっても、自動再試行は通信しない
        await tester.pump(const Duration(seconds: 30));
        expect(fetchCount, 1);

        await resumeApp(tester);

        expect(fetchCount, 2);
        // 失敗が続けば、再試行の画面のまま（サインアウトしない）
        expect(find.byType(ClientLoadErrorView), findsOneWidget);
        expect(find.byType(WelcomeScreen), findsNothing);
        expect(currentSession(), isNotNull);
      });

      testWidgets('取り直しの最中に前面へ戻っても、重ねて取りに行かない', (tester) async {
        await pumpApp(tester);

        final second = Completer<Client?>();
        fetchClient = () => second.future;
        await tester.tap(find.text('再試行'));
        await tester.pump();
        await tester.pump();
        expect(fetchCount, 2);
        expect(find.text('読み込み中…'), findsOneWidget);

        await pauseApp(tester);
        await resumeApp(tester);

        expect(fetchCount, 2);

        second.completeError(Exception('still offline'));
        await tester.pumpAndSettle();
        expect(find.text('再試行'), findsOneWidget);
        expect(fetchCount, 2);
      });

      testWidgets('15 秒ごとに自動で取り直す（失敗が続けば次の周期でもう一度）', (tester) async {
        await pumpApp(tester);
        expect(fetchCount, 1);

        // 周期（15 秒）の手前では取り直さない
        await tester.pump(const Duration(seconds: 14));
        expect(fetchCount, 1);

        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(fetchCount, 2);

        // 15 秒の間には、周期がちょうど 1 回ある
        await tester.pump(const Duration(seconds: 15));
        await tester.pump();
        expect(fetchCount, 3);

        expect(find.byType(ClientLoadErrorView), findsOneWidget);
        expect(find.byType(WelcomeScreen), findsNothing);
        expect(currentSession(), isNotNull);
      });

      testWidgets('取得に失敗したあとの再試行で「行なし」になったら、今まで通りサインアウトしてウェルカムへ',
          (tester) async {
        await pumpApp(tester);
        expect(find.byType(ClientLoadErrorView), findsOneWidget);
        expect(currentSession(), isNotNull);

        // 回線は戻ったが、clients の行は無かった
        fetchClient = () async => null;
        await tester.tap(find.text('再試行'));
        await settleSignOut(tester);

        expect(fetchCount, 2);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(find.byType(ClientLoadErrorView), findsNothing);
        expect(currentSession(), isNull);
      });
    });

    group('読み込み失敗の画面の「ログアウト」', () {
      testWidgets('確認のあと「ログアウト」でサインアウトし、ウェルカムへ', (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('ログアウト'));
        await tester.pumpAndSettle();

        expect(find.text('ログアウトしますか？'), findsOneWidget);
        // 確認の段階では、まだサインアウトしていない
        expect(currentSession(), isNotNull);
        expect(find.byType(WelcomeScreen), findsNothing);

        await tester.tap(dialogButton('ログアウト'));
        await settleSignOut(tester);

        // /logout は（テストでは常に 400 で）失敗するが、端末のセッションは先に消えて signedOut が流れる
        expect(currentSession(), isNull);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(find.byType(ClientLoadErrorView), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('確認で「キャンセル」なら、サインアウトせずこの画面のまま', (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('ログアウト'));
        await tester.pumpAndSettle();
        await tester.tap(dialogButton('キャンセル'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(ClientLoadErrorView), findsOneWidget);
        expect(find.byType(WelcomeScreen), findsNothing);
        expect(currentSession(), isNotNull);
      });
    });

    group('登録フロー中', () {
      testWidgets('トレーナーを選択済み: プロフィール設定画面を出す（再試行の画面にもサインアウトにもならない）',
          (tester) async {
        await pumpApp(
          tester,
          prepare: (container) => container
              .read(registrationNotifierProvider.notifier)
              .setTrainerId('trainer-1'),
        );

        expect(fetchCount, 1);
        expect(find.byType(ProfileSetupScreen), findsOneWidget);
        expect(find.byType(ClientLoadErrorView), findsNothing);
        expect(find.byType(WelcomeScreen), findsNothing);
        expect(currentSession(), isNotNull);
      });

      testWidgets('登録完了: 登録完了画面を出す（サインアウトしない）', (tester) async {
        await pumpApp(
          tester,
          prepare: (container) => container
              .read(registrationNotifierProvider.notifier)
              .setRegistrationComplete(true),
        );

        expect(fetchCount, 1);
        expect(find.byType(RegistrationCompleteScreen), findsOneWidget);
        expect(find.byType(ClientLoadErrorView), findsNothing);
        expect(find.byType(WelcomeScreen), findsNothing);
        expect(currentSession(), isNotNull);
      });
    });
  });

  group('clients の行が無いとき（取得は成功して null）', () {
    testWidgets('今まで通りサインアウトして、ウェルカムを出す', (tester) async {
      fetchClient = () async => null;

      await pumpApp(tester);
      await settleSignOut(tester);

      expect(fetchCount, 1);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(ClientLoadErrorView), findsNothing);
      expect(currentSession(), isNull);
    });
  });

  group('認証ストリームのエラー', () {
    /// gotrue がトークン更新の再試行可能な失敗（オフライン・5xx）のときに行うのと同じ通知を、
    /// onAuthStateChange へ「エラー」として流す。
    ///
    /// 本物の更新失敗は、期限切れのセッションを保存して、通信の失敗と数秒の再試行を待たないと
    /// 起こせない。しかもテストでは HTTP が常に 400 を返すので、通信断（再試行可能な失敗）は作れない。
    /// そこで、そのとき gotrue が呼ぶ notifyException を直接呼ぶ
    /// （@internal な API だが、確かめたいのは「流れてきたエラーを画面側がどう扱うか」）
    void notifyRetryableRefreshFailure() {
      Supabase.instance.client.auth
          // ignore: invalid_use_of_internal_member
          .notifyException(AuthRetryableFetchException(message: 'offline'));
    }

    testWidgets('セッションがある間にエラーが流れても、ログアウト扱いにしない（再試行の画面のまま・セッションも残る）',
        (tester) async {
      await pumpApp(tester);
      expect(find.byType(ClientLoadErrorView), findsOneWidget);

      notifyRetryableRefreshFailure();
      await tester.pumpAndSettle();

      // エラーのとき StreamBuilder の data は無くなる。それでもウェルカムにならない
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(ClientLoadErrorView), findsOneWidget);
      expect(currentSession(), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('エラーのあとも、再試行はそのまま使える', (tester) async {
      await pumpApp(tester);
      notifyRetryableRefreshFailure();
      await tester.pumpAndSettle();

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      expect(find.byType(ClientLoadErrorView), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(currentSession(), isNotNull);
    });

    testWidgets('セッションが無い（サインアウト済み）ときにエラーが流れても、ウェルカムのまま', (tester) async {
      fetchClient = () async => null;
      await pumpApp(tester);
      await settleSignOut(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(currentSession(), isNull);

      notifyRetryableRefreshFailure();
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(ClientLoadErrorView), findsNothing);
      expect(currentSession(), isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('クライアントを取得できたあと（MainScreen のホームが出ている）', () {
    testWidgets('取り直しに失敗しても MainScreen のまま（再試行の画面にもウェルカムにもならない）',
        (tester) async {
      // 1 回目は取得できる。2 回目以降は失敗する（そのあと回線が切れた、など）
      fetchClient = () => fetchCount == 1
          ? Future<Client?>.value(sampleClient())
          : Future<Client?>.error(Exception('offline'));
      final container = await pumpApp(
        tester,
        overrides: _mainScreenOverrides(),
      );

      expect(fetchCount, 1);
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('こんにちは、佐藤さん'), findsOneWidget);
      expect(find.byType(ClientLoadErrorView), findsNothing);

      // 取り直し（設定画面での更新後など）。取得は失敗する
      container.invalidate(currentClientProvider);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      // 取り直しが失敗したことは、provider の状態として残る
      expect(container.read(currentClientProvider).hasError, isTrue);
      // それでも、取得済みのクライアントがいる間は画面を替えない（前の値で MainScreen を出し続ける）
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('こんにちは、佐藤さん'), findsOneWidget);
      expect(find.byType(ClientLoadErrorView), findsNothing);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(currentSession(), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '読み込み失敗の画面でログアウトを確認している間に、取り直しが成功して MainScreen に替わっても、「ログアウト」でサインアウトする',
        (tester) async {
      await pumpApp(tester, overrides: _mainScreenOverrides());
      expect(find.byType(ClientLoadErrorView), findsOneWidget);

      // ログアウトの確認ダイアログを開く
      await tester.tap(find.text('ログアウト'));
      await tester.pumpAndSettle();
      expect(find.text('ログアウトしますか？'), findsOneWidget);

      // ダイアログを開いたまま、前面に戻ったときの取り直しが成功する（回線が戻った）
      fetchClient = () => Future<Client?>.value(sampleClient());
      await pauseApp(tester);
      await resumeApp(tester);
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      // 画面は MainScreen に替わった（再試行の画面は外れた）が、確認ダイアログは残っている
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(ClientLoadErrorView), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(currentSession(), isNotNull);

      // 確認した「ログアウト」は、画面が外れていても捨てられずにサインアウトされる
      await tester.tap(dialogButton('ログアウト'));
      await settleSignOut(tester);

      expect(currentSession(), isNull);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
