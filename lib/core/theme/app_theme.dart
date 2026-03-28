import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      extensions: const [AppColorsExtension.light],
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColorsExtension.light.background,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColorsExtension.light.surface,
        foregroundColor: AppColorsExtension.light.textPrimary,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColorsExtension.light.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
      ),
      cardTheme: CardThemeData(
        color: AppColorsExtension.light.surface,
      ),
      dividerTheme: DividerThemeData(
        color: AppColorsExtension.light.border,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      extensions: const [AppColorsExtension.dark],
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColorsExtension.dark.background,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColorsExtension.dark.surface,
        foregroundColor: AppColorsExtension.dark.textPrimary,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColorsExtension.dark.surface,
        selectedItemColor: AppColors.primary400,
        unselectedItemColor: Colors.grey,
      ),
      cardTheme: CardThemeData(
        color: AppColorsExtension.dark.surface,
      ),
      dividerTheme: DividerThemeData(
        color: AppColorsExtension.dark.border,
      ),
    );
  }
}
