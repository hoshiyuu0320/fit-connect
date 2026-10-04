import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';

/// オン/オフの切り替え（iOS 風スイッチ）。正本は `parts.js` の `Toggle`。
///
/// 51×31・つまみ 27（白）。**オン = actionFill、オフ = separator**。
/// 見た目は 51×31 だが、タッチ領域は縦 44 以上に広げている（行全体を押せるようにしたい場合は
/// 行側を `FcPressable` で包み、ここは `onChanged: null` ではなくそのまま渡す）。
/// [semanticLabel]（例:「通知」）は必ず渡す。
class FcToggle extends StatelessWidget {
  const FcToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;

  /// null なら無効（操作できない）
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onChanged != null;

    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: enabled,
      excludeSemantics: true,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // スイッチ本体の外側（縦 44 の余白部分）を押しても切り替わる
        onTap: enabled ? () => onChanged!(!value) : null,
        child: SizedBox(
          width: 51,
          height: AppSizes.minTouch,
          child: Center(
            child: CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: colors.actionFill,
              inactiveTrackColor: colors.separator,
              thumbColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 完了マーク。正本は `parts.js` の `DoneMark`。
///
/// - 完了 = actionFill の塗り円 + onAction のチェック（円の 60%・線 2.2）
/// - 未完了 = 1.5px の枠だけの円（枠は textSecondary の 55%）
///
/// 完了/未完了は色だけでなく **形（チェックの有無）** でも区別できる。
/// 読み上げは「完了」「未完了」（[semanticLabel] で上書き可）。
class FcDoneMark extends StatelessWidget {
  const FcDoneMark({
    super.key,
    required this.done,
    this.size = 24,
    this.semanticLabel,
  });

  final bool done;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reduceMotion = AppMotion.reduceOf(context);

    return Semantics(
      label: semanticLabel ?? (done ? '完了' : '未完了'),
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppMotion.select,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? colors.actionFill : Colors.transparent,
          border: done
              ? null
              : Border.all(
                  color: colors.textSecondary.withValues(alpha: 0.55),
                  width: 1.5,
                ),
        ),
        child: done
            ? Center(
                child: CustomPaint(
                  size: Size.square((size * 0.6).roundToDouble()),
                  painter: _CheckPainter(colors.onAction),
                ),
              )
            : null,
      ),
    );
  }
}

/// Lucide の check（24 の枠に `M20 6 9 17l-5-5`）を、線 2.2 で描く
class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final path = Path()
      ..moveTo(20 * unit, 6 * unit)
      ..lineTo(9 * unit, 17 * unit)
      ..lineTo(4 * unit, 12 * unit);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 小さな点（6×6）。塗り = 記録あり・予定あり など、中抜き = 予定のみ・日付が過ぎた など。
/// 正本は `parts.js` の `Dot`。
///
/// - 塗り = accent の単色、中抜き = 1.5px の枠（textSecondary）。カテゴリで色を変えない
/// - [color] を渡すと塗り・枠ともその色にする
/// - 読み上げ対象外（意味は隣の文言で伝える）
class FcDot extends StatelessWidget {
  const FcDot({
    super.key,
    this.filled = true,
    this.size = 6,
    this.color,
  });

  final bool filled;
  final double size;

  /// null なら 塗り = accent、中抜き = textSecondary
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? (color ?? colors.accent) : Colors.transparent,
          border: filled
              ? null
              : Border.all(color: color ?? colors.textSecondary, width: 1.5),
        ),
      ),
    );
  }
}
