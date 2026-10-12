import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// オンボーディング後段フローの1ステップ分の共通レイアウト
///
/// アイコン・タイトル・説明文・メインボタン・「あとで」ボタンで構成される。
/// 各ステップは必ずスキップ（あとで）できること（強制ロック禁止）。
///
/// アイコンの色・面は既定でテーマ追従のトークン（accent・surface）。ステップごとに
/// 色を変えない（ライト/ダークとも同じ見た目になる）。
class OnboardingStepPage extends StatelessWidget {
  final IconData icon;

  /// アイコンの色。null なら accent
  final Color? iconColor;

  /// アイコンの面の色。null なら surface
  final Color? iconBackgroundColor;
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
    this.iconColor,
    this.iconBackgroundColor,
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
                color: iconBackgroundColor ?? colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Icon(
                icon,
                size: 48,
                color: iconColor ?? colors.accent,
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
          // 処理中は文言が「処理しています…」に変わる（薄い無効表示にしない）。
          // 「あとで」は処理中に押せない（下の onLater）
          FcButton.block(
            label: primaryLabel,
            loading: isBusy,
            onPressed: onPrimary,
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

@Preview(name: 'OnboardingStepPage - Dark')
Widget previewOnboardingStepPageDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: const Scaffold(
      body: SafeArea(
        child: OnboardingStepPage(
          icon: LucideIcons.heartPulse,
          title: 'ヘルスケアと連携しましょう',
          description: '体重や睡眠のデータを自動で取り込みます。',
          primaryLabel: '連携する',
          onPrimary: null,
          onLater: null,
        ),
      ),
    ),
  );
}
