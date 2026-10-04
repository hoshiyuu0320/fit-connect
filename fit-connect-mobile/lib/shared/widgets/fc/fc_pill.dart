import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';

/// ピルの強さ
enum FcPillTone {
  /// 通常（surfaceSecondary の面 + textPrimary）
  neutral,

  /// 控えめ（surfaceSecondary の面 + textSecondary）
  muted,

  /// 強調（actionFill の面 + onAction）
  strong,
}

/// 小さな状態・属性のラベル（「今日」「完了」「推定」など）。操作はできない。
///
/// 色は強さ（[tone]）だけで変える。カテゴリごとに色を割り振らない。
/// 文字拡大では高さが伸びて折り返す。
class FcPill extends StatelessWidget {
  const FcPill(
    this.label, {
    super.key,
    this.tone = FcPillTone.neutral,
    this.icon,
  });

  final String label;
  final FcPillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final Color background;
    final Color foreground;
    switch (tone) {
      case FcPillTone.neutral:
        background = colors.surfaceSecondary;
        foreground = colors.textPrimary;
      case FcPillTone.muted:
        background = colors.surfaceSecondary;
        foreground = colors.textSecondary;
      case FcPillTone.strong:
        background = colors.actionFill;
        foreground = colors.onAction;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.circle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              ExcludeSemantics(child: Icon(icon, size: 12, color: foreground)),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.caption(context).copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
