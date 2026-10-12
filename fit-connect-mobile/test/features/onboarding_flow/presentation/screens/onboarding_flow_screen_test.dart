import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/health/data/health_repository.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/data/onboarding_repository.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/screens/onboarding_flow_screen.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/widgets/onboarding_step_page.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/providers/onboarding_flow_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// 権限リクエストが常に拒否される（タイムアウト時の false 返却も同等）リポジトリ
class _DeniedHealthRepository extends HealthRepository {
  @override
  Future<bool> requestPermission({bool includeSleep = false}) async => false;
}

/// markFlowCompleted の呼び出しを記録するだけのリポジトリ（Supabase 非接続）
class _RecordingOnboardingRepository extends OnboardingRepository {
  bool markFlowCompletedCalled = false;

  @override
  Future<void> markFlowCompleted() async {
    markFlowCompletedCalled = true;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildScreen() {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const OnboardingFlowScreen(),
      ),
    );
  }

  group('OnboardingFlowScreen', () {
    testWidgets('ステップ1（通知プライミング）が進捗ドット付きで表示される', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // ステップ1の内容
      expect(find.text('通知をオンにしましょう'), findsOneWidget);
      expect(find.textContaining('トレーナーからの返信やアドバイス'), findsOneWidget);
      expect(find.text('通知を許可する'), findsOneWidget);
      expect(find.text('あとで'), findsOneWidget);

      // 進捗ドット
      expect(find.byType(OnboardingProgressDots), findsOneWidget);
    });

    testWidgets('「あとで」でステップ2（ヘルスケア・最終ステップ）へ進める', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // ステップ1 → ステップ2（最終）
      await tester.tap(find.text('あとで'));
      await tester.pumpAndSettle();
      expect(find.text('ヘルスケアと連携しましょう'), findsOneWidget);
      expect(find.text('連携する'), findsOneWidget);

      // 最終ステップでもスキップ導線がある（タップはしない: フロー完了は
      // Supabase 接続を伴うためウィジェットテストでは検証しない）
      expect(find.text('あとで'), findsOneWidget);
    });

    testWidgets('ヘルスケア権限が拒否（タイムアウト相当の false）でもフローが完了して次へ進む', (tester) async {
      final onboardingRepo = _RecordingOnboardingRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            healthRepositoryProvider.overrideWithValue(
              _DeniedHealthRepository(),
            ),
            onboardingRepositoryProvider.overrideWithValue(onboardingRepo),
            currentClientProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const OnboardingFlowScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ステップ2（ヘルスケア・最終ステップ）へ
      await tester.tap(find.text('あとで'));
      await tester.pumpAndSettle();
      expect(find.text('連携する'), findsOneWidget);

      // 連携する → enableAllWithSinglePrompt が false → 案内 SnackBar → フロー完了
      await tester.tap(find.text('連携する'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ヘルスケアと連携できませんでした'),
        findsOneWidget,
      );
      expect(onboardingRepo.markFlowCompletedCalled, isTrue);

      // SnackBar の表示タイマーを消化してテストを終了させる
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('OnboardingStepPage', () {
    Widget buildStep({
      required VoidCallback onPrimary,
      VoidCallback? onLater,
      bool isBusy = false,
      ThemeData? theme,
      double textScale = 1.0,
    }) {
      return MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: OnboardingStepPage(
            icon: LucideIcons.bell,
            title: 'タイトル',
            description: '説明',
            primaryLabel: '許可する',
            onPrimary: onPrimary,
            onLater: onLater,
            isBusy: isBusy,
          ),
        ),
      );
    }

    testWidgets('isBusy 中は「処理しています…」に変わり、押せない（薄い無効表示にしない）', (tester) async {
      var primaryTapped = false;
      await tester.pumpWidget(
        buildStep(
          onPrimary: () => primaryTapped = true,
          onLater: () {},
          isBusy: true,
        ),
      );
      await tester.pump();

      // 文言で処理中が分かる。通常の文言は出ない
      expect(find.text('処理しています…'), findsOneWidget);
      expect(find.text('許可する'), findsNothing);

      // 押せない
      await tester.tap(find.text('処理しています…'), warnIfMissed: false);
      await tester.pump();
      expect(primaryTapped, isFalse);

      // 薄くしない（無効の opacity 0.4 を掛けない）
      expect(
        find.descendant(
          of: find.byType(FcButton),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('通常時は主要ボタンを押せる', (tester) async {
      var primaryTapped = false;
      await tester.pumpWidget(
        buildStep(onPrimary: () => primaryTapped = true, onLater: () {}),
      );
      await tester.tap(find.text('許可する'));
      await tester.pump();
      expect(primaryTapped, isTrue);
    });

    testWidgets('アイコンは accent、面は surface（ライト/ダークとも）', (tester) async {
      for (final (theme, tokens) in <(ThemeData, AppColorsExtension)>[
        (AppTheme.lightTheme, AppColorsExtension.light),
        (AppTheme.darkTheme, AppColorsExtension.dark),
      ]) {
        await tester.pumpWidget(
          buildStep(onPrimary: () {}, onLater: () {}, theme: theme),
        );
        await tester.pumpAndSettle();

        final icon = tester.widget<Icon>(find.byIcon(LucideIcons.bell));
        expect(icon.color, tokens.accent);
        final tile = tester.widget<Container>(
          find.ancestor(
            of: find.byIcon(LucideIcons.bell),
            matching: find.byType(Container),
          ),
        );
        expect((tile.decoration as BoxDecoration).color, tokens.surface);
      }
    });

    testWidgets('文字拡大 1.35 でも overflow せず、主要ボタンは 44 以上', (tester) async {
      await tester.pumpWidget(
        buildStep(onPrimary: () {}, onLater: () {}, textScale: 1.35),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FcButton)).height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('OnboardingProgressDots', () {
    testWidgets('現在のステップは accent、それ以外は textSecondary（ライト/ダークとも背景で読める）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: OnboardingProgressDots(currentStep: 1, stepCount: 2),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final colors = AppColorsExtension.dark;
      final dots = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(dots, [colors.textSecondary, colors.accent]);
      expect(
        find.bySemanticsLabel('ステップ 2 / 2'),
        findsOneWidget,
      );
    });
  });
}
