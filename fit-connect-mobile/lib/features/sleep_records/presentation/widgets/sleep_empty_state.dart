import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 睡眠の記録がまだ1件も無いときの案内。
///
/// 正本 `StateMessage`（empty）と同じ見た目（左寄せの surface カード・タイトル 16 / 500・
/// 本文 14 / textSecondary）で、「まだ記録がありません」と **記録する入口**
/// （ヘルスケア連携 / 目覚めを記録）を出す。
///
/// 基盤の `FcStateMessage` は操作を 1 つしか持てないため、入口を 2 つ置くこの画面だけ
/// feature 内に同じ見た目で作った（基盤へ昇格してほしい: 複数操作の `FcStateMessage`）。
class SleepEmptyState extends StatelessWidget {
  /// 「ヘルスケア連携を確認」（連携の設定へ）
  final VoidCallback onOpenHealthSettings;

  /// 「目覚めを記録」（手動で記録するシートへ）
  final VoidCallback onRecordWakeup;

  const SleepEmptyState({
    super.key,
    required this.onOpenHealthSettings,
    required this.onRecordWakeup,
  });

  @override
  Widget build(BuildContext context) {
    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'まだ記録がありません',
              style: AppTextStyles.body(context)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'ヘルスケア連携を有効にするか、目覚めを記録してみましょう。',
            // 正本 StateMessage の本文は 14（ラベルサイズ）・textSecondary・行高 1.5
            style: AppTextStyles.label(context).copyWith(
              color: AppColors.of(context).textSecondary,
              height: 1.5,
            ),
          ),
          // 正本 StateMessage: 操作は本文の下 14
          const SizedBox(height: 14),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FcButton.pill(
                label: 'ヘルスケア連携を確認',
                onPressed: onOpenHealthSettings,
              ),
              FcButton.pill(
                label: '目覚めを記録',
                quiet: true,
                onPressed: onRecordWakeup,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================
// プレビュー
// =====================================

Widget _previewEmpty({required Brightness brightness, double scale = 1}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SleepEmptyState(
            onOpenHealthSettings: () {},
            onRecordWakeup: () {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepEmptyState - ライト')
Widget previewSleepEmptyStateLight() =>
    _previewEmpty(brightness: Brightness.light);

@Preview(name: 'SleepEmptyState - ダーク')
Widget previewSleepEmptyStateDark() =>
    _previewEmpty(brightness: Brightness.dark);

@Preview(name: 'SleepEmptyState - 文字拡大 1.35')
Widget previewSleepEmptyStateLarge() =>
    _previewEmpty(brightness: Brightness.light, scale: 1.35);
