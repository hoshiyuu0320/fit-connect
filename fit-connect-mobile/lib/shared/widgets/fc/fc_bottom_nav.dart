import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_pressable.dart';

/// [FcBottomNav] の 1 タブ
class FcBottomNavItem {
  const FcBottomNavItem({
    required this.icon,
    required this.label,
    this.showDot = false,
    this.dotSemanticLabel = '新着あり',
  });

  final IconData icon;
  final String label;

  /// 数字のない小さな点（新着あり）を出すか
  final bool showDot;

  /// 点があるときに読み上げへ足す文言。「メッセージ（新着あり）」のように読み上げる
  final String dotSemanticLabel;
}

/// 浮遊するすりガラスのカプセル型・下部ナビ（5 タブ）。正本は `components/navigation/BottomNav.jsx`。
///
/// - footer の余白は 上 14 / 左右 17 / 下 15。カプセルは余白 5 + 枠 1px（navigationBorder）・
///   外形角丸 40・操作の間隔 2・高さ 64（操作 52 + (5 + 1) × 2）。全体の高さは 14 + 64 + 15 = 93
/// - 背景ぼかし 18・navigationSurface・`0 3px 14px` の薄い影（ライトは黒約 4%、ダークは 20%）
/// - 各操作: 最小高さ 52・余白 縦 6 × 横 3・アイコン 20 とラベル 11 の間 3・選択部角丸 28。
///   **選択中 = surfaceSecondary の面 + accent の文字（太さ 500）、未選択 = textSecondary**
/// - 新着は **数字のない小さな点**（[FcBottomNavItem.showDot]。7×7・accent・外周 2 の navigationSurface のリング・
///   アイコンの右上）。件数は出さない。読み上げは「メッセージ（新着あり）」
/// - 選択状態は `Semantics(selected)` で伝える。「コントラストを高く」「色を反転」のときは
///   ぼかさず不透明な surface にする（Flutter は iOS の「透明度を下げる」を直接は公開しないため、
///   取れる範囲の `highContrast` / `invertColors` を使う）
/// - ラベルの文字拡大は 1.15 倍で頭打ち（タブバーの慣例。読み上げは全文のまま）。収まらない
///   ときは折り返さず縮める（正本は `overflow-wrap: anywhere` の折り返し）
///
/// 通常は直接使わず、[FcBottomNavLayout] 越しに `MainScreen` が使う。
/// 画面側がナビを意識して余白を取る必要はない（[FcBottomNavLayout] 参照）。
class FcBottomNav extends StatelessWidget {
  const FcBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.opaque,
  });

  final List<FcBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// true で常に不透明（ぼかしなし）。null なら端末のアクセシビリティ設定に従う
  final bool? opaque;

  /// ナビのラベルの文字拡大の上限
  static const double maxLabelScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final solid = opaque ?? (media.highContrast || media.invertColors);

    final bottom = AppSizes.navBottomOffsetOf(context);

    Widget capsuleContent = DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? colors.surface : colors.navigationSurface,
        borderRadius: BorderRadius.circular(AppRadius.navigation),
        border: Border.all(
          color: colors.navigationBorder,
          width: AppSizes.navBorderWidth,
        ),
      ),
      child: Padding(
        // 枠線 1 の内側に余白 5
        padding: const EdgeInsets.all(
          AppSizes.navBorderWidth + AppSizes.navPadding,
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: maxLabelScale,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSizes.navItemGap),
                Expanded(
                  child: _NavItem(
                    item: items[i],
                    selected: i == currentIndex,
                    solid: solid,
                    onTap: () => onTap(i),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!solid) {
      capsuleContent = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: capsuleContent,
      );
    }

    // MainScreen では Scaffold の外に置かれ、Material 祖先が無いと Text が
    // 既定の（黄色い下線・等幅の）文字スタイルになるため、透明な Material で包む
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.navHorizontal,
          AppSizes.navTopPadding,
          AppSizes.navHorizontal,
          bottom,
        ),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'メインナビゲーション',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.navigation),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                  offset: const Offset(0, 3),
                  blurRadius: 14,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.navigation),
              child: capsuleContent,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.solid,
    required this.onTap,
  });

  final FcBottomNavItem item;
  final bool selected;
  final bool solid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reduceMotion = AppMotion.reduceOf(context);
    final color = selected ? colors.accent : colors.textSecondary;
    // 点の外周のリング: ナビの面の色（選択中の面の上でも同じ色）
    final dotRing = solid ? colors.surface : colors.navigationSurface;

    final semanticLabel =
        item.showDot ? '${item.label}（${item.dotSemanticLabel}）' : item.label;

    return FcPressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: semanticLabel,
      // 面（選択中の surfaceSecondary）は列の幅いっぱいに広げる。タッチ領域は面の大きさ（幅 ≥ 52 / 高さ 52）
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppMotion.select,
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: AppSizes.navItemHeight),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
        decoration: BoxDecoration(
          color: selected ? colors.surfaceSecondary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.navigationSelected),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(item.icon, size: AppSizes.icon, color: color),
                if (item.showDot)
                  Positioned(
                    top: -1,
                    right: -4,
                    // 7×7 の点 + 外周 2 のリング（box-shadow 0 0 0 2px）
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.accent,
                        boxShadow: [
                          BoxShadow(color: dotRing, spreadRadius: 2),
                        ],
                      ),
                      child: const SizedBox.square(dimension: 7),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                style: AppTextStyles.navLabel(context, selected: selected)
                    .copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下部ナビが本文を覆わないようにするレイアウト。`MainScreen` が使う。
