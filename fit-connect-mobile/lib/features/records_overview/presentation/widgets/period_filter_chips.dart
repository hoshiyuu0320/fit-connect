import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 期間フィルタ（今週 / 今月 / 3ヶ月）。単独の行のセグメント（[FcSegmentedControl]）。
///
/// サマリは正本どおり 3 択。ラベルは [PeriodFilter.label]。
class PeriodFilterChips extends StatelessWidget {
  final PeriodFilter selected;
  final ValueChanged<PeriodFilter> onChanged;

  const PeriodFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// サマリで選べる期間
  static const List<PeriodFilter> periods = [
    PeriodFilter.week,
    PeriodFilter.month,
    PeriodFilter.threeMonths,
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '期間',
      child: FcSegmentedControl<PeriodFilter>(
        items: [
          for (final p in periods)
            FcSegmentedItem<PeriodFilter>(value: p, label: p.label),
        ],
        selected: selected,
        onChanged: onChanged,
      ),
    );
  }
}

class _PreviewPeriod extends StatelessWidget {
  const _PreviewPeriod({required this.selected});

  final PeriodFilter selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.pageHorizontalOf(context)),
          child: PeriodFilterChips(selected: selected, onChanged: (_) {}),
        ),
      ),
    );
  }
}

@Preview(name: 'PeriodFilterChips - 今月')
Widget previewPeriodFilterChipsMonth() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewPeriod(selected: PeriodFilter.month),
  );
}

@Preview(name: 'PeriodFilterChips - 今週（ダーク）')
Widget previewPeriodFilterChipsWeekDark() {
  return const FcPreviewApp(
    brightness: Brightness.dark,
    home: _PreviewPeriod(selected: PeriodFilter.week),
  );
}
