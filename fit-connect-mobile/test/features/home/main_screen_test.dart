import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/app_update/data/app_config_repository.dart';
import 'package:fit_connect_mobile/features/app_update/presentation/force_update_dialog.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/consent/presentation/consent_dialog.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/main_screen.dart';
import 'package:fit_connect_mobile/features/home/providers/notification_navigation_provider.dart';
import 'package:fit_connect_mobile/features/messages/presentation/screens/message_screen.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/chat_input.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_screen_state.dart';
import 'package:fit_connect_mobile/features/workout/presentation/screens/workout_screen.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../messages/messages_test_support.dart';
import '../workout/presentation/workout_test_helpers.dart';
import 'home_test_support.dart';

/// メイン画面が、通知を押したときの「開く先」の要求（notificationNavigationProvider）を
/// 実行するテスト。
///
/// ホーム・メッセージ・プランの各タブが使うプロバイダーは、それぞれの画面のテストと同じ
/// 偽物に差し替える（Supabase・HealthKit には出ない）。表示前に置かれた要求を再現するため、
/// ProviderContainer を先に作って要求を置いてから、UncontrolledProviderScope で pump する。
class _DisabledHealthSettings extends HealthSettings {
  @override
  Future<HealthSettingsState> build() async => const HealthSettingsState(
        isEnabled: false,
        isWeightEnabled: false,
        isSleepEnabled: false,
        isMorningDialogEnabled: false,
      );
}

