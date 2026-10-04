import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_button.dart';
import 'fc_card.dart';
import 'fc_pressable.dart';

/// 状態メッセージの種類
enum FcStateKind {
  /// データがまだ無い（アイコンなし）
  empty,

  /// 読み込み・保存に失敗した（alert アイコン + error 色）
  error,

  /// ネットワークに繋がっていない（wifi-off アイコン）
  offline,

  /// 完了した（check アイコン + success 色）
  success,
}

/// 空・エラー・オフライン・完了を伝える **左寄せのカード**。正本は `components/feedback/StateMessage.jsx`。
///
/// - surface の面・角丸 23・余白 20（中央寄せではない。カードの外側に余白を付けない）
/// - タイトル 16 / 500。アイコンは 18（`error` は error 色、`success` は success 色、`empty` はアイコンなし）。
///   色はアイコンだけに付き、文言も必ず併記する
/// - 本文（[message]）は 14 / textSecondary・タイトルの下 4
/// - 操作は [actionLabel] / [onAction]。`FcButton`（既定は pill・上 14、[actionVariant] を `text` にすると上 4）
/// - `error` / `success` は読み上げの live region。文字拡大では縦に伸びる（縮めない）
class FcStateMessage extends StatelessWidget {
  const FcStateMessage({
    super.key,
    required this.kind,
    required this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.actionVariant = FcButtonVariant.pill,
  });

  const FcStateMessage.empty({
    Key? key,
    required String title,
    String? message,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    IconData? actionIcon,
    FcButtonVariant actionVariant = FcButtonVariant.pill,
  }) : this(
          key: key,
          kind: FcStateKind.empty,
          title: title,
          message: message,
          icon: icon,
          actionLabel: actionLabel,
          onAction: onAction,
          actionIcon: actionIcon,
          actionVariant: actionVariant,
        );

  const FcStateMessage.error({
    Key? key,
    required String title,
    String? message,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    IconData? actionIcon,
    FcButtonVariant actionVariant = FcButtonVariant.pill,
  }) : this(
          key: key,
          kind: FcStateKind.error,
          title: title,
          message: message,
          icon: icon,
          actionLabel: actionLabel,
          onAction: onAction,
          actionIcon: actionIcon,
          actionVariant: actionVariant,
        );

  const FcStateMessage.offline({
    Key? key,
    required String title,
    String? message,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    IconData? actionIcon,
    FcButtonVariant actionVariant = FcButtonVariant.pill,
  }) : this(
          key: key,
          kind: FcStateKind.offline,
          title: title,
          message: message,
          icon: icon,
          actionLabel: actionLabel,
          onAction: onAction,
          actionIcon: actionIcon,
          actionVariant: actionVariant,
        );

  const FcStateMessage.success({
    Key? key,
    required String title,
    String? message,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    IconData? actionIcon,
    FcButtonVariant actionVariant = FcButtonVariant.pill,
  }) : this(
          key: key,
          kind: FcStateKind.success,
          title: title,
          message: message,
          icon: icon,
          actionLabel: actionLabel,
          onAction: onAction,
          actionIcon: actionIcon,
          actionVariant: actionVariant,
        );

  final FcStateKind kind;
  final String title;
  final String? message;

  /// null なら種類の既定（empty: なし / error: alertCircle / offline: wifiOff / success: checkCircle）
  final IconData? icon;

  final String? actionLabel;
  final VoidCallback? onAction;

  /// 操作ボタンのアイコン（既定は pill = 末尾 / text = 末尾）
  final IconData? actionIcon;

  /// 操作ボタンの種類。`pill`（既定）か `text`
  final FcButtonVariant actionVariant;

  static IconData? defaultIcon(FcStateKind kind) => switch (kind) {
        FcStateKind.empty => null,
        FcStateKind.error => LucideIcons.alertCircle,
        FcStateKind.offline => LucideIcons.wifiOff,
        FcStateKind.success => LucideIcons.checkCircle,
      };

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final iconData = icon ?? defaultIcon(kind);
    final iconColor = switch (kind) {
      FcStateKind.error => colors.error,
      FcStateKind.success => colors.success,
      FcStateKind.empty || FcStateKind.offline => colors.textSecondary,
    };
    final hasAction = actionLabel != null && onAction != null;
    final isTextAction = actionVariant == FcButtonVariant.text;

