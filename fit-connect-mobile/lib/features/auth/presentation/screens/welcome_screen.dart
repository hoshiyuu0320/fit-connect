import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),

                      // Logo
                      Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                          child: Icon(
                            LucideIcons.activity,
                            size: 50,
                            color: colors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Title
                      Text(
                        'FIT-CONNECT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Subtitle
                      Text(
                        'トレーナーとつながって目標を達成しよう',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: colors.textSecondary,
                          height: 1.6,
                        ),
                      ),

                      const SizedBox(height: 64),

                      // Features
                      _buildFeatureItem(
                        context: context,
                        icon: LucideIcons.messageSquare,
                        title: 'メッセージで記録',
                        description: '体重・食事・運動をかんたんに報告',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        context: context,
                        icon: LucideIcons.target,
                        title: '目標を管理',
                        description: 'トレーナーと一緒に目標達成を目指す',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        context: context,
                        icon: LucideIcons.barChart3,
                        title: '進捗を可視化',
                        description: 'グラフとカレンダーで成果を確認',
                      ),

                      const SizedBox(height: 48),

                      // Sign Up Button
                      // 色・形（actionFill・角丸 24・最小高さ 48）はテーマの ElevatedButton。
                      // IntrinsicHeight の中では FcButton.block（LayoutBuilder を使う）を置けない
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const OnboardingScreen(),
                            ),
                          );
                        },
                        child: const Text('新規登録'),
                      ),

                      const SizedBox(height: 16),

                      // Login Link
                      // 文字拡大では折り返して縦に積む（Row だと横にはみ出す）
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        children: [
                          Text(
                            'すでにアカウントをお持ちの方',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.label(context).copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          FcButton.text(
                            label: 'ログインはこちら',
                            expand: false,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(
                                    isRegistration: false,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      const Spacer(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final colors = AppColors.of(context);
    return FcCard(
      paddingOverride: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Icon(
              icon,
              color: colors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.label(context)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppTextStyles.caption(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'WelcomeScreen - Default')
Widget previewWelcomeScreenDefault() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const WelcomeScreen(),
  );
}

@Preview(name: 'WelcomeScreen - Dark')
Widget previewWelcomeScreenDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: const WelcomeScreen(),
  );
}

/// 文字拡大 1.35: ログイン導線が折り返して積み直され、横にはみ出さない
@Preview(name: 'WelcomeScreen - Large Text')
Widget previewWelcomeScreenLargeText() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.35),
      ),
      child: child!,
    ),
    home: const WelcomeScreen(),
  );
}
