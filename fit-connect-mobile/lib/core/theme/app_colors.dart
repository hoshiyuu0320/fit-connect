import 'package:flutter/material.dart';

/// 色の入口。
///
/// - **画面・部品は `AppColors.of(context)`（[AppColorsExtension]）から色を取る**。
///   ライト/ダークの切り替えはここに集約している。
/// - 下の静的定数（`AppColors.primary600` など）は **旧デザインとの互換用**。
///   認証・オンボーディングなど、再デザインの対象外の画面が壊れないよう
///   名前を残して値を新しい配色（青緑・Apple 系の中立グレー）へ寄せてある。
///   **再デザインした画面では静的定数を使わない**（ダークモードに追従しないため）。
class AppColors {
  // ---------------------------------------------------------------------
  // Primary（旧: 青 → 新: 青緑）。再デザインの accent / actionFill に対応
  // ---------------------------------------------------------------------
  static const Color primary = Color(0xFF17685D); // = accent(light)
  static const Color primary50 = Color(0xFFE6F1EF);
  static const Color primary100 = Color(0xFFCFE3DF);
  static const Color primary200 = Color(0xFFA9CFC8);
  static const Color primary400 = Color(0xFF78D6B5); // = accent(dark)
  static const Color primary500 =
      Color(0xFF1D7469); // = recordButtonBorder(light)
  static const Color primary600 = Color(0xFF17685D); // = accent(light)
  static const Color primary700 = Color(0xFF115248);

  // ---------------------------------------------------------------------
  // Neutral（旧: Slate → 新: 中立グレー）
  // ---------------------------------------------------------------------
  static const Color slate50 = Color(0xFFF7F7FA);
  static const Color slate100 = Color(0xFFF2F2F7); // = background(light)
  static const Color slate200 = Color(0xFFE2E2E7); // = separator(light)
  static const Color slate300 = Color(0xFFC9C9CF);
  static const Color slate400 = Color(0xFF9A9AA2);
  static const Color slate500 = Color(0xFF6C6C73); // = textSecondary(light)
  static const Color slate600 = Color(0xFF55555B);
  static const Color slate700 = Color(0xFF3A3A3F);
  static const Color slate800 = Color(0xFF232326);
  static const Color slate900 = Color(0xFF171719); // = textPrimary(light)

  // ---------------------------------------------------------------------
  // 旧カテゴリ色。名前だけ残している。
  // **再デザイン画面では使わない**（カテゴリごとに色を割り振らない方針。
  // アイコンと言葉で区別する）。未デザインの画面が壊れないための互換。
  // ---------------------------------------------------------------------
  static const Color amber100 = Color(0xFFFEF3C7);
  static const Color amber300 = Color(0xFFFCD34D);
  static const Color amber700 = Color(0xFFB45309);
  static const Color amber800 = Color(0xFF92400E);

  static const Color rose100 = Color(0xFFFFE4E6);
  static const Color rose800 = Color(0xFF9F1239);

  static const Color indigo50 = Color(0xFFEEF2FF);
  static const Color indigo100 = Color(0xFFE0E7FF);
  static const Color indigo600 = Color(0xFF4F46E5);
  static const Color indigo800 = Color(0xFF3730A3);

  static const Color emerald50 = Color(0xFFECFDF5);
  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);

  static const Color orange50 = Color(0xFFFFF7ED);
  static const Color orange100 = Color(0xFFFFEDD5);
  static const Color orange500 = Color(0xFFF97316);
  static const Color orange600 = Color(0xFFEA580C);
  static const Color orange800 = Color(0xFF9A3412);

  static const Color red500 = Color(0xFFEF4444);
  static const Color red100 = Color(0xFFFEE2E2);

  static const Color purple50 = Color(0xFFFAF5FF);
  static const Color purple500 = Color(0xFFA855F7);
  static const Color purple600 = Color(0xFF9333EA);

  // ---------------------------------------------------------------------
  // 状態色（新配色のライト値）。文言とアイコンを併用すること
  // ---------------------------------------------------------------------
  static const Color success = Color(0xFF1F7A36);
  static const Color warning = Color(0xFF8A5300);
  static const Color error = Color(0xFFC4271D);

  // PFC Macronutrient Colors（栄養トレンド用。再デザイン画面では使わない）
  static const Color pfcProtein = Color(0xFFA8D8D3);
  static const Color pfcFat = Color(0xFFFBD9A0);
  static const Color pfcCarbs = Color(0xFFEFB7C8);
  static const Color weightLine = slate900; // 後方互換のため残置

  // GitHub 風の草カラー（旧: 食事カレンダー）。再デザイン画面では使わない
  // （記録した日に単色の印を付ける方針）
  static const Color grassLevel0 = Color(0xFFEBEDF0);
  static const Color grassLevel1 = Color(0xFF9BE9A8);
  static const Color grassLevel2 = Color(0xFF39D353);
  static const Color grassLevel3 = Color(0xFF26A641);

  // ---------------------------------------------------------------------
  // 背景・文字（ライト値）。ダーク対応が必要な箇所では of(context) を使う
  // ---------------------------------------------------------------------
  static const Color background = Color(0xFFF2F2F7);
  static const Color cardBackground = Colors.white;

  static const Color textPrimary = slate900;
  static const Color textSecondary = slate500;
  static const Color textHint = slate500;

  /// ThemeExtension の取得ヘルパー（画面・部品はここから色を取る）
  static AppColorsExtension of(BuildContext context) =>
      AppColorsExtension.of(context);
}

