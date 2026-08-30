import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/app_update/data/app_config_repository.dart';

/// 強制アップデートダイアログを表示する。
/// アップデートするまで閉じられない（バリア/戻る操作を抑止）。
Future<void> showForceUpdateDialog(
  BuildContext context, {
  required AppConfig config,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ForceUpdateDialog(config: config),
  );
}

/// アプリのアップデートを促す全画面ブロック型ダイアログ。
/// ストアURL（iOS: ios_store_url / Android: android_store_url）があれば
/// 「アップデート」ボタンを表示し、無ければ案内文言のみ表示する。
class ForceUpdateDialog extends StatelessWidget {
  const ForceUpdateDialog({super.key, required this.config});

  final AppConfig config;

  /// 実行中プラットフォームに対応するストアURL（未設定なら null）
  String? get _storeUrl => defaultTargetPlatform == TargetPlatform.android
      ? config.androidStoreUrl
      : config.iosStoreUrl;

  Future<void> _openStore(BuildContext context) async {
    final url = _storeUrl;
    if (url == null) return;

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ストアを開けませんでした'),
          backgroundColor: AppColors.rose800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final storeUrl = _storeUrl;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(
              LucideIcons.arrowUpCircle,
              size: 22,
              color: AppColors.primary600,
            ),
            SizedBox(width: 8),
            Text('アップデートのお願い'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // update_message があればそれを優先表示
              config.updateMessage ??
                  '新しいバージョンのアプリが公開されています。\n'
                      'お手数ですが、最新バージョンへアップデートのうえご利用ください。',
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: colors.textPrimary,
              ),
            ),
            if (config.latestVersion != null) ...[
              const SizedBox(height: 12),
              Text(
                '最新バージョン: ${config.latestVersion}',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
            ],
            if (storeUrl != null) ...[
              const SizedBox(height: 16),

              // ストアへの誘導ボタン（アプリはこの画面のまま維持される）
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _openStore(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'アップデート',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'ForceUpdateDialog - ストアURLあり')
Widget previewForceUpdateDialogWithStoreUrl() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ForceUpdateDialog(
          config: AppConfig(
            minSupportedVersion: '1.1.0',
            latestVersion: '1.2.0',
            iosStoreUrl: 'https://apps.apple.com/jp/app/id0000000000',
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'ForceUpdateDialog - ストアURLなし（文言のみ）')
Widget previewForceUpdateDialogWithoutStoreUrl() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ForceUpdateDialog(
          config: AppConfig(
            minSupportedVersion: '1.1.0',
            updateMessage: '重要な不具合修正を含むため、最新バージョンへの更新が必要です。',
          ),
        ),
      ),
    ),
  );
}
