import 'package:flutter/material.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';

/// ボトムシートの上端に置くハンドル（36 × 5・角丸 3・separator）。
/// 正本 `plan-screens.js` の `ReportSheet`。読み上げ対象外（閉じる操作はシートの中のボタンで用意する）。
class WorkoutSheetHandle extends StatelessWidget {
  const WorkoutSheetHandle({super.key});

  static const double width = 36;
  static const double height = 5;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.of(context).separator,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
