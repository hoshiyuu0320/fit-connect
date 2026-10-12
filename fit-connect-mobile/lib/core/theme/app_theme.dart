import 'package:flutter/cupertino.dart' show CupertinoThemeData;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// アプリ全体の Material 3 テーマ。
///
/// 配色は [AppColorsExtension]（ライト/ダーク）から組む。`ColorScheme.fromSeed` は使わない。
/// - scaffold 背景 = background、カードは影・枠線なし（角丸 23）、入力は surface の面 + 1px separator の枠・角丸 12
///   （正本 `TextField.jsx`。`FcTextField` と同じ見た目）
/// - 主要ボタンの塗りは `colorScheme.primary`（= accent）ではなく actionFill
/// - フォントはシステム標準のまま（`fontFamily` を指定しない）
class AppTheme {
  const AppTheme._();

  /// SnackBar の面（ライト）。ダーク配色の surfaceSecondary と同じ暗い中立
  static const Color _snackBarSurfaceLight = Color(0xFF2B2B30);

  /// SnackBar の面（ダーク）。地（黒）・カード（#1C1C1E）より明るい中立
  static const Color _snackBarSurfaceDark = Color(0xFF48484C);

  /// SnackBar の操作の文字。暗い面の上で読める（ダーク配色の accent）
  static const Color _snackBarAction = Color(0xFF78D6B5);

  static ThemeData get lightTheme =>
      _build(AppColorsExtension.light, Brightness.light);

  static ThemeData get darkTheme =>
      _build(AppColorsExtension.dark, Brightness.dark);

  static ColorScheme _colorScheme(AppColorsExtension c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ColorScheme(
      brightness: brightness,
      primary: c.accent,
      // accent の面に載せる文字。ライトは白、ダークは濃い青緑
      onPrimary: isDark ? const Color(0xFF06241D) : c.onAction,
      primaryContainer: c.primaryTint,
      onPrimaryContainer: c.accent,
      secondary: c.accent,
      onSecondary: isDark ? const Color(0xFF06241D) : c.onAction,
      secondaryContainer: c.surfaceSecondary,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.accent,
      onTertiary: isDark ? const Color(0xFF06241D) : c.onAction,
      tertiaryContainer: c.surfaceSecondary,
      onTertiaryContainer: c.textPrimary,
      error: c.error,
      onError: isDark ? const Color(0xFF3A0B07) : Colors.white,
      errorContainer: c.errorSurface,
      onErrorContainer: c.error,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceSecondary,
      surfaceContainerHighest: c.surfaceSecondary,
      surfaceDim: c.background,
      surfaceBright: c.surface,
      outline: c.textSecondary,
      outlineVariant: c.separator,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.background,
      inversePrimary: isDark ? AppColors.primary600 : AppColors.primary400,
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _build(AppColorsExtension c, Brightness brightness) {
    final scheme = _colorScheme(c, brightness);
    final isDark = brightness == Brightness.dark;

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
    );
    final inputRadius = BorderRadius.circular(AppRadius.input);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: color, width: width),
        );

