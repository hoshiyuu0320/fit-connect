import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';

/// 読み込み中の仮表示（スケルトン）。
///
/// - 動かない静的な面（skeleton 色）。点滅・シマーはしない（「動きを減らす」にも安全で、
///   `pumpAndSettle` を止めない）
/// - 読み上げ対象外。読み込み中であることは画面側で `Semantics(label: '読み込み中')` を付ける
/// - 幅・高さを省略した場合は、親の幅いっぱい・高さ 14・角丸 6（正本の既定）
/// - 正本では不透明度が脈動する（1.4s ease-in-out の繰り返し）が、ここでは静的なまま
///   （テストの `pumpAndSettle` を止めないため）
///
/// 使い分け: 文字行は `FcSkeleton.line`、円形（アバター）は `FcSkeleton.circle`、
/// カード型の面は `FcSkeleton.card`。
class FcSkeleton extends StatelessWidget {
  const FcSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  }) : _circle = false;

  /// 文字 1 行ぶんの帯（高さ 14・角丸 6）。[width] を行ごとにずらすと自然に見える
  const FcSkeleton.line({
    super.key,
    this.width,
    this.height = 14,
  })  : radius = 6,
        _circle = false;

  /// 円形（アバターなど）
  const FcSkeleton.circle({
    super.key,
    double size = AppSizes.avatar,
  })  : width = size,
        height = size,
        radius = 0,
        _circle = true;

  /// カード型の面（角丸 23）
  const FcSkeleton.card({
    super.key,
    this.width,
    this.height = 120,
  })  : radius = AppRadius.card,
        _circle = false;

  final double? width;
  final double height;
  final double radius;
  final bool _circle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: width ?? (_circle ? null : double.infinity),
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.skeleton,
            shape: _circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: _circle ? null : BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }
}
