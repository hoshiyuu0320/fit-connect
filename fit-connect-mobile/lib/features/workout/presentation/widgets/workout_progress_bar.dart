import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 今日のプランの進み具合（「進み具合」＋「1 / 3 種目」＋ 4px のバー）。
///
/// 正本は `plan-screens.js` の `TodayPlan` の進み具合ブロック。
/// バーは surfaceSecondary の地に accent の塗り（角丸 2）。数字は桁幅をそろえる。
/// 完了しても色は変えない（達成を色や演出で強調しない）。
class WorkoutProgressBar extends StatelessWidget {
  const WorkoutProgressBar({
    super.key,
    required this.completed,
    required this.total,
  });

  final int completed;
  final int total;

  /// バーの高さ（正本 4px。トークンに無いのでここだけの定数）
  static const double _barHeight = 4;

  /// バーの角丸（正本 2px）
  static const double _barRadius = 2;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final progress =
        total > 0 ? (completed / total).clamp(0.0, 1.0).toDouble() : 0.0;
    final summary = '$completed / $total 種目';

    return Semantics(
      container: true,
      label: '進み具合 $summary',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('進み具合', style: AppTextStyles.caption(context)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                summary,
                style: AppTextStyles.caption(context)
                    .copyWith(fontFeatures: AppTextStyles.tabularFigures),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(_barRadius),
            child: SizedBox(
              height: _barHeight,
              width: double.infinity,
              child: ColoredBox(
                color: colors.surfaceSecondary,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    heightFactor: 1,
                    child: ColoredBox(
                      key: const ValueKey('workout-progress-fill'),
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewProgress(Brightness brightness, int completed, int total,
    {double textScale = 1.0}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: textScale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: FcCard(
            child: WorkoutProgressBar(completed: completed, total: total),
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutProgressBar - 1 / 3')
Widget previewWorkoutProgressBarInProgress() =>
    _previewProgress(Brightness.light, 1, 3);

@Preview(name: 'WorkoutProgressBar - 3 / 3')
Widget previewWorkoutProgressBarCompleted() =>
    _previewProgress(Brightness.light, 3, 3);

@Preview(name: 'WorkoutProgressBar - 0 / 3')
Widget previewWorkoutProgressBarEmpty() =>
    _previewProgress(Brightness.light, 0, 3);

@Preview(name: 'WorkoutProgressBar - Dark')
Widget previewWorkoutProgressBarDark() =>
    _previewProgress(Brightness.dark, 1, 3);
