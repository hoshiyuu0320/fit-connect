import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// HealthKit/Health Connect 権限拒否時のダイアログ。
///
/// surface の面・角丸 23・余白 20 の左寄せのカード（正本 `StateMessage` と同じ並び）。
/// タイトル（16 / 500）の前に注意のアイコン（warning 色）、本文は 14 / textSecondary。
/// 操作は「あとで」（控えめな面）と「設定を開く」（主要）。文言は従来のまま。
class PermissionDeniedDialog extends StatelessWidget {
  const PermissionDeniedDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // 面の色・角丸 23 は DialogTheme（surface・card の形）に任せる
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontalOf(context),
        vertical: AppSpacing.xxl,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // 1 行目の中央に揃える（行高 1.5 × 16 = 24 の中の 18）
                  padding: const EdgeInsets.only(top: 3),
                  child: ExcludeSemantics(
                    child: Icon(
                      LucideIcons.lock,
                      size: 18,
                      color: colors.warning,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'ヘルスケアへのアクセスが許可されていません',
                      style: AppTextStyles.body(context)
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _platformMessage(),
              style: AppTextStyles.label(context)
                  .copyWith(color: colors.textSecondary, height: 1.5),
            ),
            // 正本 StateMessage: 操作は本文の下 14
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FcButton.pill(
                    label: 'あとで',
                    quiet: true,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FcButton.pill(
                    label: '設定を開く',
                    expand: true,
                    onPressed: _openSettings,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _platformMessage() {
    if (kIsWeb) {
      return 'お使いの端末のヘルスケア設定からアクセスを許可してください。';
    }
    if (Platform.isIOS) {
      return '設定アプリの「ヘルスケア」→「データアクセスとデバイス」から FIT-CONNECT に睡眠データの読み取りを許可してください。';
    }
    return 'Health Connect アプリから FIT-CONNECT に睡眠データの読み取りを許可してください。';
  }

  Future<void> _openSettings() async {
    try {
      await AppSettings.openAppSettings();
    } catch (_) {
      // fallback: 何もしない（設定アプリが開けない端末は稀）
    }
  }
}

/// PermissionDeniedDialog を表示するヘルパー
Future<void> showPermissionDeniedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    // 背景の暗幕。ぼかしは下部ナビだけに使うので、薄い黒の面だけにする
    // （正本のシートの暗幕 rgba(0,0,0,.32) に合わせた）
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => const PermissionDeniedDialog(),
  );
}

// =====================================
// プレビュー
// =====================================

Widget _previewDialog({required Brightness brightness, double scale = 1}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: const Scaffold(body: PermissionDeniedDialog()),
  );
}

@Preview(name: 'PermissionDeniedDialog - ライト')
Widget previewPermissionDeniedDialog() =>
    _previewDialog(brightness: Brightness.light);

@Preview(name: 'PermissionDeniedDialog - ダーク')
Widget previewPermissionDeniedDialogDark() =>
    _previewDialog(brightness: Brightness.dark);

@Preview(name: 'PermissionDeniedDialog - 文字拡大 1.35')
Widget previewPermissionDeniedDialogLarge() =>
    _previewDialog(brightness: Brightness.light, scale: 1.35);
