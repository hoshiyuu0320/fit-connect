import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/widgets/onboarding_step_page.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/providers/onboarding_flow_provider.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// オンボーディング後段フロー（登録完了画面の「トレーニングを始める」から起動）
///
/// 2ステップ構成（各画面スキップ可・戻る強制なし・進捗ドット表示）:
/// 1. 通知権限プライミング（価値説明 → OS許可ダイアログ）
/// 2. ヘルスケア連携提案（この画面上でインライン連携。権限シートが直接出る）
///
/// フロー完了（最終ステップ or 全スキップ）時:
/// - clients.onboarding_completed_at を更新（失敗はログのみ）
/// - SharedPreferences に完了フラグを保存
/// - 登録状態をクリアしてホーム（MainScreen）へ
class OnboardingFlowScreen extends ConsumerStatefulWidget {
  const OnboardingFlowScreen({super.key});

  static const int stepCount = 2;

  @override
  ConsumerState<OnboardingFlowScreen> createState() =>
      _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isBusy = false;
  bool _isCompleting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 次のステップへ進む（最終ステップならフロー完了）
  Future<void> _goNext() async {
    if (_currentStep >= OnboardingFlowScreen.stepCount - 1) {
      await _completeFlow();
      return;
    }
    setState(() => _currentStep += 1);
    await _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// フロー完了処理
  Future<void> _completeFlow() async {
    if (_isCompleting) return;
    _isCompleting = true;

    // 完了記録（DB更新失敗はリポジトリ内でログのみ）
    await ref.read(onboardingRepositoryProvider).markFlowCompleted();

    if (!mounted) return;

    // 先に currentClientProvider を再評価し、client の取得完了を待ってから
    // 登録状態をクリアする。先に clear() すると、client 未取得の間
    // app.dart 側が「セッション有り・client なし・登録フロー外」と誤判定し、
    // 一瞬ウェルカム画面が表示されるレースコンディションが起きるため。
    ref.invalidate(currentClientProvider);
    try {
      await ref.read(currentClientProvider.future);
    } catch (_) {
      // 取得失敗でもフロー完了は続行（表示分岐は app.dart 側に委ねる）
    }

    if (!mounted) return;

    // 登録状態をクリアすることで app.dart 側が MainScreen を表示する
    ref.read(registrationNotifierProvider.notifier).clear();

    // push されたフロー画面を全て閉じてルート（ホーム）へ戻る
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// ステップ1: 通知を許可する
  Future<void> _handleAllowNotifications() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    NotificationSetupResult? result;
    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId != null) {
        result = await NotificationService.requestPermissionAndRegister(
          userId: userId,
          userType: 'client',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
    if (!mounted) return;
    // 結果をフィードバック（拒否されても進行は止めない。iOS は一度拒否されると
    // アプリからは再表示できず、設定アプリからの変更のみになるため案内する）
    switch (result) {
      case NotificationSetupResult.granted:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知をオンにしました')),
        );
      case NotificationSetupResult.denied:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('通知が許可されていません。iOS の設定アプリからいつでも変更できます'),
          ),
        );
      case NotificationSetupResult.registrationFailed:
        // 権限は取れているので次回起動時に自動で再登録される
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('通知の登録が完了しませんでした。次回起動時に自動で再試行します'),
          ),
        );
      case null:
        break;
    }
    await _goNext();
  }

  /// ステップ2（最終ステップ）: ヘルスケア連携をこの画面上でインライン実行する
  ///
  /// 体重+睡眠の読み取り権限を1回のリクエスト（=OS の権限シート1枚）でまとめて
  /// 要求する。シートを連続表示すると iOS が2枚目の present を拒否して
  /// health プラグインの Future が解決せずハングするため、必ず1回にまとめる。
  /// timeout はシートの表示自体に失敗して Future が解決しない場合の保険。
  ///
  /// なお iOS では1枚のシート内でユーザーが睡眠だけオフにしても
  /// requestAuthorization は true を返す（Apple が READ 権限の可否を秘匿するため）。
  /// その場合は睡眠同期がデータ0件になるだけで、既存の設定画面と同じ挙動なので許容。
  /// 完了後は _goNext 経由で _completeFlow が呼ばれフローが終了する
  Future<void> _handleConnectHealth() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    var granted = false;
    try {
      final notifier = ref.read(healthSettingsProvider.notifier);
      granted = await notifier.enableAllWithSinglePrompt().timeout(
            const Duration(seconds: 120),
            onTimeout: () => false,
          );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ヘルスケアと連携できませんでした。設定アプリからいつでも変更できます'),
        ),
      );
    }
    await _goNext();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 進捗ドット
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: OnboardingProgressDots(
                currentStep: _currentStep,
                stepCount: OnboardingFlowScreen.stepCount,
              ),
            ),

            // ステップ本体
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // ステップ1: 通知プライミング
                  OnboardingStepPage(
                    icon: LucideIcons.bell,
                    iconColor: AppColors.primary600,
                    iconBackgroundColor: AppColors.primary50,
                    title: '通知をオンにしましょう',
                    description: 'トレーナーからの返信やアドバイスを\nすぐ受け取れます。',
                    primaryLabel: '通知を許可する',
                    onPrimary: _handleAllowNotifications,
                    onLater: _isBusy ? null : _goNext,
                    isBusy: _isBusy,
                  ),

                  // ステップ2（最終）: ヘルスケア連携提案
                  OnboardingStepPage(
                    icon: LucideIcons.heartPulse,
                    iconColor: AppColors.emerald500,
                    iconBackgroundColor: AppColors.emerald50,
                    title: 'ヘルスケアと連携しましょう',
                    description: '体重や睡眠のデータを自動で取り込み、\n記録の手間を減らせます。',
                    primaryLabel: '連携する',
                    onPrimary: _handleConnectHealth,
                    onLater: _isBusy ? null : _goNext,
                    isBusy: _isBusy,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 進捗ドット（現在のステップをピル形状でハイライト）
class OnboardingProgressDots extends StatelessWidget {
  final int currentStep;
  final int stepCount;

  const OnboardingProgressDots({
    super.key,
    required this.currentStep,
    required this.stepCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(stepCount, (index) {
        final isActive = index == currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary600 : colors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'OnboardingFlow - Step1 通知プライミング')
Widget previewOnboardingFlowStep1() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: 24),
              child: OnboardingProgressDots(currentStep: 0, stepCount: 2),
            ),
            Expanded(
              child: OnboardingStepPage(
                icon: LucideIcons.bell,
                iconColor: AppColors.primary600,
                iconBackgroundColor: AppColors.primary50,
                title: '通知をオンにしましょう',
                description: 'トレーナーからの返信やアドバイスを\nすぐ受け取れます。',
                primaryLabel: '通知を許可する',
                onPrimary: null,
                onLater: null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'OnboardingFlow - Step2 ヘルスケア連携')
Widget previewOnboardingFlowStep2() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: 24),
              child: OnboardingProgressDots(currentStep: 1, stepCount: 2),
            ),
            Expanded(
              child: OnboardingStepPage(
                icon: LucideIcons.heartPulse,
                iconColor: AppColors.emerald500,
                iconBackgroundColor: AppColors.emerald50,
                title: 'ヘルスケアと連携しましょう',
                description: '体重や睡眠のデータを自動で取り込み、\n記録の手間を減らせます。',
                primaryLabel: '連携する',
                onPrimary: null,
                onLater: null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
