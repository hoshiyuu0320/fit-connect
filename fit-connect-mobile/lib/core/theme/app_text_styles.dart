import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// 文字の階層（390px 基準の論理 px）。正本は Claude Design の `tokens/typography.css`。
///
/// - 色は `AppColors.of(context)`（ThemeExtension）から解決するので、ダークに自動追従する。
///   別の色にしたいときは `.copyWith(color: ...)` で上書きする。
/// - フォントは **システム標準**（iOS は San Francisco / 日本語は Hiragino Sans）。
///   `fontFamily` は指定しない。同梱もしない。
/// - サイズは固定値だが、`Text` は OS の文字サイズ設定（`TextScaler`）に追従して拡大する。
///   **拡大しても縮めない**。固定高さ・固定行数にせず、`Wrap` や縦並びで積み直すこと。
/// - 数値（`num*`）は桁幅を揃える `FontFeature.tabularFigures()` 付き。
class AppTextStyles {
  const AppTextStyles._();

  /// 桁幅を揃える（数値表示用）
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static TextStyle _style(
    BuildContext context, {
    required double size,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    Color? color,
    bool secondary = false,
    bool tabular = false,
  }) {
    final colors = AppColors.of(context);
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
      // 日本語の行間を CSS と同じく上下均等に配る
      leadingDistribution: TextLeadingDistribution.even,
      color: color ?? (secondary ? colors.textSecondary : colors.textPrimary),
      fontFeatures: tabular ? tabularFigures : null,
    );
  }

  /// アイブロウ（ページ見出しの上の小さな文字）。13 / 400 / 字間なし / 行高 1.5 / textSecondary
  ///
  /// 正本 `PageHeading` の eyebrow（`secondary-size` = 13）。12px・字間 1.6 のブランド表記は [brand]。
  static TextStyle eyebrow(BuildContext context) => _style(
        context,
        size: 13,
        height: 1.5,
        secondary: true,
      );

  /// ブランド表記（正本 `AppHeader` の "FIT CONNECT"）。12 / 500 / 字間 1.6 / textSecondary。
  /// ページ見出しの eyebrow とは別物（[eyebrow] は 13・字間なし）
  static TextStyle brand(BuildContext context) => _style(
        context,
        size: 12,
        weight: FontWeight.w500,
        letterSpacing: 1.6,
        height: 1.5,
        secondary: true,
      );

  /// ページ見出し。32 / 500 / 字間 -1 / 行高 1.2
  static TextStyle pageHeading(BuildContext context) => _style(
        context,
        size: 32,
        weight: FontWeight.w500,
        letterSpacing: -1,
        height: 1.2,
      );

  /// セクション見出し。20 / 500 / 行高 1.3
  static TextStyle sectionHeading(BuildContext context) => _style(
        context,
        size: 20,
        weight: FontWeight.w500,
        height: 1.3,
      );

  /// プラン名。26 / 500 / 字間 -0.6 / 行高 1.3
  static TextStyle planName(BuildContext context) => _style(
        context,
        size: 26,
        weight: FontWeight.w500,
        letterSpacing: -0.6,
        height: 1.3,
      );

  /// コーチ名（コーチ画面）。25 / 500 / 字間 -1 / 行高 1.2（正本 `CoachHeader` は letterSpacing -1）
  static TextStyle coachName(BuildContext context) => _style(
        context,
        size: 25,
        weight: FontWeight.w500,
        letterSpacing: -1,
        height: 1.2,
      );

  /// 種目名。17 / 500 / 行高 1.5
  static TextStyle exerciseName(BuildContext context) => _style(
        context,
        size: 17,
        weight: FontWeight.w500,
        height: 1.5,
      );

  /// 本文。16 / 400 / 行高 1.5
  static TextStyle body(BuildContext context) => _style(
        context,
        size: 16,
        height: 1.5,
      );

  /// 操作ラベル（ボタンの文字）。15 / 500
  static TextStyle actionLabel(BuildContext context) => _style(
        context,
        size: 15,
        weight: FontWeight.w500,
      );

  /// ラベル。14 / 400
  static TextStyle label(BuildContext context) => _style(context, size: 14);

  /// 補足・日時。13 / 400 / 行高 1.5 / textSecondary
  static TextStyle supplement(BuildContext context) => _style(
        context,
        size: 13,
        height: 1.5,
        secondary: true,
      );

  /// キャプション。12 / 400 / 行高 1.5 / textSecondary
  static TextStyle caption(BuildContext context) => _style(
        context,
        size: 12,
        height: 1.5,
        secondary: true,
      );

  /// ナビラベル。11 / 400（選択中 500）/ 行高 1.5。色は呼び出し側で指定する
  static TextStyle navLabel(BuildContext context, {bool selected = false}) =>
      _style(
        context,
        size: 11,
        weight: selected ? FontWeight.w500 : FontWeight.w400,
        height: 1.5,
      );

  /// 数値（ホーム）。32 / 500 / 字間 -1.1 / 行高 1.05 / tabular（`tokens/typography.css` の値。
  /// 画面の見た目の正本 `parts.js` の `Num` は 字間 -1 / 行高 1.1 で、`FcNum` は [metric] に従う）
  static TextStyle numHome(BuildContext context) => _style(
        context,
        size: 32,
        weight: FontWeight.w500,
        letterSpacing: -1.1,
        height: 1.05,
        tabular: true,
      );

  /// 数値（振り返り）。34 / 500 / 字間 -1 / 行高 1.0 / tabular
  static TextStyle numReview(BuildContext context) => _style(
        context,
        size: 34,
        weight: FontWeight.w500,
        letterSpacing: -1,
        height: 1.0,
        tabular: true,
      );

  /// 任意サイズの数値（正本 `parts.js` の `Num`）。[size] / 500 / 行高 1.1 / tabular。
  /// 字間は [size] が 30 以上なら -1、それ未満なら -0.6。`FcNum` / `FcStat` がこれを使う
  /// （ホーム 32・振り返り 34・指標 26・小 20）
  static TextStyle metric(BuildContext context, {required double size}) =>
      _style(
        context,
        size: size,
        weight: FontWeight.w500,
        letterSpacing: size >= 30 ? -1 : -0.6,
        height: 1.1,
        tabular: true,
      );

  /// 数値の単位。13 / 400 / 字間 0 / textSecondary。**単位は常に表示する**
  static TextStyle numUnit(BuildContext context) => _style(
        context,
        size: 13,
        letterSpacing: 0,
        secondary: true,
      );

  /// 本文サイズ（16）の数値。入力欄など、本文の中に数値を置くとき
  static TextStyle bodyNumber(BuildContext context) => _style(
        context,
        size: 16,
        height: 1.5,
        tabular: true,
      );
}
