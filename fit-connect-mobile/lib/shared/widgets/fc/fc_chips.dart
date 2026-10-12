import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_pressable.dart';

/// [FcChips] の 1 項目
class FcChipItem<T> {
  const FcChipItem({
    required this.value,
    required this.label,
    this.icon,
    this.semanticLabel,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? semanticLabel;
}

/// 選択チップ（食事の区分・運動の種類・時間帯など）。折り返して並ぶ。正本は `parts.js` の `Chips`。
///
/// - 高さ 40・角丸 20・左右余白 16・文字 14・間隔 6
/// - **選択中 = surface の面 + accent の文字 + 太さ 500、未選択 = 面なし（透明）+ textSecondary**
///   （ページ背景の上に直接置く前提。surface のカードの上では選択中の面が見えない）
/// - カテゴリごとに色を割り振らない。区別はアイコンと言葉で行う
/// - 単一選択: `FcChips.single(selected: x, onSelected: ...)`、複数選択: `FcChips(selected: {..}, onSelected: toggle)`
/// - 見た目の高さは 40 のまま、タッチ領域は高さ 44 に広げてある（上下 2 の透明な余白）。
///   文字拡大では折り返して高さが伸びる
class FcChips<T> extends StatelessWidget {
  const FcChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  /// 単一選択（[selected] が null なら未選択）
  FcChips.single({
    Key? key,
    required List<FcChipItem<T>> items,
    required T? selected,
    required ValueChanged<T> onSelected,
  }) : this(
          key: key,
          items: items,
          selected: selected == null ? <T>{} : <T>{selected},
          onSelected: onSelected,
        );

  final List<FcChipItem<T>> items;

  /// 選択中の値の集合
  final Set<T> selected;

  /// チップが押されたとき（選択・解除の切り替えは呼び出し側で行う）
  final ValueChanged<T> onSelected;

  /// チップの見た目の高さ
  static const double height = 40;

  /// チップどうしの間隔
  static const double gap = 6;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: gap,
      // タッチ領域 44 − 見た目 40 = 4（上下 2 ずつ）。見た目の行間を 6 にするため 6 − 4 = 2
      runSpacing: gap - (AppSizes.minTouch - height),
      children: [
        for (final item in items)
          _Chip(
            item: item,
            active: selected.contains(item.value),
            onTap: () => onSelected(item.value),
          ),
      ],
    );
  }
}

class _Chip<T> extends StatelessWidget {
  const _Chip({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final FcChipItem<T> item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final foreground = active ? colors.accent : colors.textSecondary;
    final reduceMotion = AppMotion.reduceOf(context);

    return FcPressable(
      onTap: onTap,
      selected: active,
      semanticLabel: item.semanticLabel ?? item.label,
      minSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppMotion.select,
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: FcChips.height),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        // 幅は内容に合わせたまま（alignment を使うと Wrap の中で幅いっぱいに広がる）、高さの余りは中央に寄せる
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.icon != null) ...[
                ExcludeSemantics(
                  child: Icon(item.icon, size: 16, color: foreground),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  item.label,
                  style: AppTextStyles.label(context).copyWith(
                    color: foreground,
                    fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
