import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/health/data/health_repository.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/data/onboarding_repository.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/screens/onboarding_flow_screen.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/widgets/onboarding_step_page.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/providers/onboarding_flow_provider.dart';
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

    testWidgets('「あとで」でステップ2（ヘルスケア・最終ステップ）へ進める',
        (tester) async {
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

    testWidgets('ヘルスケア権限が拒否（タイムアウト相当の false）でもフローが完了して次へ進む',
        (tester) async {
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
    testWidgets('isBusy 中はボタンが無効化されインジケータが表示される', (tester) async {
      var primaryTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: OnboardingStepPage(
              icon: LucideIcons.bell,
              iconColor: Colors.blue,
              iconBackgroundColor: Colors.blue.shade50,
              title: 'タイトル',
              description: '説明',
              primaryLabel: '許可する',
              onPrimary: () => primaryTapped = true,
              onLater: () {},
              isBusy: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();
      expect(primaryTapped, isFalse);
    });
  });
}