/// ライト/ダークで切り替わる色トークン。正本は Claude Design の
/// `tokens/colors.css`（Flutter 側の参照表は docs/tasks/2026-10-04-mobile-redesign-spec.md §3）。
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  const AppColorsExtension({
    // --- 再デザインのトークン ---
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.separator,
    required this.accent,
    required this.actionFill,
    required this.onAction,
    required this.navigationSurface,
    required this.navigationBorder,
    required this.recordButtonBorder,
    required this.skeleton,
    required this.error,
    required this.errorSurface,
    required this.warning,
    required this.warningSurface,
    required this.success,
    required this.successSurface,
    // --- 旧名（互換。値は新配色へ寄せてある） ---
    required this.surfaceDim,
    required this.border,
    required this.textHint,
    required this.shadow,
    required this.accentIndigo,
    required this.accentIndigoBorder,
    required this.accentPurple,
    required this.accentOrange,
    required this.calendarEmpty,
    required this.primaryTint,
    required this.primaryTintForeground,
    required this.successTint,
    required this.dangerTint,
    required this.sleepStageDeep,
    required this.sleepStageLight,
    required this.sleepStageRem,
    required this.sleepStageAwake,
  });

  // ===== 再デザインのトークン =====

  /// ページ背景（ライト #F2F2F7 / ダーク #000000）
  final Color background;

  /// カード・シートの面。**不透明**（ライト #FFFFFF / ダーク #1C1C1E）
  final Color surface;

  /// 入力欄・選択中の面・チップなど、surface の上に重ねる面
  final Color surfaceSecondary;

  final Color textPrimary;
  final Color textSecondary;

  /// 区切り線・枠
  final Color separator;

  /// 強調色（アイコン・リンク・選択中の文字）。青緑
  final Color accent;

  /// 主要ボタンの塗り（ダークは accent より暗い青緑。文字は [onAction] の白）
  final Color actionFill;
  final Color onAction;

  /// 下部ナビの面（半透明）。ぼかしの上に重ねる
  final Color navigationSurface;
  final Color navigationBorder;

  /// 「記録する」ボタンの枠
  final Color recordButtonBorder;

  /// スケルトン（読込中）の面
  final Color skeleton;

  /// 状態色。必ず文言・アイコンを併用する。accent を状態の意味に兼用しない
  final Color error;
  final Color errorSurface;
  final Color warning;
  final Color warningSurface;
  final Color success;
  final Color successSurface;

  // ===== 旧名（互換） =====

  /// 旧: 淡いグレー面 → [surfaceSecondary] と同値
  final Color surfaceDim;

  /// 旧: 罫線 → [separator] と同値
  final Color border;

  /// 旧: ヒント文字 → [textSecondary] と同値
  final Color textHint;

  final Color shadow;

  /// 旧カテゴリ背景。**再デザイン画面では使わない**。値は中立グレーに寄せてある
  final Color accentIndigo;
  final Color accentIndigoBorder;
  final Color accentPurple;
  final Color accentOrange;

  /// 旧: カレンダーの空セル → [separator] 相当
  final Color calendarEmpty;

  /// 旧: 淡青カード → 青緑の淡い面。上の文字は textPrimary のまま読める
  final Color primaryTint;

  /// 旧: primaryTint 上のアイコン・強調色 → [accent] と同値
  final Color primaryTintForeground;

  /// 旧: 淡緑カード → [successSurface] と同値
  final Color successTint;

  /// 旧: 淡赤カード → [errorSurface] と同値
  final Color dangerTint;

  // 睡眠ステージ（睡眠グラフ用。睡眠画面の担当が必要に応じて調整する）
  final Color sleepStageDeep;
  final Color sleepStageLight;
  final Color sleepStageRem;
  final Color sleepStageAwake;

  static const light = AppColorsExtension(
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFEDEDF2),
    textPrimary: Color(0xFF171719),
    textSecondary: Color(0xFF6C6C73),
    separator: Color(0xFFE2E2E7),
    accent: Color(0xFF17685D),
    actionFill: Color(0xFF17685D),
    onAction: Color(0xFFFFFFFF),
    navigationSurface: Color(0xF2FCFCFD), // #FCFCFD α0xF2
    navigationBorder: Color(0xFFFFFFFF),
    recordButtonBorder: Color(0xFF1D7469),
    skeleton: Color(0xFFE6E6EB),
    error: Color(0xFFC4271D),
    errorSurface: Color(0xFFFCEDEC),
    warning: Color(0xFF8A5300),
    warningSurface: Color(0xFFFBF1E0),
    success: Color(0xFF1F7A36),
    successSurface: Color(0xFFE8F4EB),
    // 旧名
    surfaceDim: Color(0xFFEDEDF2), // = surfaceSecondary
    border: Color(0xFFE2E2E7), // = separator
    textHint: Color(0xFF6C6C73), // = textSecondary
    shadow: Color(0x0D000000), // black 5%
    accentIndigo: Color(0xFFEDEDF2),
    accentIndigoBorder: Color(0xFFE2E2E7),
    accentPurple: Color(0xFFEDEDF2),
    accentOrange: Color(0xFFEDEDF2),
    calendarEmpty: Color(0xFFE2E2E7),
    primaryTint: Color(0xFFE6F1EF),
    primaryTintForeground: Color(0xFF17685D), // = accent
    successTint: Color(0xFFE8F4EB), // = successSurface
    dangerTint: Color(0xFFFCEDEC), // = errorSurface
    sleepStageDeep: Color(0xFF4338CA),
    sleepStageLight: Color(0xFF818CF8),
    sleepStageRem: Color(0xFF60A5FA),
    sleepStageAwake: Color(0xFFE2E2E7),
  );

  static const dark = AppColorsExtension(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceSecondary: Color(0xFF2B2B30),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFABABB3),
    separator: Color(0xFF36363A),
    accent: Color(0xFF78D6B5),
    actionFill: Color(0xFF286353),
    onAction: Color(0xFFFFFFFF),
    navigationSurface: Color(0xF52B2B2E), // #2B2B2E α0xF5
    navigationBorder: Color(0xFF48484C),
    recordButtonBorder: Color(0xFF3B7B69),
    skeleton: Color(0xFF2B2B30),
    error: Color(0xFFFF7A70),
    errorSurface: Color(0xFF3A1C1A),
    warning: Color(0xFFFFC266),
    warningSurface: Color(0xFF3A2C14),
    success: Color(0xFF6FD68A),
    successSurface: Color(0xFF17301E),
    // 旧名
    surfaceDim: Color(0xFF2B2B30), // = surfaceSecondary
    border: Color(0xFF36363A), // = separator
    textHint: Color(0xFFABABB3), // = textSecondary
    shadow: Color(0x33000000), // black 20%
    accentIndigo: Color(0xFF2B2B30),
    accentIndigoBorder: Color(0xFF36363A),
    accentPurple: Color(0xFF2B2B30),
    accentOrange: Color(0xFF2B2B30),
    calendarEmpty: Color(0xFF36363A),
    primaryTint: Color(0xFF1B3A33),
    primaryTintForeground: Color(0xFF78D6B5), // = accent
    successTint: Color(0xFF17301E), // = successSurface
    dangerTint: Color(0xFF3A1C1A), // = errorSurface
    sleepStageDeep: Color(0xFF6366F1),
    sleepStageLight: Color(0xFF818CF8),
    sleepStageRem: Color(0xFF60A5FA),
    sleepStageAwake: Color(0xFF48484C),
  );

  static AppColorsExtension of(BuildContext context) =>
      Theme.of(context).extension<AppColorsExtension>()!;

  @override
  AppColorsExtension copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSecondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? separator,
    Color? accent,
    Color? actionFill,
    Color? onAction,
    Color? navigationSurface,
    Color? navigationBorder,
    Color? recordButtonBorder,
    Color? skeleton,
    Color? error,
    Color? errorSurface,
    Color? warning,
    Color? warningSurface,
    Color? success,
    Color? successSurface,
    Color? surfaceDim,
    Color? border,
    Color? textHint,
    Color? shadow,
    Color? accentIndigo,
    Color? accentIndigoBorder,
    Color? accentPurple,
    Color? accentOrange,
    Color? calendarEmpty,
    Color? primaryTint,
    Color? primaryTintForeground,
    Color? successTint,
    Color? dangerTint,
    Color? sleepStageDeep,
    Color? sleepStageLight,
    Color? sleepStageRem,
    Color? sleepStageAwake,
  }) {
    return AppColorsExtension(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      separator: separator ?? this.separator,
      accent: accent ?? this.accent,
      actionFill: actionFill ?? this.actionFill,
      onAction: onAction ?? this.onAction,
      navigationSurface: navigationSurface ?? this.navigationSurface,
      navigationBorder: navigationBorder ?? this.navigationBorder,
      recordButtonBorder: recordButtonBorder ?? this.recordButtonBorder,
      skeleton: skeleton ?? this.skeleton,
      error: error ?? this.error,
      errorSurface: errorSurface ?? this.errorSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      border: border ?? this.border,
      textHint: textHint ?? this.textHint,
      shadow: shadow ?? this.shadow,
      accentIndigo: accentIndigo ?? this.accentIndigo,
      accentIndigoBorder: accentIndigoBorder ?? this.accentIndigoBorder,
      accentPurple: accentPurple ?? this.accentPurple,
      accentOrange: accentOrange ?? this.accentOrange,
      calendarEmpty: calendarEmpty ?? this.calendarEmpty,
      primaryTint: primaryTint ?? this.primaryTint,
      primaryTintForeground:
          primaryTintForeground ?? this.primaryTintForeground,
      successTint: successTint ?? this.successTint,
      dangerTint: dangerTint ?? this.dangerTint,
      sleepStageDeep: sleepStageDeep ?? this.sleepStageDeep,
      sleepStageLight: sleepStageLight ?? this.sleepStageLight,
      sleepStageRem: sleepStageRem ?? this.sleepStageRem,
      sleepStageAwake: sleepStageAwake ?? this.sleepStageAwake,
    );
  }

  @override
  AppColorsExtension lerp(AppColorsExtension? other, double t) {
    if (other is! AppColorsExtension) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsExtension(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceSecondary: l(surfaceSecondary, other.surfaceSecondary),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      separator: l(separator, other.separator),
      accent: l(accent, other.accent),
      actionFill: l(actionFill, other.actionFill),
      onAction: l(onAction, other.onAction),
      navigationSurface: l(navigationSurface, other.navigationSurface),
      navigationBorder: l(navigationBorder, other.navigationBorder),
      recordButtonBorder: l(recordButtonBorder, other.recordButtonBorder),
      skeleton: l(skeleton, other.skeleton),
      error: l(error, other.error),
      errorSurface: l(errorSurface, other.errorSurface),
      warning: l(warning, other.warning),
      warningSurface: l(warningSurface, other.warningSurface),
      success: l(success, other.success),
      successSurface: l(successSurface, other.successSurface),
      surfaceDim: l(surfaceDim, other.surfaceDim),
      border: l(border, other.border),
      textHint: l(textHint, other.textHint),
      shadow: l(shadow, other.shadow),
      accentIndigo: l(accentIndigo, other.accentIndigo),
      accentIndigoBorder: l(accentIndigoBorder, other.accentIndigoBorder),
      accentPurple: l(accentPurple, other.accentPurple),
      accentOrange: l(accentOrange, other.accentOrange),
      calendarEmpty: l(calendarEmpty, other.calendarEmpty),
      primaryTint: l(primaryTint, other.primaryTint),
      primaryTintForeground:
          l(primaryTintForeground, other.primaryTintForeground),
      successTint: l(successTint, other.successTint),
      dangerTint: l(dangerTint, other.dangerTint),
      sleepStageDeep: l(sleepStageDeep, other.sleepStageDeep),
      sleepStageLight: l(sleepStageLight, other.sleepStageLight),
      sleepStageRem: l(sleepStageRem, other.sleepStageRem),
      sleepStageAwake: l(sleepStageAwake, other.sleepStageAwake),
    );
  }
}
