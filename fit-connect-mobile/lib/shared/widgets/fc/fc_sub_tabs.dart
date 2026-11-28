import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_bottom_nav.dart';
import 'fc_pressable.dart';

/// [FcSubTabs] の 1 項目
class FcSubTabItem<T> {
  const FcSubTabItem({
    required this.value,
    required this.label,
    this.semanticLabel,
  });

  final T value;
  final String label;
  final String? semanticLabel;
}

/// 横スクロールのカプセル型サブタブ（記録の「サマリ / 体重 / 食事 / 運動 / 睡眠 / ノート」など 5 件以上）。
/// 正本は `parts.js` の `SubTabs`。
///
/// - 外枠 = surface の面・角丸 26・内側余白 4・タブの間隔 2。タブが収まらないときは外枠の中で横スクロール
/// - 各タブ = 高さ 44 以上・幅 48 以上・角丸 22・左右余白 10・文字 14（折り返さない）。
///   収まるときは余った幅を全タブで等分して広がる（正本の `flex: 1 0 auto`）
/// - **選択中 = surfaceSecondary の面 + accent の文字 + 太さ 500、未選択 = 面なし + textSecondary**
/// - 選択が変わると見える位置へ自動でスクロールする（最初に表示するときも選択中が見える位置から始まる）
/// - 画面の左右余白の内側（幅 = 画面幅 - 40）にそのまま置く。外側の余白が要るときだけ [padding]
///
/// [FcSubTabs.compact] は 2〜3 項目用の小さなピル（会話の絞り込みなど、画面の主役でない切り替え）。
/// - 幅は内容に合わせ（全タブ等幅）、横スクロールしない。置く側で中央などに寄せる
/// - 見た目の高さは 32（外枠の内側余白 2 + タブ 28）。上下に 6 ずつ透明なタッチ領域を持ち、
///   部品の高さは 44（タッチ領域は高さ 44 以上・幅 64 以上）
/// - 色・文字・選択中の表現は通常と同じ
/// - `floating: true` は、スクロールする中身の上に重ねて浮かせるとき用。外枠だけを下部ナビ
///   （[FcBottomNav]）のカプセルと同じ扱いにする: navigationSurface の面・1px の navigationBorder の枠・
///   背景ぼかし 18・`0 3px 14px` の薄い影。「コントラストを高く」「色を反転」のときは
///   ぼかさず不透明な surface。枠は外枠の内側に描くので、寸法（外枠 32・部品 44）は変わらない
class FcSubTabs<T> extends StatefulWidget {
  const FcSubTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.padding,
  })  : compact = false,
        floating = false;

  /// 2〜3 項目用の小さなピル。幅は内容に合わせる（クラスの説明を参照）
  const FcSubTabs.compact({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.padding,
    this.floating = false,
  }) : compact = true;

  final List<FcSubTabItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  /// 外枠の外側の余白（既定は 0。左右の余白は画面側の `Padding` で付ける）
  final EdgeInsetsGeometry? padding;

  /// 小さなピルで出すか（[FcSubTabs.compact]）
  final bool compact;

  /// 中身の上に重ねて浮かせる見た目にするか（[FcSubTabs.compact] のみ。クラスの説明を参照）
  final bool floating;

  /// 外枠の角丸
  static const double radius = 26;

  /// 外枠の内側余白
  static const double inset = 4;

  /// タブの間隔
  static const double gap = 2;

  /// [FcSubTabs.compact] の外枠の内側余白
  static const double compactInset = 2;

  /// [FcSubTabs.compact] のタブの高さ（見た目）
  static const double compactTabHeight = 28;

  /// [FcSubTabs.compact] の外枠の高さ（見た目）
  static const double compactHeight = compactTabHeight + compactInset * 2;

  /// [FcSubTabs.compact] の部品の高さ（上下の透明なタッチ領域を含む）
  static const double compactTouchHeight = AppSizes.minTouch;

  @override
  State<FcSubTabs<T>> createState() => _FcSubTabsState<T>();
}

class _FcSubTabsState<T> extends State<FcSubTabs<T>> {
  final Map<int, GlobalKey> _keys = {};

