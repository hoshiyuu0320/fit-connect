import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_pressable.dart';

/// ボタンの種類
enum FcButtonVariant {
  /// 主要ボタン。最小高さ 48・余白 12・角丸 24・actionFill・16/500。横幅いっぱい・中央寄せ
  block,

  /// ピルボタン。最小高さ 43・余白 11×17・角丸 24・actionFill・15/500。内容幅
  pill,

  /// 文字だけの操作（accent・15/500）。最小高さ 47・余白 11×0。横幅いっぱいで両端寄せ
  text,

  /// 「戻る」「日付を変更」のような accent の文字操作（15/400）。最小高さ 44・余白 0。
  /// アイコンの既定は左矢印を先頭に置く
  back,
}

/// アイコンを文字の前に置くか後ろに置くか
enum FcIconPosition { start, end }

/// 共通ボタン。正本は `components/core/Button.jsx`。
///
/// - [onPressed] が null なら無効表示（opacity 0.4・押せない）
/// - [loading] が true の間は文言を [loadingLabel]（既定「処理しています…」）に置き換えて押せなくする
///   （無効のような薄い表示にはしない）
/// - アイコンの位置の既定は、`back` だけ先頭、それ以外は末尾（正本と同じ）
/// - すべてタッチ領域 44 以上。押下で scale 0.98（動きを減らす設定では無効）
/// - 文字は折り返せる。文字拡大でも高さが伸びるだけで切れない
/// - アイコンだけで使わない。アイコンだけにしたいときは [semanticLabel] を必ず渡す
/// - 横幅いっぱいにする種類（block / text）も、横幅が無制限の場所（`Row` の中など）では
///   内容幅になる（エラーにならない）。`Row` で並べたいときは `Expanded` で包むか `expand: false`
class FcButton extends StatelessWidget {
  const FcButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = FcButtonVariant.block,
    this.icon,
    this.iconPosition,
    this.quiet = false,
    this.expand,
    this.loading = false,
    this.loadingLabel = '処理しています…',
    this.semanticLabel,
  });

  /// 主要ボタン（最小高さ 48・角丸 24・actionFill・横幅いっぱい）
  const FcButton.block({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconPosition,
    this.loading = false,
    this.loadingLabel = '処理しています…',
    this.semanticLabel,
  })  : variant = FcButtonVariant.block,
        quiet = false,
        expand = true;

  /// ピルボタン（最小高さ 43）。[quiet] で控えめな面（surfaceSecondary）にする
  const FcButton.pill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconPosition,
    this.quiet = false,
    this.expand = false,
    this.loading = false,
    this.loadingLabel = '処理しています…',
    this.semanticLabel,
  }) : variant = FcButtonVariant.pill;

  /// 文字だけの操作（accent の文字）。既定は横幅いっぱいで、文字が左・アイコンが右端
  const FcButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconPosition,
    this.expand = true,
    this.loading = false,
    this.loadingLabel = '処理しています…',
    this.semanticLabel,
  })  : variant = FcButtonVariant.text,
        quiet = false;

  /// 「戻る」のような戻り操作。既定で左矢印（arrow-left）を先頭に置く
  const FcButton.back({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = LucideIcons.arrowLeft,
    this.iconPosition = FcIconPosition.start,
    this.loading = false,
    this.loadingLabel = '処理しています…',
    this.semanticLabel,
  })  : variant = FcButtonVariant.back,
        quiet = false,
        expand = false;

  final String label;
  final VoidCallback? onPressed;
  final FcButtonVariant variant;
  final IconData? icon;

  /// null なら種類の既定（back = 先頭、それ以外 = 末尾）
  final FcIconPosition? iconPosition;

  /// pill だけ有効。true なら surfaceSecondary の控えめな面
  final bool quiet;

  /// 横幅いっぱいに広げるか。null なら種類の既定（block / text は true）
  final bool? expand;

  /// 処理中。文言を [loadingLabel] にして押せなくする
  final bool loading;
  final String loadingLabel;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tappable = onPressed != null && !loading;
    // 無効（opacity 0.4）。処理中は薄くしない
    final dimmed = onPressed == null && !loading;

    final Color background;
    final Color foreground;
    switch (variant) {
      case FcButtonVariant.block:
        background = colors.actionFill;
        foreground = colors.onAction;
      case FcButtonVariant.pill:
        background = quiet ? colors.surfaceSecondary : colors.actionFill;
        foreground = quiet ? colors.textPrimary : colors.onAction;
      case FcButtonVariant.text:
      case FcButtonVariant.back:
        background = Colors.transparent;
        foreground = colors.accent;
    }

    final double minHeight = switch (variant) {
      FcButtonVariant.block => AppSizes.primaryButtonHeight,
      FcButtonVariant.pill => AppSizes.pillButtonHeight,
      FcButtonVariant.text => 47,
      FcButtonVariant.back => AppSizes.minTouch,
    };
    final EdgeInsets padding = switch (variant) {
      FcButtonVariant.block => const EdgeInsets.all(12),
      FcButtonVariant.pill =>
        const EdgeInsets.symmetric(vertical: 11, horizontal: 17),
      FcButtonVariant.text => const EdgeInsets.symmetric(vertical: 11),
      FcButtonVariant.back => EdgeInsets.zero,
    };
    final double gap = variant == FcButtonVariant.text ? 8 : 7;
    final double iconSize = switch (variant) {
      FcButtonVariant.block => 18,
      FcButtonVariant.pill => 15,
      FcButtonVariant.text => 16,
      FcButtonVariant.back => 17,
    };
    final textStyle = switch (variant) {
      FcButtonVariant.block => AppTextStyles.body(context)
          .copyWith(fontWeight: FontWeight.w500, color: foreground),
      FcButtonVariant.pill => AppTextStyles.actionLabel(context)
          .copyWith(color: foreground, height: 1.4),
      FcButtonVariant.text => AppTextStyles.actionLabel(context)
          .copyWith(color: foreground, height: 1.5),
      FcButtonVariant.back => AppTextStyles.actionLabel(context).copyWith(
          fontWeight: FontWeight.w400, color: foreground, height: 1.5),
    };
    final centered =
        variant == FcButtonVariant.block || variant == FcButtonVariant.pill;

    final position = iconPosition ??
        (variant == FcButtonVariant.back
            ? FcIconPosition.start
            : FcIconPosition.end);
    final iconWidget = icon == null
        ? null
        : ExcludeSemantics(
            child: Icon(icon, size: iconSize, color: foreground));

    final wantsFullWidth = expand ??
        (variant == FcButtonVariant.block || variant == FcButtonVariant.text);

    Widget buildButton(bool fullWidth) {
      final children = <Widget>[
        if (iconWidget != null && position == FcIconPosition.start) ...[
          iconWidget,
          SizedBox(width: gap),
        ],
        Flexible(
          child: Text(
            loading ? loadingLabel : label,
            style: textStyle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
          ),
        ),
        if (iconWidget != null && position == FcIconPosition.end) ...[
          SizedBox(width: gap),
          iconWidget,
        ],
      ];

      Widget face = DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: centered
                  ? MainAxisAlignment.center
                  : (variant == FcButtonVariant.text && fullWidth
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.start),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: children,
            ),
          ),
        ),
      );

      if (fullWidth) {
        face = SizedBox(width: double.infinity, child: face);
      }
      if (dimmed) {
        face = Opacity(opacity: 0.4, child: face);
      }

      return FcPressable(
        onTap: onPressed,
        enabled: tappable,
        semanticLabel: semanticLabel,
        minSize: const Size.square(AppSizes.minTouch),
        child: face,
      );
    }

    if (!wantsFullWidth) return buildButton(false);
    // 横幅が無制限（Row の中など）なら内容幅に落とす
    return LayoutBuilder(
      builder: (context, constraints) =>
          buildButton(constraints.hasBoundedWidth),
    );
  }
}
