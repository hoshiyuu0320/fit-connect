import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_pressable.dart';

/// [FcSegmentedControl] の 1 項目
class FcSegmentedItem<T> {
  const FcSegmentedItem({
    required this.value,
    required this.label,
    this.semanticLabel,
  });

  final T value;
  final String label;

  /// 読み上げを表示文字と変えたいときだけ指定する
  final String? semanticLabel;
}

/// 並んだボタン式のセグメント（今後/過去、週/月/3ヶ月/全期間、食事の区分 など 2〜4 択）。
/// 正本は `components/forms/SegmentedControl.jsx`。
///
/// - カードに入れず、**単独の行**として置く（外側の面は持たない）。項目の間隔は 7
/// - 選択中 = actionFill の塗り + onAction の文字 + actionFill の枠、
///   未選択 = surface の面 + 1px separator の枠 + textSecondary の文字
/// - 高さ 45 以上・角丸 10・余白 6×8・文字 15（選択 500 / 未選択 400）。項目は等幅
/// - 各項目のタッチ領域は高さ 45 × 幅（均等割り）で 44 以上
/// - 文字拡大では項目が折り返して高さが伸びる（縮めない。全項目が同じ高さに揃う）
/// - 選択状態は `Semantics(selected)` で伝える
///
/// 項目が多い・横スクロールが要る場合は [FcSubTabs] を使う。
class FcSegmentedControl<T> extends StatelessWidget {
  const FcSegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<FcSegmentedItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  /// 項目どうしの間隔
  static const double gap = 7;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Expanded(
              child: _Segment(
                label: items[i].label,
                semanticLabel: items[i].semanticLabel,
                active: items[i].value == selected,
                onTap: () => onChanged(items[i].value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.semanticLabel,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String? semanticLabel;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reduceMotion = AppMotion.reduceOf(context);

    return FcPressable(
      onTap: onTap,
      selected: active,
      semanticLabel: semanticLabel ?? label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppMotion.select,
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: AppSizes.segmentHeight),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.actionFill : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.segment),
          border: Border.all(
            color: active ? colors.actionFill : colors.separator,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.actionLabel(context).copyWith(
            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
            height: 1.4,
            color: active ? colors.onAction : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
