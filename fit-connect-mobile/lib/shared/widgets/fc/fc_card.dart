import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'fc_pressable.dart';

/// カード内余白の種類
enum FcCardPadding {
  /// 標準（全周 20）
  standard,

  /// コーチカード（全周 17）
  coach,

  /// 健康カード（上下 16・左右 14）
  health,

  /// 余白なし（画像や区切り線を端まで広げたいとき）
  none,
}

/// 本文カード。
///
/// - 角丸 23、**不透明**な surface、枠線・影なし（カードごとに色を変えない）
/// - [onTap] を渡すとカード全体が押せる（押下で scale 0.98）。[semanticLabel] で読み上げを指定できる
/// - 既定で横幅いっぱいに広がる。`Row` の中など横幅が無制限の場所では `expand: false`
/// - 角丸に沿って子をクリップする（`padding: none` で画像を端まで置ける）
class FcCard extends StatelessWidget {
  const FcCard({
    super.key,
    required this.child,
    this.padding = FcCardPadding.standard,
    this.paddingOverride,
    this.onTap,
    this.semanticLabel,
    this.expand = true,
  });

  final Widget child;
  final FcCardPadding padding;

  /// [padding] の代わりに任意の余白を指定したいときだけ使う
  final EdgeInsetsGeometry? paddingOverride;

  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool expand;

  static EdgeInsets paddingOf(FcCardPadding padding) {
    switch (padding) {
      case FcCardPadding.standard:
        return const EdgeInsets.all(AppSpacing.cardPadding);
      case FcCardPadding.coach:
        return const EdgeInsets.all(AppSpacing.coachCardPadding);
      case FcCardPadding.health:
        return const EdgeInsets.symmetric(
          vertical: AppSpacing.healthCardVertical,
          horizontal: AppSpacing.healthCardHorizontal,
        );
      case FcCardPadding.none:
        return EdgeInsets.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: paddingOverride ?? paddingOf(padding),
          child: child,
        ),
      ),
    );

    if (expand) {
      card = SizedBox(width: double.infinity, child: card);
    }

    if (onTap != null) {
      card = FcPressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: card,
      );
    } else if (semanticLabel != null) {
      card = Semantics(
        container: true,
        label: semanticLabel,
        child: card,
      );
    }
    return card;
  }
}
