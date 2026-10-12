import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';

/// 区切り線（1px / separator）。読み上げ対象外。
///
/// カード内の項目の区切りに使う。[indent] / [endIndent] で左右を詰められる。
class FcSeparator extends StatelessWidget {
  const FcSeparator({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
  });

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
        child: SizedBox(
          height: 1,
          width: double.infinity,
          child: ColoredBox(color: AppColors.of(context).separator),
        ),
      ),
    );
  }
}
