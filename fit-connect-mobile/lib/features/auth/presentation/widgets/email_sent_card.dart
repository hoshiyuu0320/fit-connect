import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// ログイン画面のマジックリンク送信後カード。
///
/// 背景はテーマ追従の successTint（ダークでは濃緑）なので、テーマ追従の文字色がそのまま両モードで読める。
/// 枠線は固定の emerald100 ではなく半透明の success オーバーレイにして、どちらの背景にも馴染ませる。
class EmailSentCard extends StatelessWidget {
  final String email;

  const EmailSentCard({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.successTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(
            LucideIcons.mailCheck,
            size: 48,
            color: AppColors.success,
          ),
          const SizedBox(height: 16),
          Text(
            'メールを確認してください',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '認証リンクを送信しました:\n$email',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'メール内のリンクをタップして\n認証を完了してください',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
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

@Preview(name: 'EmailSentCard - Light')
Widget previewEmailSentCardLight() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: EmailSentCard(email: 'user@example.com')),
        ),
      ),
    ),
  );
}

/// ダークモード: 淡緑カードが濃緑に切り替わり、見出し・本文が読めることを確認する
@Preview(name: 'EmailSentCard - Dark')
Widget previewEmailSentCardDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: EmailSentCard(email: 'user@example.com')),
        ),
      ),
    ),
  );
}
