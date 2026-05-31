import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

/// 期間フィルタを iOS 風セグメンテッドコントロールで切り替える Widget。
///
/// - 白い角丸コンテナ（影で浮かせる）の中に 4 つのセグメントを等幅で並べる
/// - 選択中: AppColors.primary600 塗りつぶしピル + 白文字
/// - 非選択: 透明背景 + slate500 文字
/// - 選択肢: 週 / 月 / 3ヶ月 / 全期間
class PeriodFilterChips extends StatelessWidget {
  final PeriodFilter selected;
  final ValueChanged<PeriodFilter> onChanged;

  const PeriodFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _items = <_FilterItem>[
    _FilterItem(filter: PeriodFilter.week, label: '週'),
    _FilterItem(filter: PeriodFilter.month, label: '月'),
    _FilterItem(filter: PeriodFilter.threeMonths, label: '3ヶ月'),
    _FilterItem(filter: PeriodFilter.all, label: '全期間'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          // rgba(15, 23, 42, 0.08) 相当のやわらかい影
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final item in _items)
            Expanded(
              child: _Segment(
                label: item.label,
                active: item.filter == selected,
                onTap: () => onChanged(item.filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary600 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? const [
                  // rgba(37, 99, 235, 0.2) 相当の控えめな浮遊感
                  BoxShadow(
                    color: Color(0x332563EB),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : AppColors.slate500,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _FilterItem {
  final PeriodFilter filter;
  final String label;
  const _FilterItem({required this.filter, required this.label});
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
