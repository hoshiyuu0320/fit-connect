import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/segmented_control.dart';

/// 期間フィルタを iOS 風セグメンテッドコントロールで切り替える Widget。
///
/// 見た目・挙動は共通の [SegmentedControl] に集約済み
/// （SessionsScreen の「今後 / 過去」と同じ実装を使う）。
/// ここは選択肢（週 / 月 / 3ヶ月 / 全期間）の定義だけを持つ。
class PeriodFilterChips extends StatelessWidget {
  final PeriodFilter selected;
  final ValueChanged<PeriodFilter> onChanged;

  const PeriodFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _items = <SegmentedControlItem<PeriodFilter>>[
    SegmentedControlItem(value: PeriodFilter.week, label: '週'),
    SegmentedControlItem(value: PeriodFilter.month, label: '月'),
    SegmentedControlItem(value: PeriodFilter.threeMonths, label: '3ヶ月'),
    SegmentedControlItem(value: PeriodFilter.all, label: '全期間'),
  ];

  @override
  Widget build(BuildContext context) {
    return SegmentedControl<PeriodFilter>(
      items: _items,
      selected: selected,
      onChanged: onChanged,
    );
  }
}

@Preview(name: 'PeriodFilterChips - Month Selected')
Widget previewPeriodFilterChipsMonth() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PeriodFilterChips(
            selected: PeriodFilter.month,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'PeriodFilterChips - Week Selected')
Widget previewPeriodFilterChipsWeek() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PeriodFilterChips(
            selected: PeriodFilter.week,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}