    return Semantics(
      container: true,
      liveRegion: kind == FcStateKind.error || kind == FcStateKind.success,
      child: FcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (iconData != null) ...[
                  ExcludeSemantics(
                    child: Icon(iconData, size: 18, color: iconColor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: AppTextStyles.body(context)
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  message!,
                  style: AppTextStyles.label(context)
                      .copyWith(color: colors.textSecondary, height: 1.5),
                ),
              ),
            if (hasAction)
              Padding(
                padding:
                    EdgeInsets.only(top: isTextAction ? AppSpacing.xs : 14),
                child: FcButton(
                  variant: actionVariant,
                  label: actionLabel!,
                  icon: actionIcon,
                  onPressed: onAction,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// インライン通知の種類
enum FcNoticeKind {
  /// 注意（warning 色 + alertCircle）
  warning,

  /// 失敗（error 色 + alertCircle）
  error,

  /// お知らせ。[neutral] の別名（中立の面・アイコンなし）。青緑を状態の意味に兼用しない
  info,

  /// 中立（surfaceSecondary の面 + textSecondary の文字・アイコンなし）
  neutral,

  /// 完了（success 色 + checkCircle）
  success,
}

/// 画面の中に差し込む通知帯（オフライン・同期失敗・入力の注意など）。
/// 正本は `components/feedback/InlineNotice.jsx`。
///
/// - 余白 10×12・角丸 12・文字 13（行高 1.5）。**文字もアイコンもトーンの色**（面は errorSurface など）
/// - アイコンは 16（文字の 1 行目に揃える）。neutral はアイコンなし
/// - アイコンと文言を併用し、色だけで伝えない。読み上げの live region
/// - [actionLabel] と [onAction] で「再試行」を付けられる（更新アイコン 14 + ラベル・タッチ領域 44 以上・太さ 500）
/// - 文字拡大では折り返して縦に伸びる
class FcInlineNotice extends StatelessWidget {
  const FcInlineNotice({
    super.key,
    required this.kind,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  const FcInlineNotice.warning({
    Key? key,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
          key: key,
          kind: FcNoticeKind.warning,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        );

  const FcInlineNotice.error({
    Key? key,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
          key: key,
          kind: FcNoticeKind.error,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        );

  /// [FcInlineNotice.neutral] の別名
  const FcInlineNotice.info({
    Key? key,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
          key: key,
          kind: FcNoticeKind.info,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        );

  const FcInlineNotice.neutral({
    Key? key,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
          key: key,
          kind: FcNoticeKind.neutral,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        );

  const FcInlineNotice.success({
    Key? key,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
          key: key,
          kind: FcNoticeKind.success,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        );

  final FcNoticeKind kind;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final Color background;
    final Color foreground;
    final IconData? icon;
    switch (kind) {
      case FcNoticeKind.warning:
        background = colors.warningSurface;
        foreground = colors.warning;
        icon = LucideIcons.alertCircle;
      case FcNoticeKind.error:
        background = colors.errorSurface;
        foreground = colors.error;
        icon = LucideIcons.alertCircle;
      case FcNoticeKind.success:
        background = colors.successSurface;
        foreground = colors.success;
        icon = LucideIcons.checkCircle;
      case FcNoticeKind.info:
      case FcNoticeKind.neutral:
        background = colors.surfaceSecondary;
        foreground = colors.textSecondary;
        icon = null;
    }

    final hasAction = actionLabel != null && onAction != null;
    final textStyle =
        AppTextStyles.supplement(context).copyWith(color: foreground);

    return Semantics(
      container: true,
      liveRegion: true,
      explicitChildNodes: hasAction,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Padding(
          // 操作ボタンは右へ 4 はみ出して（左右 4 の余白ぶん）、文字の右端を揃える
          padding: EdgeInsets.only(
              left: AppSpacing.md, right: hasAction ? 8 : AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ExcludeSemantics(
                    child: Icon(icon, size: 16, color: foreground),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(message, style: textStyle),
                ),
              ),
              if (hasAction) ...[
                const SizedBox(width: AppSpacing.sm),
                FcPressable(
                  onTap: onAction,
                  minSize: const Size.square(AppSizes.minTouch),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            LucideIcons.refreshCw,
                            size: 14,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          actionLabel!,
                          softWrap: false,
                          style:
                              textStyle.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
