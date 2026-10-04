import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_pressable.dart';

// ============================================
// 囲み・丸ボタン・閉じる・写真の代替
// 正本: record-screens.js / message-screens.js / plan-screens.js / parts.js (`Photo`)
// ============================================

/// 推定値・コーチのメモ・就寝/起床 のような、カードの中の控えめな囲み。
///
/// surfaceSecondary の面・角丸 12・余白 縦 10 × 横 14。surface の上に重ねて使う。
/// 既定で横幅いっぱいに広がる（`Row` の中などでは `expand: false`）。
/// 例: `FcInfoBox(child: Text('推定 640 kcal'))`
class FcInfoBox extends StatelessWidget {
  const FcInfoBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.expand = true,
    this.semanticLabel,
  });

  final Widget child;

  /// 既定は縦 10 × 横 14（コーチのメモのように 11 × 14 にしたいときだけ変える）
  final EdgeInsetsGeometry padding;

  final bool expand;

  /// 読み上げをまとめて上書きしたいとき
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (expand) {
      box = SizedBox(width: double.infinity, child: box);
    }
    if (semanticLabel != null) {
      box = Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: box,
      );
    }
    return box;
  }
}

/// 44×44 の丸いアイコンボタン（送信・写真を添付・同期など）。
///
/// - 既定: surface の面 ＋ textSecondary のアイコン。`primary: true` は actionFill ＋ onAction
/// - [iconColor] でアイコン色を変えられる（記録の同期ボタンは accent）
/// - [onPressed] が null なら無効（不透明度 0.4・押せない）
/// - アイコンだけなので [semanticLabel] は必須（読み上げ）
/// - 既定の面は surface なので、背景（background）の上で見える。surface のカードの上に置くと
///   面が溶けて見えない（その場合は `primary` を使うか、`surfaceSecondary` の面の上に置く）
///
/// 例: `FcIconButton(icon: LucideIcons.arrowUp, semanticLabel: '送信', primary: true, onPressed: send)`
class FcIconButton extends StatelessWidget {
  const FcIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.primary = false,
    this.iconColor,
    this.iconSize = AppSizes.icon,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool primary;

  /// null なら primary は onAction、既定は textSecondary
  final Color? iconColor;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null;
    final background = primary ? colors.actionFill : colors.surface;
    final foreground =
        iconColor ?? (primary ? colors.onAction : colors.textSecondary);

    return FcPressable(
      onTap: onPressed,
      enabled: enabled,
      semanticLabel: semanticLabel,
      minSize: const Size.square(AppSizes.minTouch),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: AppSizes.minTouch,
          height: AppSizes.minTouch,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(icon, size: iconSize, color: foreground),
        ),
      ),
    );
  }
}

/// 44×44 の「×」ボタン（フォーム・返信バナーを閉じる）。textSecondary・アイコン 18。
///
/// 部品自体は 44×44 のまま（余白は含まない）。正本の `CloseBtn` は右に -12・上下に -10 の
/// 負マージンで詰めているが、Flutter では負の余白を置くと押せる範囲が欠けるため、
/// **配置側でカードの余白を減らして**詰める（[endBleed] / [verticalBleed] は正本の値）。
///
/// 例: カード右上に置くとき
/// `FcCard(paddingOverride: EdgeInsets.fromLTRB(18, 18 - FcCloseButton.verticalBleed, 18 - FcCloseButton.endBleed, 18), ...)`
/// とし、見出し行の直後の余白を `12 - FcCloseButton.verticalBleed` にする。
class FcCloseButton extends StatelessWidget {
  const FcCloseButton({
    super.key,
    required this.onPressed,
    this.semanticLabel = '閉じる',
  });

  /// 正本の右の負マージン（12）。カードの右余白からこの分を引くと「×」が本文の右端に揃う
  static const double endBleed = 12;

  /// 正本の上下の負マージン（10）。行の高さを 24 に保つために上下の余白から引く
  static const double verticalBleed = 10;

  final VoidCallback? onPressed;

  /// 読み上げ。既定は「閉じる」。返信バナーなら「返信をやめる」など
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FcPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      minSize: const Size.square(AppSizes.minTouch),
      child: SizedBox(
        width: AppSizes.minTouch,
        height: AppSizes.minTouch,
        child: Center(
          child: Icon(LucideIcons.x, size: 18, color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// 写真が無い・読み込み中のときの代替面（`Photo`）。
///
/// surfaceSecondary の面に image アイコン（22）。高さが 100 以上なら [label] も出す。
/// [width] を省略すると親の幅いっぱい（`Row` の中などでは [width] を渡す）。
/// 読み上げは [label]（画像として）。
/// 例: `FcPhotoPlaceholder(height: 176, radius: 0, label: '食事の写真')`
class FcPhotoPlaceholder extends StatelessWidget {
  const FcPhotoPlaceholder({
    super.key,
    this.height = 160,
    this.width,
    this.radius = 16,
    this.label = '写真',
  });

  final double height;
  final double? width;
  final double radius;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      image: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.image, size: 22, color: colors.textSecondary),
                if (height >= 100) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