class _FakeHealthSync extends HealthSync {
  @override
  Future<void> build() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeMessages.sent.clear();
  });

  List<Override> overrides() => [
        // ホーム（trainerProfileProvider はメッセージ・プランと共通）
        ...normalHomeOverrides(),
        unreadMessageCountProvider.overrideWith((ref) async => 0),
        healthSettingsProvider.overrideWith(_DisabledHealthSettings.new),
        healthSyncProvider.overrideWith(_FakeHealthSync.new),
        // メッセージ
        authNotifierProvider.overrideWith(FakeAuth.new),
        paginatedMessagesProvider.overrideWith(() => FakeMessages(const [])),
        aiFeaturesEnabledProvider.overrideWith((ref) async => false),
        // プラン
        workoutScreenNotifierProvider.overrideWith(
          () => FakeWorkoutScreenNotifier(
            const WorkoutScreenState(
              overdueAssignments: [],
              todayAssignments: [],
              upcomingAssignments: [],
              weeklyData: {},
            ),
          ),
        ),
      ];

  /// [showMain] を渡すと、それが true になるまでは別の画面を出し、true で MainScreen に切り替わる
  /// （app.dart の _AuthLoadingScreen が、読み込みの後で MainScreen を出すのと同じ）
  Future<ProviderContainer> pumpMain(
    WidgetTester tester, {
    NotificationNavigationRequest? initialRequest,
    ValueListenable<bool>? showMain,
  }) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    if (initialRequest != null) {
      container
          .read(notificationNavigationProvider.notifier)
          .request(initialRequest);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: showMain == null
              ? const MainScreen()
              : ValueListenableBuilder<bool>(
                  valueListenable: showMain,
                  builder: (context, show, _) => show
                      ? const MainScreen()
                      : const Scaffold(body: Center(child: Text('読み込み中...'))),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  int currentTab(WidgetTester tester) =>
      tester.widget<FcBottomNav>(find.byType(FcBottomNav)).currentIndex;

  /// メッセージの入力欄の文字
  String inputText(WidgetTester tester) => tester
      .widget<TextField>(find.descendant(
        of: find.byType(ChatInput),
        matching: find.byType(TextField),
      ))
      .controller!
      .text;

  testWidgets('要求が無ければホームのまま', (tester) async {
    final container = await pumpMain(tester);

    expect(currentTab(tester), 0);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(container.read(notificationNavigationProvider), isNull);
  });

  testWidgets('表示前に置かれた要求（体重）: メッセージタブを開き、入力欄にタグを入れて、要求を消す', (tester) async {
    final container = await pumpMain(
      tester,
      initialRequest: const OpenMessagesWithDraft('#体重 '),
    );

    expect(currentTab(tester), 1);
    expect(find.byType(MessageScreen), findsOneWidget);
    expect(inputText(tester), '#体重 ');
    expect(container.read(notificationNavigationProvider), isNull);
    // 送信はしない
    expect(FakeMessages.sent, isEmpty);
  });

  testWidgets('表示前に置かれた要求（運動）: プランタブを開く', (tester) async {
    final container = await pumpMain(
      tester,
      initialRequest: const OpenPlanTab(),
    );

    expect(currentTab(tester), 2);
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(container.read(notificationNavigationProvider), isNull);
  });

  testWidgets('表示中に置かれた要求も、置かれたときに実行して消す', (tester) async {
    final container = await pumpMain(tester);
    final navigation = container.read(notificationNavigationProvider.notifier);
    expect(currentTab(tester), 0);

    navigation.request(const OpenPlanTab());
    await tester.pumpAndSettle();
    expect(currentTab(tester), 2);
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(container.read(notificationNavigationProvider), isNull);

    navigation.request(const OpenMessagesWithDraft('#食事:夕食 '));
    await tester.pumpAndSettle();
    expect(currentTab(tester), 1);
    expect(inputText(tester), '#食事:夕食 ');
    expect(container.read(notificationNavigationProvider), isNull);
  });

  testWidgets('メッセージタブを開いている間に次の要求が来ても、入力欄のタグを入れ直す', (tester) async {
    final container = await pumpMain(
      tester,
      initialRequest: const OpenMessagesWithDraft('#体重 '),
    );
    expect(inputText(tester), '#体重 ');

    container
        .read(notificationNavigationProvider.notifier)
        .request(const OpenMessagesWithDraft('#食事:朝食 '));
    await tester.pumpAndSettle();

    expect(currentTab(tester), 1);
    expect(inputText(tester), '#食事:朝食 ');
    expect(container.read(notificationNavigationProvider), isNull);
  });

  /// 通知を押したとき、メイン画面の上に画面が重なっていたら（アプリを離れたときに開いていた画面）、
  /// それを閉じてからタブを切り替える。閉じないと、切り替えが下で起きて見えないまま。
  /// ただし閉じるのを拒む画面（PopScope の canPop: false。同意・強制アップデートのダイアログなど）は
  /// 閉じずに残し、そこで止める
  group('メイン画面の上に画面が重なっているとき', () {
    const coveringText = '上に重なった画面';

    /// 上に積む画面（設定から開いた「記録のリマインダー」・記録の詳細などの代わり）
    Route<void> coveringRoute() => MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text(coveringText))),
        );

    testWidgets('表示中に置かれた要求（体重）: 上の画面とボトムシートを閉じてから、メッセージタブを入力欄にタグ入りで見せる',
        (tester) async {
      final container = await pumpMain(tester);
      final navigator = Navigator.of(tester.element(find.byType(MainScreen)));
      navigator.push(coveringRoute());
      await tester.pumpAndSettle();
      showModalBottomSheet<void>(
        context: tester.element(find.text(coveringText)),
        builder: (_) => const SizedBox(
          height: 200,
          child: Center(child: Text('ボトムシート')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ボトムシート'), findsOneWidget);
      // 覆われている間、メイン画面は見えていない
      expect(find.byType(MainScreen), findsNothing);

      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenMessagesWithDraft('#体重 '));
      await tester.pumpAndSettle();

      expect(find.text('ボトムシート'), findsNothing);
      expect(find.text(coveringText), findsNothing);
      expect(navigator.canPop(), isFalse);
      // 切り替えたタブが見えている（finder は覆われた画面を数えない）
      expect(currentTab(tester), 1);
      expect(find.byType(MessageScreen), findsOneWidget);
      expect(inputText(tester), '#体重 ');
      expect(container.read(notificationNavigationProvider), isNull);
      expect(FakeMessages.sent, isEmpty);
    });

    testWidgets('表示前に置かれた要求（運動）: MainScreen が現れたら、上の画面を閉じてからプランタブを見せる',
        (tester) async {
      final showMain = ValueNotifier(false);
      addTearDown(showMain.dispose);
      final container = await pumpMain(tester, showMain: showMain);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(coveringRoute());
      await tester.pumpAndSettle();

      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenPlanTab());
      showMain.value = true;
      await tester.pumpAndSettle();

      expect(find.text(coveringText), findsNothing);
      expect(navigator.canPop(), isFalse);
      expect(currentTab(tester), 2);
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(container.read(notificationNavigationProvider), isNull);
    });

    testWidgets('要求が無ければ、MainScreen が現れても上の画面は閉じない', (tester) async {
      final showMain = ValueNotifier(false);
      addTearDown(showMain.dispose);
      await pumpMain(tester, showMain: showMain);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(coveringRoute());
      await tester.pumpAndSettle();

      showMain.value = true;
      await tester.pumpAndSettle();

      expect(find.text(coveringText), findsOneWidget);
      expect(navigator.canPop(), isTrue);
    });

    testWidgets('同意ダイアログは閉じずに一番上に残し、その下でタブを切り替える', (tester) async {
      final container = await pumpMain(tester);
      showConsentDialog(
        tester.element(find.byType(MainScreen)),
        userId: 'client-1',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ConsentDialog), findsOneWidget);

      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenMessagesWithDraft('#食事:夕食 '));
      await tester.pumpAndSettle();

      // 同意が記録されるまで閉じない（一番上のまま）
      expect(find.byType(ConsentDialog), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(ConsentDialog)))!.isCurrent,
        isTrue,
      );
      // その下ではタブが切り替わり、入力欄にタグが入っている
      expect(currentTab(tester), 1);
      expect(inputText(tester), '#食事:夕食 ');
      expect(container.read(notificationNavigationProvider), isNull);
    });

    testWidgets('同意ダイアログは名前でも見分ける（PopScope が無くなっても閉じない）', (tester) async {
      const nameOnlyText = '同意ダイアログの名前だけを持つ画面';
      final container = await pumpMain(tester);
      // PopScope の無い、同意ダイアログの名前だけを持つ route
      showDialog<void>(
        context: tester.element(find.byType(MainScreen)),
        routeSettings: const RouteSettings(name: consentDialogRouteName),
        builder: (_) => const AlertDialog(content: Text(nameOnlyText)),
      );
      await tester.pumpAndSettle();

      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenPlanTab());
      await tester.pumpAndSettle();

      expect(find.text(nameOnlyText), findsOneWidget);
      expect(currentTab(tester), 2);
      expect(container.read(notificationNavigationProvider), isNull);
    });

    testWidgets('強制アップデートのダイアログも閉じずに一番上に残し、その下でタブを切り替える', (tester) async {
      final container = await pumpMain(tester);
      showForceUpdateDialog(
        tester.element(find.byType(MainScreen)),
        config: const AppConfig(minSupportedVersion: '9.9.9'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ForceUpdateDialog), findsOneWidget);

      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenPlanTab());
      await tester.pumpAndSettle();

      // アップデートするまで閉じない（一番上のまま）
      expect(find.byType(ForceUpdateDialog), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(ForceUpdateDialog)))!
            .isCurrent,
        isTrue,
      );
      // その下ではプランタブに切り替わっている
      expect(currentTab(tester), 2);
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(container.read(notificationNavigationProvider), isNull);
    });

    testWidgets('閉じるのを拒む画面（canPop: false）は残し、その上の画面だけ閉じる', (tester) async {
      const guardedText = '閉じるのを拒む画面';
      final container = await pumpMain(tester);
      final navigator = Navigator.of(tester.element(find.byType(MainScreen)));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const PopScope(
            canPop: false,
            child: Scaffold(body: Center(child: Text(guardedText))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.push(coveringRoute());
      await tester.pumpAndSettle();

      container
          .read(notificationNavigationProvider.notifier)
          .request(const OpenMessagesWithDraft('#体重 '));
      await tester.pumpAndSettle();

      // 上の画面は閉じ、拒む画面はそこで止まって一番上に残る
      expect(find.text(coveringText), findsNothing);
      expect(find.text(guardedText), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.text(guardedText)))!.isCurrent,
        isTrue,
      );
      // 要求は実行済み（覆われたメイン画面の中でタブは切り替わっている）
      expect(
        tester
            .widget<FcBottomNav>(find.byType(FcBottomNav, skipOffstage: false))
            .currentIndex,
        1,
      );
      expect(container.read(notificationNavigationProvider), isNull);
    });
  });
}
