import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

/// セグメンテッドコントロールの1項目
class SegmentedControlItem<T> {
  final T value;
  final String label;

  const SegmentedControlItem({
    required this.value,
    required this.label,
  });
}

/// iOS 風セグメンテッドコントロール（期間フィルタ / セッションの今後・過去など）。
///
/// - 角丸コンテナ（影で浮かせる）の中に項目を等幅で並べる
/// - 選択中: AppColors.primary600 塗りつぶしピル + 白文字
/// - 非選択: 透明背景 + textSecondary 文字
/// - 高さ40（外枠のpadding4と合わせて48）でタッチターゲットを確保する
///
/// ※ PeriodFilterChips と SessionsScreen で同じ見た目を二重実装していたため
///   ここへ集約した。色は AppColors.of(context) 経由でダークモードに追従させる
class SegmentedControl<T> extends StatelessWidget {
  final List<SegmentedControlItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  const SegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _Segment(
                label: item.label,
                active: item.value == selected,
                onTap: () => onChanged(item.value),
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
    final colors = AppColors.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        // タッチターゲット確保のため高さ40（外枠のpadding4と合わせて48）
        height: 40,
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
            color: active ? Colors.white : colors.textSecondary,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'SegmentedControl - Two Items')
Widget previewSegmentedControlTwoItems() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedControl<String>(
            items: const [
              SegmentedControlItem(value: 'upcoming', label: '今後'),
              SegmentedControlItem(value: 'past', label: '過去'),
            ],
            selected: 'upcoming',
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'SegmentedControl - Four Items Dark')
Widget previewSegmentedControlFourItemsDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedControl<int>(
            items: const [
              SegmentedControlItem(value: 0, label: '週'),
              SegmentedControlItem(value: 1, label: '月'),
              SegmentedControlItem(value: 2, label: '3ヶ月'),
              SegmentedControlItem(value: 3, label: '全期間'),
            ],
            selected: 1,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}
