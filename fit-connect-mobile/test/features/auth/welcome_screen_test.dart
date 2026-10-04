import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/welcome_screen.dart';

/// 未ログインの入口（ウェルカム）。ダークの面・文字拡大での折り返し・タップ領域を確かめる。
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // LoginScreen が Supabase.instance を触るだけ（通信しない）
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  Future<void> pumpWelcome(
    WidgetTester tester, {
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const WelcomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('WelcomeScreen', () {
    testWidgets('文言と主要な導線が表示される', (tester) async {
      await pumpWelcome(tester);

      expect(find.text('FIT-CONNECT'), findsOneWidget);
      expect(find.text('トレーナーとつながって目標を達成しよう'), findsOneWidget);
      expect(find.text('メッセージで記録'), findsOneWidget);
      expect(find.text('目標を管理'), findsOneWidget);
      expect(find.text('進捗を可視化'), findsOneWidget);
      expect(find.text('新規登録'), findsOneWidget);
      expect(find.text('すでにアカウントをお持ちの方'), findsOneWidget);
      expect(find.text('ログインはこちら'), findsOneWidget);
    });

    testWidgets('「新規登録」でアカウント登録画面へ、「ログインはこちら」でログイン画面へ進む', (tester) async {
      await pumpWelcome(tester);

      await tester.tap(find.text('新規登録'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(OnboardingScreen))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('ログインはこちら'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('ダーク: ロゴ・特徴アイコンの面が淡いミントで浮かず、アイコンは accent', (tester) async {
      await pumpWelcome(tester, theme: AppTheme.darkTheme);
      final dark = AppColorsExtension.dark;

      // ロゴ（100x100）の面は surface、アイコンは accent
      final logoTile = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(LucideIcons.activity),
          matching: find.byType(Container),
        ),
      );
      expect((logoTile.decoration as BoxDecoration).color, dark.surface);
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.activity)).color,
        dark.accent,
      );

      // 特徴アイコンの面は surfaceSecondary、アイコンは accent
      for (final icon in [
        LucideIcons.messageSquare,
        LucideIcons.target,
        LucideIcons.barChart3,
      ]) {
        final tile = tester.widget<Container>(
          find.ancestor(
            of: find.byIcon(icon),
            matching: find.byType(Container),
          ),
        );
        expect(
          (tile.decoration as BoxDecoration).color,
          dark.surfaceSecondary,
        );
        expect(tester.widget<Icon>(find.byIcon(icon)).color, dark.accent);
      }

      // 旧トークンの淡いミント面が残っていない
      final decorated = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color);
      expect(decorated, isNot(contains(AppColors.primary50)));
      expect(decorated, isNot(contains(AppColors.primary100)));
    });

    testWidgets('文字拡大 1.35: ログイン導線が折り返して画面幅に収まる（はみ出さない）', (tester) async {
      await pumpWelcome(tester, textScale: 1.35);

      expect(tester.takeException(), isNull);

      for (final label in ['すでにアカウントをお持ちの方', 'ログインはこちら']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(390), reason: label);
      }
    });

    testWidgets('「ログインはこちら」と「新規登録」のタップ領域は高さ 44 以上', (tester) async {
      await pumpWelcome(tester);

      for (final finder in [
        find.ancestor(
          of: find.text('ログインはこちら'),
          matching: find.byType(GestureDetector),
        ),
        find.ancestor(
          of: find.text('新規登録'),
          matching: find.byType(ElevatedButton),
        ),
      ]) {
        expect(
          tester.getSize(finder.first).height,
          greaterThanOrEqualTo(44),
        );
      }
    });
  });
}
