import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/presentation/widgets/client_load_error_view.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// クライアント情報の読み込み失敗画面。
/// サインアウトせずに、手動の再試行・一定間隔の自動再試行・ログアウト（確認つき）を出す。
void main() {
  late int retryCount;
  late int signOutCount;

  setUp(() {
    retryCount = 0;
    signOutCount = 0;
  });

  /// 画面を出す。[autoRetryInterval] が null なら、コンストラクタの既定のまま
  Future<void> pumpView(
    WidgetTester tester, {
    bool isRetrying = false,
    Duration? autoRetryInterval,
    Future<void> Function()? onSignOut,
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    void onRetry() => retryCount++;
    Future<void> defaultSignOut() async {
      signOutCount++;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: autoRetryInterval == null
            ? ClientLoadErrorView(
                isRetrying: isRetrying,
                onRetry: onRetry,
                onSignOut: onSignOut ?? defaultSignOut,
              )
            : ClientLoadErrorView(
                isRetrying: isRetrying,
                onRetry: onRetry,
                onSignOut: onSignOut ?? defaultSignOut,
                autoRetryInterval: autoRetryInterval,
              ),
      ),
    );
  }

  /// 確認ダイアログの中のボタン
  Finder dialogButton(String label) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, label),
      );

  /// 画面の「ログアウト」を押して、確認ダイアログを開く
  Future<void> openLogoutDialog(WidgetTester tester) async {
    await tester.tap(find.text('ログアウト'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  }

  group('ClientLoadErrorView 表示', () {
    testWidgets('メッセージと「再試行」「ログアウト」が表示される（確認ダイアログは押すまで出ない）', (tester) async {
      await pumpView(tester);

      expect(find.text('ユーザー情報を読み込めませんでした'), findsOneWidget);
      expect(
        find.text('通信状況を確認してください。つながると自動で読み込み直します。'),
        findsOneWidget,
      );
      expect(find.text('再試行'), findsOneWidget);
      expect(find.text('ログアウト'), findsOneWidget);

      // 色だけに頼らず、エラーのアイコンを併用する
      expect(find.byType(FcStateMessage), findsOneWidget);
      expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);
      expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);

      expect(find.byType(AlertDialog), findsNothing);
      // 表示しただけではサインアウトも再試行もしない
      expect(signOutCount, 0);
      expect(retryCount, 0);
    });

    testWidgets('レイアウト: 左右の余白 20・メッセージは中央付近・操作は下部・背景はテーマ既定', (tester) async {
      await pumpView(tester);

      final message = tester.getRect(find.byType(FcStateMessage));
      final retry = tester.getRect(find.widgetWithText(FcButton, '再試行'));
      final logout = tester.getRect(find.widgetWithText(FcButton, 'ログアウト'));

      // 左右の余白は AppSpacing.pageHorizontalOf（390 幅では 20）
      expect(message.left, AppSpacing.pageHorizontal);
      expect(message.right, 390 - AppSpacing.pageHorizontal);
      expect(retry.left, AppSpacing.pageHorizontal);
      expect(retry.right, 390 - AppSpacing.pageHorizontal);

      // 上から メッセージ → 再試行 → ログアウト
      expect(message.bottom, lessThan(retry.top));
      expect(retry.bottom, lessThan(logout.top));
      // メッセージは画面の中央付近、操作は下部（下端の余白 24）
      expect(message.center.dy, inInclusiveRange(844 * 0.25, 844 * 0.75));
      expect(logout.bottom, closeTo(844 - AppSpacing.xxl, 0.5));
      // 「ログアウト」は控えめな文字だけの操作。横幅いっぱいにしない（中央に置く）
      expect(logout.center.dx, closeTo(390 / 2, 0.5));
      expect(logout.width, lessThan(retry.width));

      // 背景はテーマ既定（画面側で色を塗らない）
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isNull);
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,
        AppColorsExtension.light.background,
      );
    });

    testWidgets('幅 360 未満（320）では左右の余白が 16 になる', (tester) async {
      await pumpView(tester, size: const Size(320, 568));

      final message = tester.getRect(find.byType(FcStateMessage));
      final retry = tester.getRect(find.widgetWithText(FcButton, '再試行'));
      expect(message.left, AppSpacing.pageHorizontalCompact);
      expect(message.right, 320 - AppSpacing.pageHorizontalCompact);
      expect(retry.left, AppSpacing.pageHorizontalCompact);
      expect(retry.right, 320 - AppSpacing.pageHorizontalCompact);
      expect(tester.takeException(), isNull);
    });

    testWidgets('「再試行」「ログアウト」のタップ領域は 44 以上', (tester) async {
      await pumpView(tester);

      for (final label in ['再試行', 'ログアウト']) {
        final size = tester.getSize(find.widgetWithText(FcButton, label));
        expect(size.height, greaterThanOrEqualTo(AppSizes.minTouch),
            reason: label);
        expect(size.width, greaterThanOrEqualTo(AppSizes.minTouch),
            reason: label);
      }
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final isDark = brightness == Brightness.dark;
      final label = isDark ? 'ダーク' : 'ライト';

      testWidgets('$label: 色はテーマに追従する（エラーのアイコンは error・主ボタンは actionFill）',
          (tester) async {
        await pumpView(
          tester,
          theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        final colors =
            isDark ? AppColorsExtension.dark : AppColorsExtension.light;

        expect(
          tester.widget<Icon>(find.byIcon(LucideIcons.alertCircle)).color,
          colors.error,
        );
        final retryFace = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.widgetWithText(FcButton, '再試行'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
            (retryFace.decoration as BoxDecoration).color, colors.actionFill);
        // 「ログアウト」は accent の文字（面は透明）
        final logoutText = tester.widget<Text>(
          find.descendant(
            of: find.widgetWithText(FcButton, 'ログアウト'),
            matching: find.text('ログアウト'),
          ),
        );
        expect(logoutText.style?.color, colors.accent);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label・文字拡大 1.35（390×844）: オーバーフローせず、操作は画面内に残る',
          (tester) async {
        await pumpView(
          tester,
          theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
          textScale: 1.35,
        );

        expect(tester.takeException(), isNull);
        for (final text in [
          'ユーザー情報を読み込めませんでした',
          '通信状況を確認してください。つながると自動で読み込み直します。',
          '再試行',
          'ログアウト',
        ]) {
          final rect = tester.getRect(find.text(text));
          expect(rect.left, greaterThanOrEqualTo(0), reason: text);
          expect(rect.right, lessThanOrEqualTo(390), reason: text);
        }
        // 縮めずに積み直し、操作は画面内に残る
        expect(
          tester.getRect(find.widgetWithText(FcButton, 'ログアウト')).bottom,
          lessThanOrEqualTo(844),
        );
        expect(
          tester.getRect(find.byType(FcStateMessage)).bottom,
          lessThan(tester.getRect(find.widgetWithText(FcButton, '再試行')).top),
        );
      });
    }

    testWidgets('小さい画面（320×480）+ 文字拡大 2.0: 縮めずスクロールで収まり、「ログアウト」まで届く',
        (tester) async {
      await pumpView(
        tester,
        size: const Size(320, 480),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      // 画面に収まりきらないので、縦にスクロールできる
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      // 下までスクロールすれば「ログアウト」に届き、押せる
      await tester.ensureVisible(find.text('ログアウト'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ログアウト'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ClientLoadErrorView 再試行', () {
    testWidgets('「再試行」をタップすると onRetry が 1 回呼ばれる', (tester) async {
      await pumpView(tester);

      await tester.tap(find.text('再試行'));
      await tester.pump();

      expect(retryCount, 1);
      expect(signOutCount, 0);
    });

    testWidgets('isRetrying: true なら「読み込み中…」になり、押しても onRetry は呼ばれない',
        (tester) async {
      await pumpView(tester, isRetrying: true);

      expect(find.text('読み込み中…'), findsOneWidget);
      expect(find.text('再試行'), findsNothing);

      await tester.tap(find.text('読み込み中…'));
      await tester.pump();

      expect(retryCount, 0);
    });
  });

  group('ClientLoadErrorView 自動再試行', () {
    testWidgets('間隔の既定は 15 秒', (tester) async {
      expect(
        ClientLoadErrorView.defaultAutoRetryInterval,
        const Duration(seconds: 15),
      );

      await pumpView(tester);

      expect(
        tester
            .widget<ClientLoadErrorView>(find.byType(ClientLoadErrorView))
            .autoRetryInterval,
        ClientLoadErrorView.defaultAutoRetryInterval,
      );
    });

    testWidgets('既定の 15 秒ごとに onRetry が呼ばれる（それより前には呼ばれない）', (tester) async {
      await pumpView(tester);

      await tester.pump(const Duration(seconds: 14));
      expect(retryCount, 0);

      await tester.pump(const Duration(seconds: 1));
      expect(retryCount, 1);

      await tester.pump(const Duration(seconds: 15));
      expect(retryCount, 2);
    });

    testWidgets('isRetrying: true の間は呼ばれず、false に戻ると次の周期から再開する',
        (tester) async {
      await pumpView(tester, isRetrying: true);

      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(retryCount, 0);

      await pumpView(tester); // 読み込みが終わった
      await tester.pump(const Duration(seconds: 15));
      expect(retryCount, 1);
    });

    testWidgets('autoRetryInterval を指定できる。変えると張り直す（古い周期では呼ばれない）',
        (tester) async {
      await pumpView(tester, autoRetryInterval: const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(retryCount, 1);

      // 3 秒たったところで 20 秒間隔に変える → そこから数え直す（t=8 から 20 秒後の t=28）
      await tester.pump(const Duration(seconds: 3));
      await pumpView(tester, autoRetryInterval: const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 19));
      expect(retryCount, 1); // 古い 5 秒の周期（t=10, 15, 20, 25）では呼ばれない

      await tester.pump(const Duration(seconds: 1));
      expect(retryCount, 2);
    });

    testWidgets('間隔が 0 以下なら周期タイマーを作らない（自動再試行しない）', (tester) async {
      var zeroPeriodTimers = 0;
      // 0 のままタイマーを作ると時計を進めた瞬間に回り続けて固まるので、作成だけを数える
      await runZoned(
        () => pumpView(tester, autoRetryInterval: Duration.zero),
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, f) {
            if (period <= Duration.zero) zeroPeriodTimers++;
            return parent.createPeriodicTimer(zone, period, f);
          },
        ),
      );

      expect(zeroPeriodTimers, 0);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('画面を外すとタイマーも止まる（外したあとに時間を進めても増えない）', (tester) async {
      await pumpView(tester);
      await tester.pump(const Duration(seconds: 15));
      expect(retryCount, 1);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(find.byType(ClientLoadErrorView), findsNothing);

      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(minutes: 5));
      expect(retryCount, 1);
      // タイマーが残っていれば、テスト終了時の検査（pending timer）でも失敗する
    });

    testWidgets('アプリがバックグラウンドの間は呼ばれず、前面に戻ると再開する', (tester) async {
      // 他のテストに状態を持ち越さない（失敗しても前面に戻す）
      addTearDown(
        () => tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      await pumpView(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      expect(retryCount, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 15));
      expect(retryCount, 1);
    });

    testWidgets('前面でない状態（inactive / hidden）の間も呼ばれない', (tester) async {
      addTearDown(
        () => tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      await pumpView(tester);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump(const Duration(seconds: 15));
        expect(retryCount, 0, reason: '$state');

        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }

      await tester.pump(const Duration(seconds: 15));
      expect(retryCount, 1);
    });

    testWidgets('ログアウトの確認ダイアログを開いている間は呼ばれない（周期を何度またいでも）', (tester) async {
      await pumpView(tester);
      await openLogoutDialog(tester);

      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(minutes: 1));

      // 成功して画面が差し替わると、確認している操作の足元が変わってしまうので呼ばない
      expect(retryCount, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    // どう閉じても、フラグは下りて自動再試行が再開する（その場では呼ばず、次の周期から）
    final closeDialog = <String, Future<void> Function(WidgetTester)>{
      '「キャンセル」': (tester) => tester.tap(dialogButton('キャンセル')),
      '枠外タップ': (tester) => tester.tapAt(const Offset(8, 8)),
      '「ログアウト」': (tester) => tester.tap(dialogButton('ログアウト')),
    };
    for (final entry in closeDialog.entries) {
      testWidgets('ログアウトの確認ダイアログを${entry.key}で閉じたあとは、次の周期から再開する',
          (tester) async {
        await pumpView(tester);
        await openLogoutDialog(tester);
        await tester.pump(const Duration(seconds: 15));
        expect(retryCount, 0);

        await entry.value(tester);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(retryCount, 0);

        await tester.pump(const Duration(seconds: 15));
        expect(retryCount, 1);
      });
    }
  });

  group('ClientLoadErrorView ログアウト', () {
    testWidgets('「ログアウト」で確認ダイアログが出る（押しただけでは onSignOut は呼ばれない）', (tester) async {
      await pumpView(tester);

      await openLogoutDialog(tester);

      // 設定画面のログアウトと同じ文言
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('ログアウト'),
        ),
        findsNWidgets(2), // タイトルと確認ボタン
      );
      expect(find.text('ログアウトしますか？'), findsOneWidget);
      expect(dialogButton('キャンセル'), findsOneWidget);
      expect(dialogButton('ログアウト'), findsOneWidget);
      expect(signOutCount, 0);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final isDark = brightness == Brightness.dark;

      testWidgets(
          '${isDark ? 'ダーク' : 'ライト'}: 確認ダイアログの「キャンセル」は textSecondary・「ログアウト」は error',
          (tester) async {
        await pumpView(
          tester,
          theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        final colors =
            isDark ? AppColorsExtension.dark : AppColorsExtension.light;

        await openLogoutDialog(tester);

        final cancel = tester.widget<Text>(
          find.descendant(
            of: dialogButton('キャンセル'),
            matching: find.text('キャンセル'),
          ),
        );
        expect(cancel.style?.color, colors.textSecondary);

        final confirm = tester.widget<Text>(
          find.descendant(
            of: dialogButton('ログアウト'),
            matching: find.text('ログアウト'),
          ),
        );
        expect(confirm.style?.color, colors.error);
        expect(confirm.style?.fontWeight, FontWeight.w500);
      });
    }

    testWidgets('確認ダイアログで「キャンセル」なら onSignOut は呼ばれず、ダイアログが閉じる', (tester) async {
      await pumpView(tester);
      await openLogoutDialog(tester);

      await tester.tap(dialogButton('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(signOutCount, 0);
      // サインアウトしないので、この画面のまま
      expect(find.text('ユーザー情報を読み込めませんでした'), findsOneWidget);
    });

    testWidgets('ダイアログの外をタップして閉じても onSignOut は呼ばれない', (tester) async {
      await pumpView(tester);
      await openLogoutDialog(tester);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(signOutCount, 0);
    });

    testWidgets('確認ダイアログで「ログアウト」なら、ダイアログを閉じてから onSignOut が 1 回呼ばれる',
        (tester) async {
      bool? dialogWasPopped;
      await pumpView(
        tester,
        onSignOut: () async {
          signOutCount++;
          // 呼ばれた時点で、確認ダイアログのルートはもう pop されている
          dialogWasPopped =
              !tester.state<NavigatorState>(find.byType(Navigator)).canPop();
        },
      );
      await openLogoutDialog(tester);

      await tester.tap(dialogButton('ログアウト'));
      await tester.pumpAndSettle();

      expect(signOutCount, 1);
      expect(dialogWasPopped, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    /// 確認ダイアログを開いている間に、再試行が成功して画面が差し替わった場面を作る。
    /// 同じ MaterialApp のまま画面だけを入れ替える（ダイアログは Navigator 上に残る）
    Future<void> replaceViewWhileDialogIsOpen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      expect(find.byType(ClientLoadErrorView), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    testWidgets(
        '確認ダイアログを開いている間に画面が外れても、「ログアウト」を選べば onSignOut が 1 回呼ばれる（確認済みの操作を捨てない）',
        (tester) async {
      await pumpView(tester);
      await openLogoutDialog(tester);
      await replaceViewWhileDialogIsOpen(tester);

      await tester.tap(dialogButton('ログアウト'));
      await tester.pumpAndSettle();

      // 外れたあとに実行してよいかは、呼び出し側が自分の状態で確かめる
      expect(signOutCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('画面が外れていても、確認ダイアログを「キャンセル」で閉じれば onSignOut は呼ばれない',
        (tester) async {
      await pumpView(tester);
      await openLogoutDialog(tester);
      await replaceViewWhileDialogIsOpen(tester);

      await tester.tap(dialogButton('キャンセル'));
      await tester.pumpAndSettle();

      expect(signOutCount, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('onSignOut の例外は握りつぶさず、そのまま伝わる（扱いは呼び出し側に任せる）', (tester) async {
      await pumpView(
        tester,
        onSignOut: () async {
          throw StateError('sign out failed');
        },
      );

      // 握られなければ、握る人のいない非同期エラーとしてゾーンに届く。
      // 「ログアウト」を押すところから同じゾーンで操作して、それを受け取る
      final uncaught = <Object>[];
      await runZonedGuarded(
        () async {
          await openLogoutDialog(tester);
          await tester.tap(dialogButton('ログアウト'));
          await tester.pumpAndSettle();
        },
        (error, stack) => uncaught.add(error),
      );

      expect(uncaught, hasLength(1));
      expect(uncaught.single, isA<StateError>());
      // 例外が出ても、ダイアログは閉じている
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
