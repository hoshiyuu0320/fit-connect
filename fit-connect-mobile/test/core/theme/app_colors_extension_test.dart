import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';

void main() {
  group('AppColorsExtension successTint / dangerTint', () {
    test('light preset has expected fixed values', () {
      expect(AppColorsExtension.light.successTint, const Color(0xFFECFDF5));
      expect(AppColorsExtension.light.dangerTint, const Color(0xFFFFE4E6));
    });

    test('dark preset has expected fixed values', () {
      expect(AppColorsExtension.dark.successTint, const Color(0xFF064E3B));
      expect(AppColorsExtension.dark.dangerTint, const Color(0xFF881337));
    });

    test('light and dark tint values differ (theme-following)', () {
      expect(
        AppColorsExtension.light.successTint,
        isNot(equals(AppColorsExtension.dark.successTint)),
      );
      expect(
        AppColorsExtension.light.dangerTint,
        isNot(equals(AppColorsExtension.dark.dangerTint)),
      );
    });

    test('copyWith(successTint:) overrides only successTint', () {
      const override = Color(0xFF123456);
      final result = AppColorsExtension.light.copyWith(successTint: override);
      expect(result.successTint, override);
      expect(result.dangerTint, AppColorsExtension.light.dangerTint);
    });

    test('copyWith(dangerTint:) overrides only dangerTint', () {
      const override = Color(0xFF654321);
      final result = AppColorsExtension.light.copyWith(dangerTint: override);
      expect(result.dangerTint, override);
      expect(result.successTint, AppColorsExtension.light.successTint);
    });

    test('lerp(t: 0.0) returns light values', () {
      final result = AppColorsExtension.light.lerp(AppColorsExtension.dark, 0.0);
      expect(result.successTint, AppColorsExtension.light.successTint);
      expect(result.dangerTint, AppColorsExtension.light.dangerTint);
    });

    test('lerp(t: 1.0) returns dark values', () {
      final result = AppColorsExtension.light.lerp(AppColorsExtension.dark, 1.0);
      expect(result.successTint, AppColorsExtension.dark.successTint);
      expect(result.dangerTint, AppColorsExtension.dark.dangerTint);
    });
  });
}
