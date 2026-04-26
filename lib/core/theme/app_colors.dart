import 'package:flutter/material.dart';

class AppColors {
  // Primary Blue (Tailwind-like)
  static const Color primary = Color(0xFF2563EB); // 600
  static const Color primary50 = Color(0xFFEFF6FF);
  static const Color primary100 = Color(0xFFDBEAFE);
  static const Color primary200 = Color(0xFFBFDBFE);
  static const Color primary400 = Color(0xFF60A5FA);
  static const Color primary500 = Color(0xFF3B82F6);
  static const Color primary600 = Color(0xFF2563EB);
  static const Color primary700 = Color(0xFF1D4ED8);

  // Slate (Neutral)
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);

  // Accent Colors for Categories
  // Meals (Amber, Blue, Rose, Indigo)
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

  // Success / Emerald
  static const Color emerald50 = Color(0xFFECFDF5);
  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);
  static const Color success = emerald500;

  // Warning / Orange
  static const Color orange50 = Color(0xFFFFF7ED);
  static const Color orange100 = Color(0xFFFFEDD5);
  static const Color orange500 = Color(0xFFF97316);
  static const Color orange600 = Color(0xFFEA580C);
  static const Color orange800 = Color(0xFF9A3412);
  static const Color warning = orange500;

  // Error / Red
  static const Color red500 = Color(0xFFEF4444);
  static const Color red100 = Color(0xFFFEE2E2);
  static const Color error = red500;

  // Purple
  static const Color purple50 = Color(0xFFFAF5FF);
  static const Color purple500 = Color(0xFFA855F7);
  static const Color purple600 = Color(0xFF9333EA);

  // GitHub Grass Colors
  static const Color grassLevel0 = Color(0xFFEBEDF0); // グレー
  static const Color grassLevel1 = Color(0xFF9BE9A8); // 薄い緑
  static const Color grassLevel2 = Color(0xFF39D353); // 中くらいの緑
  static const Color grassLevel3 = Color(0xFF26A641); // 濃い緑

  // Background
  static const Color background = Color(0xFFFAFAFA);
  static const Color cardBackground = Colors.white;

  // Text
  static const Color textPrimary = slate800;
  static const Color textSecondary = slate500;
  static const Color textHint = slate400;

  // ThemeExtension helper
  static AppColorsExtension of(BuildContext context) =>
      AppColorsExtension.of(context);
}

