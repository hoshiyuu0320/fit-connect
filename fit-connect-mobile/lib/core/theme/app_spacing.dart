import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 余白（論理 px。390px 基準）。正本は Claude Design の `tokens/spacing.css`。
///
/// 間隔スケール: 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48。
/// 画面・部品は数値を直書きせず、ここの定数を使う。
class AppSpacing {
  const AppSpacing._();

  // --- 間隔スケール ---
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  // --- ページ ---

  /// 画面の左右余白（標準）
  static const double pageHorizontal = 20;

  /// 画面の左右余白（狭い画面）
  static const double pageHorizontalCompact = 16;

  /// 「狭い画面」とみなす幅（これ未満で [pageHorizontalCompact]）
  static const double compactWidth = 360;

  /// カードとカードの間
  static const double cardGap = 16;

  /// 大見出し（FcPageHeading）の後ろ
  static const double afterHeading = 24;

  // --- カード内余白 ---

  /// 標準カード
  static const double cardPadding = 20;

  /// コーチカード
  static const double coachCardPadding = 17;

  /// 健康カード（2列）の上下
  static const double healthCardVertical = 16;

  /// 健康カード（2列）の左右
  static const double healthCardHorizontal = 14;

  /// 健康カード 2 列の間隔
  static const double healthCardGap = 12;

  /// 画面幅に応じた左右余白（360 未満で 16、それ以外で 20）
  static double pageHorizontalOf(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width < compactWidth ? pageHorizontalCompact : pageHorizontal;
  }
}

/// 角丸。
class AppRadius {
  const AppRadius._();

  /// カード
  static const double card = 23;

  /// 入力欄
  static const double input = 12;

  /// チャット内の記録カード
  static const double chatRecordCard = 20;

  /// 主要ボタン（block）
  static const double button = 24;

  /// 下部ナビの外形
  static const double navigation = 40;

  /// 下部ナビの選択部
  static const double navigationSelected = 28;

  /// セグメント
  static const double segment = 10;

  /// 円形（50%）に相当。BorderRadius ではなく BoxShape.circle を使うこと
  static const double circle = 999;

  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get inputRadius => BorderRadius.circular(input);
}

/// サイズ。
class AppSizes {
  const AppSizes._();

  /// タッチ領域の最小（縦横とも）
  static const double minTouch = 44;

  /// 主要送信ボタン（FcButton.block）の高さ
  static const double primaryButtonHeight = 48;

  /// ピルボタン（FcButton.pill）の高さ
  static const double pillButtonHeight = 43;

  /// セグメントの高さ
  static const double segmentHeight = 45;

  /// アイコン
  static const double icon = 20;

  /// アバター（標準）
  static const double avatar = 39;

  /// アバター（プロフィール）
  static const double avatarProfile = 43;

  // --- 下部ナビ（正本 BottomNav: footer 余白 上14 / 左右17 / 下15、nav 余白 5・枠 1） ---

  /// ナビの各操作の高さ
  static const double navItemHeight = 52;

  /// ナビのカプセルの内側余白（枠線の内側）
  static const double navPadding = 5;

  /// ナビのカプセルの枠線の太さ（navigationBorder）
  static const double navBorderWidth = 1;

  /// ナビの操作どうしの間隔
  static const double navItemGap = 2;

  /// ナビのカプセルの高さ（操作 52 + (余白 5 + 枠 1) × 2 = 64）
  static const double navCapsuleHeight =
      navItemHeight + (navPadding + navBorderWidth) * 2;

  /// ナビ（footer）の左右余白。画面の左右余白（20 / 16）とは別に 17 固定
  static const double navHorizontal = 17;

  /// ナビ（footer）の上余白
  static const double navTopPadding = 14;

  /// ナビの下端から画面下端までの距離（最小。footer の下余白 15）
  static const double navBottomOffset = 15;

  /// 下端の安全領域のうち、ナビが食い込んでよい量（ホームインジケーター 34 → 下端 15）
  static const double navSafeAreaOverlap = 19;

  /// 本文とナビの間の余白
  static const double navContentGap = 28;

  /// 参照値: ナビの高さ（上余白 14 + カプセル 64 + 下端 15 = 93）
  static const double navReferenceHeight =
      navTopPadding + navCapsuleHeight + navBottomOffset;

  /// 画面下端から本文が空けるべき距離（参照値）: 93 + 28 = 121
  static const double navReservedReference = navReferenceHeight + navContentGap;

  /// 実機の安全領域を考慮したナビ下端の位置（画面下端から）
  static double navBottomOffsetOf(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return math.max(navBottomOffset, safeBottom - navSafeAreaOverlap);
  }

  /// 画面下端から本文が空けるべき距離。上余白 + カプセル + 下端位置 + 余白
  static double navReservedOf(BuildContext context) =>
      navTopPadding +
      navCapsuleHeight +
      navBottomOffsetOf(context) +
      navContentGap;
}

/// 動き。
class AppMotion {
  const AppMotion._();

  /// 押下の縮小アニメーション
  static const Duration press = Duration(milliseconds: 120);
  static const double pressScale = 0.98;

  /// 選択状態の切り替え
  static const Duration select = Duration(milliseconds: 180);

  /// 「動きを減らす」設定が有効か
  static bool reduceOf(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
