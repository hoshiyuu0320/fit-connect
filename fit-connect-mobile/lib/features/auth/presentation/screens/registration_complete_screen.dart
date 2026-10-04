import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/screens/onboarding_flow_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// 登録完了画面
///
/// 演出（紙吹雪・グラデーション・光る影）は使わず、ページ背景の上に
/// チェックのアイコン・見出し・説明のカード・主要ボタンを静かに並べる。
/// 「トレーニングを始める」でオンボーディング後段フロー（通知・ヘルスケア）へ進む。
class RegistrationCompleteScreen extends ConsumerWidget {
  const RegistrationCompleteScreen({super.key});

  void _startOnboardingFlow(BuildContext context) {
    // オンボーディング後段フロー（通知プライミング・ヘルスケア提案）へ進む。
    // 登録状態のクリアと currentClientProvider の無効化はフロー完了時に
    // OnboardingFlowScreen 側で行う（完了後に app.dart が MainScreen を表示）。
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const OnboardingFlowScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registrationState = ref.watch(registrationNotifierProvider);

    return _RegistrationCompleteView(
      trainerName: registrationState.trainerName,
      onStart: () => _startOnboardingFlow(context),
    );
  }
}

/// 登録完了画面の見た目（プロバイダーに依存しない。プレビューでも使う）
class _RegistrationCompleteView extends StatelessWidget {
  const _RegistrationCompleteView({
    required this.trainerName,
    required this.onStart,
  });

  final String? trainerName;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final name = trainerName;
    final hasTrainer = name != null;
    final horizontal = AppSpacing.pageHorizontalOf(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 文字拡大・小さい画面ではスクロールで収める（縮めない）
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      AppSpacing.xl,
                      horizontal,
                      AppSpacing.lg,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight -
                            AppSpacing.xl -
                            AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // チェックのアイコン（accent）。面は surface（青緑で塗らない）
                          Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: colors.surface,
                                shape: BoxShape.circle,
                              ),
                              child: ExcludeSemantics(
                                child: Icon(
                                  LucideIcons.check,
                                  size: 40,
                                  color: colors.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),

                          // 見出し
                          if (hasTrainer) ...[
                            Text(
                              '登録完了！',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.eyebrow(context),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                          Semantics(
                            header: true,
                            child: Text(
                              // 改行位置は従来の文言どおり（「…トレーナーと／つながりました！」）
                              hasTrainer ? '$nameトレーナーと\nつながりました！' : '登録完了！',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.planName(context),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),

                          // 要点（説明）
                          FcCard(
                            child: Text(
                              'トレーニングを始める準備ができました。\n一緒に目標を達成しましょう！',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body(context)
                                  .copyWith(height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // スタートボタン（下部）
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                0,
                horizontal,
                AppSpacing.xxl,
              ),
              child: FcButton.block(
                label: 'トレーニングを始める',
                icon: LucideIcons.arrowRight,
                onPressed: onStart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'RegistrationComplete - Light')
Widget previewRegistrationCompleteLight() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _RegistrationCompleteView(trainerName: '田中', onStart: () {}),
  );
}

@Preview(name: 'RegistrationComplete - Dark')
Widget previewRegistrationCompleteDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: _RegistrationCompleteView(trainerName: '田中', onStart: () {}),
  );
}

/// トレーナー名が取れていない場合は「登録完了！」を見出しにする
@Preview(name: 'RegistrationComplete - No Trainer Name')
Widget previewRegistrationCompleteNoTrainerName() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _RegistrationCompleteView(trainerName: null, onStart: () {}),
  );
}

/// 文字拡大 1.35: 見出し・カードが折り返して縦に伸び、横にはみ出さない
@Preview(name: 'RegistrationComplete - Large Text')
Widget previewRegistrationCompleteLargeText() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.35),
      ),
      child: child!,
    ),
    home: _RegistrationCompleteView(trainerName: '田中', onStart: () {}),
  );
}