class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  const AppColorsExtension({
    required this.background,
    required this.surface,
    required this.surfaceDim,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.shadow,
    required this.accentIndigo,
    required this.accentIndigoBorder,
    required this.accentPurple,
    required this.accentOrange,
    required this.calendarEmpty,
    required this.sleepStageDeep,
    required this.sleepStageLight,
    required this.sleepStageRem,
    required this.sleepStageAwake,
  });

  final Color background;
  final Color surface;
  final Color surfaceDim;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color shadow;

  // Accent background colors (adapt to dark mode)
  final Color accentIndigo;
  final Color accentIndigoBorder;
  final Color accentPurple;
  final Color accentOrange;
  final Color calendarEmpty;

  // Sleep stage colors
  final Color sleepStageDeep;
  final Color sleepStageLight;
  final Color sleepStageRem;
  final Color sleepStageAwake;

  static const light = AppColorsExtension(
    background: Color(0xFFFAFAFA),
    surface: Colors.white,
    surfaceDim: Color(0xFFF8FAFC), // slate50
    border: Color(0xFFF1F5F9), // slate100
    textPrimary: Color(0xFF1E293B), // slate800
    textSecondary: Color(0xFF64748B), // slate500
    textHint: Color(0xFF94A3B8), // slate400
    shadow: Color(0x0D000000), // black 5%
    accentIndigo: Color(0xFFEEF2FF), // indigo50
    accentIndigoBorder: Color(0xFFE0E7FF), // indigo100
    accentPurple: Color(0xFFFAF5FF), // purple50
    accentOrange: Color(0xFFFFF7ED), // orange50
    calendarEmpty: Color(0xFFE2E8F0), // slate200
    sleepStageDeep: Color(0xFF4338CA), // indigo-700
    sleepStageLight: Color(0xFF818CF8), // indigo-400
    sleepStageRem: Color(0xFF60A5FA), // primary-400
    sleepStageAwake: Color(0xFFE2E8F0), // slate-200
  );

  static const dark = AppColorsExtension(
    background: Color(0xFF0F172A), // slate900
    surface: Color(0xFF1E293B), // slate800
    surfaceDim: Color(0xFF0F172A), // slate900
    border: Color(0xFF334155), // slate700
    textPrimary: Color(0xFFF8FAFC), // slate50
    textSecondary: Color(0xFF94A3B8), // slate400
    textHint: Color(0xFF64748B), // slate500
    shadow: Color(0x33000000), // black 20%
    accentIndigo: Color(0xFF312E81), // indigo900
    accentIndigoBorder: Color(0xFF3730A3), // indigo800
    accentPurple: Color(0xFF3B0764), // purple950
    accentOrange: Color(0xFF431407), // orange950
    calendarEmpty: Color(0xFF334155), // slate700
    sleepStageDeep: Color(0xFF6366F1),
    sleepStageLight: Color(0xFF818CF8),
    sleepStageRem: Color(0xFF60A5FA),
    sleepStageAwake: Color(0xFF475569),
  );

  static AppColorsExtension of(BuildContext context) =>
      Theme.of(context).extension<AppColorsExtension>()!;

  @override
  AppColorsExtension copyWith({
    Color? background,
    Color? surface,
    Color? surfaceDim,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
    Color? shadow,
    Color? accentIndigo,
    Color? accentIndigoBorder,
    Color? accentPurple,
    Color? accentOrange,
    Color? calendarEmpty,
    Color? sleepStageDeep,
    Color? sleepStageLight,
    Color? sleepStageRem,
    Color? sleepStageAwake,
  }) {
    return AppColorsExtension(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      shadow: shadow ?? this.shadow,
      accentIndigo: accentIndigo ?? this.accentIndigo,
      accentIndigoBorder: accentIndigoBorder ?? this.accentIndigoBorder,
      accentPurple: accentPurple ?? this.accentPurple,
      accentOrange: accentOrange ?? this.accentOrange,
      calendarEmpty: calendarEmpty ?? this.calendarEmpty,
      sleepStageDeep: sleepStageDeep ?? this.sleepStageDeep,
      sleepStageLight: sleepStageLight ?? this.sleepStageLight,
      sleepStageRem: sleepStageRem ?? this.sleepStageRem,
      sleepStageAwake: sleepStageAwake ?? this.sleepStageAwake,
    );
  }

  @override
  AppColorsExtension lerp(AppColorsExtension? other, double t) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceDim: Color.lerp(surfaceDim, other.surfaceDim, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      accentIndigo: Color.lerp(accentIndigo, other.accentIndigo, t)!,
      accentIndigoBorder:
          Color.lerp(accentIndigoBorder, other.accentIndigoBorder, t)!,
      accentPurple: Color.lerp(accentPurple, other.accentPurple, t)!,
      accentOrange: Color.lerp(accentOrange, other.accentOrange, t)!,
      calendarEmpty: Color.lerp(calendarEmpty, other.calendarEmpty, t)!,
      sleepStageDeep:
          Color.lerp(sleepStageDeep, other.sleepStageDeep, t)!,
      sleepStageLight:
          Color.lerp(sleepStageLight, other.sleepStageLight, t)!,
      sleepStageRem: Color.lerp(sleepStageRem, other.sleepStageRem, t)!,
      sleepStageAwake:
          Color.lerp(sleepStageAwake, other.sleepStageAwake, t)!,
    );
  }
}