  GlobalKey _keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _scheduleEnsureVisible(animate: false);
  }

  @override
  void didUpdateWidget(covariant FcSubTabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _scheduleEnsureVisible(animate: true);
    }
  }

  void _scheduleEnsureVisible({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index =
          widget.items.indexWhere((item) => item.value == widget.selected);
      final tabContext = index < 0 ? null : _keys[index]?.currentContext;
      if (tabContext != null && tabContext.mounted) {
        Scrollable.ensureVisible(
          tabContext,
          alignment: 0.5,
          duration: (!animate || AppMotion.reduceOf(context))
              ? Duration.zero
              : AppMotion.select,
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (widget.compact) return _buildCompact(colors);

    // 隣り合うタブの間隔 2 は、各タブの左右に 1 ずつの余白として持たせる
    // （Table の列幅は「内容幅 + 余った幅の等分」になり、正本の flex: 1 0 auto と同じ配分になる）
    const half = FcSubTabs.gap / 2;
    const scrollPadding = EdgeInsets.symmetric(
      horizontal: FcSubTabs.inset - half,
      vertical: FcSubTabs.inset,
    );

    Widget tabs = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FcSubTabs.radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FcSubTabs.radius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentMinWidth = constraints.hasBoundedWidth
                ? math.max(0.0, constraints.maxWidth - scrollPadding.horizontal)
                : 0.0;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: scrollPadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: contentMinWidth),
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: [
                    TableRow(
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: half),
                            child: _SubTab(
                              key: _keyFor(i),
                              label: widget.items[i].label,
                              semanticLabel: widget.items[i].semanticLabel,
                              active: widget.items[i].value == widget.selected,
                              compact: false,
                              colors: colors,
                              onTap: () =>
                                  widget.onChanged(widget.items[i].value),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    if (widget.padding != null) {
      tabs = Padding(padding: widget.padding!, child: tabs);
    }
    return tabs;
  }

  /// 小さなピル。外枠（見た目 32）の上下に透明なタッチ領域を足して、高さ 44 にする
  Widget _buildCompact(AppColorsExtension colors) {
    const half = FcSubTabs.gap / 2;
    const touchOutset =
        (FcSubTabs.compactTouchHeight - FcSubTabs.compactHeight) / 2;

    Widget tabs = Stack(
      children: [
        // 外枠の面（タッチ領域の分だけ上下を空ける。文字拡大で伸びたら一緒に伸びる）
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: touchOutset),
            child: widget.floating
                ? _buildFloatingFace(colors)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(FcSubTabs.radius),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FcSubTabs.compactInset - half,
          ),
          // 全タブ等幅（いちばん広いタブに合わせる）
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  Expanded(
                    child: _SubTab(
                      key: _keyFor(i),
                      label: widget.items[i].label,
                      semanticLabel: widget.items[i].semanticLabel,
                      active: widget.items[i].value == widget.selected,
                      compact: true,
                      colors: colors,
                      onTap: () => widget.onChanged(widget.items[i].value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.padding != null) {
      tabs = Padding(padding: widget.padding!, child: tabs);
    }
    return tabs;
  }

  /// 浮かせるときの外枠の面。下部ナビのカプセルと同じ（面・枠・ぼかし・影）。
  /// 枠は面の内側に描く（子を持たない面なので、寸法は変わらない）
  Widget _buildFloatingFace(AppColorsExtension colors) {
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final solid = media.highContrast || media.invertColors;
    final borderRadius = BorderRadius.circular(FcSubTabs.radius);

    Widget face = DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? colors.surface : colors.navigationSurface,
        borderRadius: borderRadius,
        border: Border.all(
          color: colors.navigationBorder,
          width: AppSizes.navBorderWidth,
        ),
      ),
    );
    if (!solid) {
      face = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: FcBottomNav.blurSigma,
          sigmaY: FcBottomNav.blurSigma,
        ),
        child: face,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: FcBottomNav.capsuleShadow(isDark: isDark),
      ),
      child: ClipRRect(borderRadius: borderRadius, child: face),
    );
  }
}

class _SubTab extends StatelessWidget {
  const _SubTab({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.active,
    required this.compact,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final String? semanticLabel;
  final bool active;
  final bool compact;
  final AppColorsExtension colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.reduceOf(context);
    final text = Text(
      label,
      softWrap: false,
      style: AppTextStyles.label(context).copyWith(
        fontWeight: active ? FontWeight.w500 : FontWeight.w400,
        color: active ? colors.accent : colors.textSecondary,
      ),
    );
    final face = BoxDecoration(
      color: active ? colors.surfaceSecondary : Colors.transparent,
      borderRadius: BorderRadius.circular(22),
    );

    if (compact) {
      // 面（高さ 28）の外側の余白もタップできる（上下 = 外枠の内側余白 2 + 透明なタッチ領域 6）
      const vertical =
          (FcSubTabs.compactTouchHeight - FcSubTabs.compactTabHeight) / 2;
      return FcPressable(
        onTap: onTap,
        selected: active,
        semanticLabel: semanticLabel ?? label,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FcSubTabs.gap / 2,
            vertical: vertical,
          ),
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppMotion.select,
            curve: Curves.easeOut,
            constraints: const BoxConstraints(
              minWidth: 64,
              minHeight: FcSubTabs.compactTabHeight,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: face,
            child: Center(heightFactor: 1, child: text),
          ),
        ),
      );
    }

    return FcPressable(
      onTap: onTap,
      selected: active,
      semanticLabel: semanticLabel ?? label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppMotion.select,
        curve: Curves.easeOut,
        constraints: const BoxConstraints(
          minWidth: 48,
          minHeight: AppSizes.minTouch,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: face,
        child: text,
      ),
    );
  }
}