    const buttonTextStyle =
        TextStyle(fontSize: 15, fontWeight: FontWeight.w500);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[c],
      scaffoldBackgroundColor: c.background,
      canvasColor: c.surface,
      cardColor: c.surface,
      dividerColor: c.separator,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: c.accent,
        scaffoldBackgroundColor: c.background,
        barBackgroundColor: c.surface,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        // title の文字は `appBarTheme.titleTextStyle` を **設定しない**（設定すると色まで固定され、
        // 画面側の `AppBar(foregroundColor: ...)` が title に効かなくなる）。サイズ・太さは下の
        // `textTheme.titleLarge`（AppBar の既定の title）で持ち、色は foregroundColor に任せる
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
      // 旧 BottomNavigationBar を使う箇所の互換（本体の下部ナビは FcBottomNav）
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.accent,
        unselectedItemColor: c.textSecondary,
      ),
      // カードに影・枠線を付けない。角丸 23
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
      ),
      dividerTheme: DividerThemeData(color: c.separator, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
      ),
      iconTheme: IconThemeData(color: c.textPrimary),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        // オン = actionFill、オフ = separator（正本 `Toggle`。`FcToggle` と同じ）
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.actionFill
              : c.separator,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.actionFill : null,
        ),
        checkColor: WidgetStatePropertyAll(c.onAction),
        side: BorderSide(color: c.textSecondary, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.actionFill
              : c.textSecondary,
        ),
      ),
      // 入力欄の既定の枠: 1px の枠（通常 separator、フォーカス accent、エラー error）・角丸 12・内側余白 12（+ 枠 1）。
      // - 枠は状態別の [WidgetStateInputBorder] を `border` だけに設定する。`enabledBorder` などの
      //   状態別の枠は **設定しない**: Flutter は状態別の枠を `border` より先に使うため、設定すると
      //   画面側の `border: InputBorder.none`（自前の枠付きコンテナに入れた入力欄）が打ち消される
      // - `filled` は false のまま（`fillColor` だけ surface に）。面は `filled: true` を渡した入力欄
      //   （`FcTextField` など）だけに付く。自前の面の上に置く旧画面で二重にならない
      inputDecorationTheme: InputDecorationTheme(
        fillColor: c.surface,
        contentPadding: const EdgeInsets.all(13),
        hintStyle: TextStyle(color: c.textSecondary),
        labelStyle: TextStyle(color: c.textSecondary),
        floatingLabelStyle: TextStyle(color: c.accent),
        helperStyle: TextStyle(color: c.textSecondary),
        errorStyle: TextStyle(color: c.error),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        border: WidgetStateInputBorder.resolveWith((states) {
          final focused = states.contains(WidgetState.focused);
          if (states.contains(WidgetState.error)) {
            return inputBorder(c.error, focused ? 1.5 : 1);
          }
          if (focused) return inputBorder(c.accent, 1.5);
          return inputBorder(c.separator);
        }),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.25),
        selectionHandleColor: c.accent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.actionFill,
          foregroundColor: c.onAction,
          // 無効 = 通常の面（actionFill）のまま 40%。文字は onAction のまま
          // （surfaceSecondary 系にすると面が地に溶けて、白いスピナーなどが見えなくなる）
          disabledBackgroundColor: c.actionFill.withValues(alpha: 0.4),
          disabledForegroundColor: c.onAction,
          minimumSize: const Size(64, AppSizes.primaryButtonHeight),
          shape: buttonShape,
          textStyle: buttonTextStyle,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.actionFill,
          foregroundColor: c.onAction,
          disabledBackgroundColor: c.actionFill.withValues(alpha: 0.4),
          disabledForegroundColor: c.onAction,
          minimumSize: const Size(64, AppSizes.primaryButtonHeight),
          shape: buttonShape,
          textStyle: buttonTextStyle,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.accent,
          disabledForegroundColor: c.accent.withValues(alpha: 0.4),
          minimumSize: const Size(64, AppSizes.primaryButtonHeight),
          side: BorderSide(color: c.separator),
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          disabledForegroundColor: c.accent.withValues(alpha: 0.4),
          minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
          textStyle: buttonTextStyle,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
        ),
      ),
      // 正本 `Chips`: 選択中 = surface の面 + accent の文字（500）、未選択 = 面なし + textSecondary
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: c.surface,
        disabledColor: Colors.transparent,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        secondaryLabelStyle: TextStyle(
          color: c.accent,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        checkmarkColor: c.accent,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: cardShape,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
        contentTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: c.surface,
        headerForegroundColor: c.textPrimary,
        dividerColor: c.separator,
        shape: cardShape,
        todayBorder: BorderSide(color: c.accent),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: c.surface,
        dialBackgroundColor: c.surfaceSecondary,
        hourMinuteColor: c.surfaceSecondary,
        dayPeriodColor: c.surfaceSecondary,
        shape: cardShape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: inputRadius),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.accent,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.accent,
        dividerColor: c.separator,
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceSecondary,
        circularTrackColor: Colors.transparent,
      ),
      // どの背景の上でも読める: 面は暗い中立（ライト #2B2B30 / ダーク #48484C。ダークの地 #000000・surface と
      // 見分けがつく）、文字は白固定。画面側が `backgroundColor` を指定しなくてよい。
      // 浮かせて表示する（固定だと `padding.bottom` ぶんの高い帯が下部ナビの裏に出る）。
      // `FcBottomNavLayout` が `viewPadding` も加算するので、ナビの上に出る
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? _snackBarSurfaceDark : _snackBarSurfaceLight,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.5,
        ),
        actionTextColor: _snackBarAction,
        disabledActionTextColor: Colors.white.withValues(alpha: 0.5),
        closeIconColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: inputRadius),
        insetPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
      ),
    );
  }
}
