import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/consent/data/consent_repository.dart';
import 'package:fit_connect_mobile/features/consent/legal_links.dart';

/// 同意ダイアログを表示する。
/// 同意が記録されるまで閉じられない（バリア/戻る操作を抑止）。
Future<void> showConsentDialog(
  BuildContext context, {
  required String userId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ConsentDialog(userId: userId),
  );
}

/// 利用規約・プライバシーポリシー・AI解析への同意を求めるダイアログ
class ConsentDialog extends ConsumerStatefulWidget {
  const ConsentDialog({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends ConsumerState<ConsentDialog> {
  bool _agreed = false;
  bool _saving = false;

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('リンクを開けませんでした'),
          backgroundColor: AppColors.rose800,
        ),
      );
    }
  }

  Future<void> _onAgreePressed() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(consentRepositoryProvider)
          .recordConsent(widget.userId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // 失敗時はダイアログを閉じず、再試行できるようにする
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('同意の記録に失敗しました。通信環境をご確認のうえ、もう一度お試しください。'),
            backgroundColor: AppColors.rose800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('ご利用にあたって'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FIT-CONNECTのご利用には、利用規約とプライバシーポリシーへの同意が必要です。以下のリンクから内容をご確認ください。',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // 法務ドキュメントへのリンク
              _LegalLinkRow(
                icon: LucideIcons.fileText,
                label: '利用規約',
                onTap: _saving ? null : () => _openUrl(LegalLinks.termsUrl),
              ),
              _LegalLinkRow(
                icon: LucideIcons.shieldCheck,
                label: 'プライバシーポリシー',
                onTap: _saving ? null : () => _openUrl(LegalLinks.privacyUrl),
              ),
              const SizedBox(height: 12),

              // AI解析の明示説明ブロック
              const ConsentAiNoticeBox(),
              const SizedBox(height: 4),

              // 同意チェックボックス
              CheckboxListTile(
                value: _agreed,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _agreed = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '上記に同意します',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 同意ボタン（チェックするまで無効）
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_agreed && !_saving) ? _onAgreePressed : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          '同意してはじめる',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 法務ドキュメントへのリンク行
class _LegalLinkRow extends StatelessWidget {
  const _LegalLinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary500),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary600,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.primary600,
                ),
              ),
            ),
            const Icon(
              LucideIcons.externalLink,
              size: 14,
              color: AppColors.primary500,
            ),
          ],
        ),
      ),
    );
  }
}

/// AI解析についての明示説明ブロック（枠で強調）
/// プレビューでも使用するため公開Widgetにしている
class ConsentAiNoticeBox extends StatelessWidget {
  const ConsentAiNoticeBox({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                LucideIcons.sparkles,
                size: 16,
                color: AppColors.primary600,
              ),
              SizedBox(width: 6),
              Text(
                'AI解析について',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '記録された食事の写真・体重などの健康データは、AI解析（栄養素の推定など）のために'
            '外部のAIサービス（Anthropic）へ送信されます。詳細はプライバシーポリシーをご覧ください。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: colors.textPrimary,
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

@Preview(name: 'ConsentDialog - 初期状態（未チェック）')
Widget previewConsentDialogInitial() {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: ConsentDialog(userId: 'preview-user'),
        ),
      ),
    ),
  );
}

@Preview(name: 'ConsentAiNoticeBox - 単体')
Widget previewConsentAiNoticeBox() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: ConsentAiNoticeBox()),
      ),
    ),
  );
}