///
/// - [body]（選択中のタブ画面）の `MediaQuery.padding.bottom` に
///   「ナビの高さ + 下端位置 + 余白」（参照値 93 + 28 = 121）を加算して包む。
///   タブ画面側の `SafeArea` / 余白指定なしの `ListView` / `SingleChildScrollView` は、
///   **改修しなくても自動でナビの上に収まる**
/// - 同じ値を `viewPadding.bottom` にも加算する。Scaffold は「浮かせた SnackBar」を
///   `viewPadding` の上に置くので、SnackBar がナビの下に潜らず、ナビの上に出る
///   （固定の SnackBar は `padding.bottom` ぶんの高い帯をナビの裏に作ってしまう）
/// - [bottomNav] は [body] の上に重ねて下端へ浮かせる
/// - **キーボードの表示・非表示の最中も連続的に動く**: 加算する余白は
///   `max(ナビの確保量 − viewInsets.bottom, 0)`。キーボードの上端がナビの上端（確保量から余白 28 を
///   引いた高さ）に届くまでは、入力欄などの下端は動かず（ナビの上）、それより上は
///   キーボードの真上に付いてくる。出す・閉じるの瞬間に入力欄が下がって跳ねることはない
/// - ナビは、キーボードがナビの高さ以上まで出たら外す（それまではキーボードの下に隠れていく）。
///   キーボードが少しでも出ている間は、操作・読み上げの対象にしない
/// - 各画面は **ナビのための余白を自分で足さない**（二重に空く）。
///   `SafeArea` を使わない画面（`TabBarView` など）は `MediaQuery.paddingOf(context).bottom` を
///   スクロール領域の下余白に使う
///
/// 配置: `Scaffold` より **外側** に置く（`Scaffold` の中ではキーボードの `viewInsets` が
/// 取り除かれて見えないため）。
class FcBottomNavLayout extends StatelessWidget {
  const FcBottomNavLayout({
    super.key,
    required this.body,
    required this.bottomNav,
  });

  final Widget body;
  final Widget bottomNav;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final reserved = AppSizes.navReservedOf(context);
    final navHeight = reserved - AppSizes.navContentGap;

    // キーボードに食われた分だけ確保量を減らす（キーボードが出きれば 0）
    final bodyReserve = math.max(reserved - keyboard, 0.0);
    final bodyMedia = bodyReserve <= 0
        ? media
        : media.copyWith(
            padding: media.padding.copyWith(
              bottom: math.max(media.padding.bottom, bodyReserve),
            ),
            viewPadding: media.viewPadding.copyWith(
              bottom: math.max(media.viewPadding.bottom, bodyReserve),
            ),
          );

    return Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(data: bodyMedia, child: body),
        ),
        if (keyboard < navHeight)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: keyboard > 0,
              child: ExcludeSemantics(
                excluding: keyboard > 0,
                child: bottomNav,
              ),
            ),
          ),
      ],
    );
  }
}
