import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// オンボーディング後段フローの1ステップ分の共通レイアウト
///
/// アイコン・タイトル・説明文・メインボタン・「あとで」ボタンで構成される。
/// 各ステップは必ずスキップ（あとで）できること（強制ロック禁止）。
class OnboardingStepPage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String laterLabel;
  final VoidCallback? onLater;
  final bool isBusy;

  const OnboardingStepPage({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onLater,
    this.laterLabel = 'あとで',
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),

          // アイコン
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: iconBackgroundColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                icon,
                size: 48,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // タイトル
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // 説明文
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: colors.textSecondary,
              height: 1.7,
            ),
          ),

          const Spacer(),

          // メインボタン
          ElevatedButton(
            onPressed: isBusy ? null : onPrimary,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: isBusy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    primaryLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 8),

          // あとで（スキップ）ボタン
          TextButton(
            onPressed: isBusy ? null : onLater,
            style: TextButton.styleFrom(
              foregroundColor: colors.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              laterLabel,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
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

@Preview(name: 'OnboardingStepPage - Notification')
Widget previewOnboardingStepPageNotification() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SafeArea(
        child: OnboardingStepPage(
          icon: LucideIcons.bell,
          iconColor: AppColors.primary600,
          iconBackgroundColor: AppColors.primary50,
          title: '通知をオンにしましょう',
          description: 'トレーナーからの返信やアドバイスをすぐ受け取れます。',
          primaryLabel: '通知を許可する',
          onPrimary: null,
          onLater: null,
        ),
      ),
    ),
  );
}

@Preview(name: 'OnboardingStepPage - Busy')
Widget previewOnboardingStepPageBusy() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SafeArea(
        child: OnboardingStepPage(
          icon: LucideIcons.heartPulse,
          iconColor: AppColors.emerald500,
          iconBackgroundColor: AppColors.emerald50,
          title: 'ヘルスケアと連携しましょう',
          description: '体重や睡眠のデータを自動で取り込みます。',
          primaryLabel: '連携する',
          onPrimary: null,
          onLater: null,
          isBusy: true,
        ),
      ),
    ),
  );
}
