import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

void main() {
  group('AppColorsExtension 再デザインのトークン', () {
    test('light の主要値', () {
      const c = AppColorsExtension.light;
      expect(c.background, const Color(0xFFF2F2F7));
      expect(c.surface, const Color(0xFFFFFFFF));
      expect(c.surfaceSecondary, const Color(0xFFEDEDF2));
      expect(c.textPrimary, const Color(0xFF171719));
      expect(c.textSecondary, const Color(0xFF6C6C73));
      expect(c.separator, const Color(0xFFE2E2E7));
      expect(c.accent, const Color(0xFF17685D));
      expect(c.actionFill, const Color(0xFF17685D));
      expect(c.onAction, const Color(0xFFFFFFFF));
      expect(c.navigationSurface, const Color(0xF2FCFCFD));
      expect(c.navigationBorder, const Color(0xFFFFFFFF));
      expect(c.recordButtonBorder, const Color(0xFF1D7469));
      expect(c.skeleton, const Color(0xFFE6E6EB));
      expect(c.error, const Color(0xFFC4271D));
      expect(c.errorSurface, const Color(0xFFFCEDEC));
      expect(c.warning, const Color(0xFF8A5300));
      expect(c.warningSurface, const Color(0xFFFBF1E0));
      expect(c.success, const Color(0xFF1F7A36));
      expect(c.successSurface, const Color(0xFFE8F4EB));
    });

    test('dark の主要値', () {
      const c = AppColorsExtension.dark;
      expect(c.background, const Color(0xFF000000));
      expect(c.surface, const Color(0xFF1C1C1E));
      expect(c.surfaceSecondary, const Color(0xFF2B2B30));
      expect(c.textPrimary, const Color(0xFFF5F5F7));
      expect(c.textSecondary, const Color(0xFFABABB3));
      expect(c.separator, const Color(0xFF36363A));
      expect(c.accent, const Color(0xFF78D6B5));
      expect(c.actionFill, const Color(0xFF286353));
      expect(c.onAction, const Color(0xFFFFFFFF));
      expect(c.navigationSurface, const Color(0xF52B2B2E));
      expect(c.navigationBorder, const Color(0xFF48484C));
      expect(c.recordButtonBorder, const Color(0xFF3B7B69));
      expect(c.skeleton, const Color(0xFF2B2B30));
      expect(c.error, const Color(0xFFFF7A70));
      expect(c.errorSurface, const Color(0xFF3A1C1A));
      expect(c.warning, const Color(0xFFFFC266));
      expect(c.warningSurface, const Color(0xFF3A2C14));
      expect(c.success, const Color(0xFF6FD68A));
      expect(c.successSurface, const Color(0xFF17301E));
    });

    test('カード面は light/dark とも不透明', () {
      expect(AppColorsExtension.light.surface.a, 1.0);
      expect(AppColorsExtension.dark.surface.a, 1.0);
    });

    test('ナビの面だけが半透明', () {
      expect(AppColorsExtension.light.navigationSurface.a, lessThan(1.0));
      expect(AppColorsExtension.dark.navigationSurface.a, lessThan(1.0));
    });

    test('light と dark で主要トークンが異なる（テーマ追従）', () {
      const l = AppColorsExtension.light;
      const d = AppColorsExtension.dark;
      expect(l.background, isNot(equals(d.background)));
      expect(l.surface, isNot(equals(d.surface)));
      expect(l.accent, isNot(equals(d.accent)));
      expect(l.error, isNot(equals(d.error)));
    });
  });

  group('AppColorsExtension 旧名の互換（値は新配色へ寄せてある）', () {
    for (final entry in {
      'light': AppColorsExtension.light,
      'dark': AppColorsExtension.dark,
    }.entries) {
      final c = entry.value;
      test('${entry.key}: 旧名は新トークンと同値', () {
        expect(c.border, c.separator);
        expect(c.surfaceDim, c.surfaceSecondary);
        expect(c.textHint, c.textSecondary);
        expect(c.primaryTintForeground, c.accent);
        expect(c.successTint, c.successSurface);
        expect(c.dangerTint, c.errorSurface);
      });

      test('${entry.key}: 旧カテゴリ背景は中立グレー（色を割り振らない）', () {
        expect(c.accentIndigo, c.surfaceSecondary);
        expect(c.accentPurple, c.surfaceSecondary);
        expect(c.accentOrange, c.surfaceSecondary);
      });
    }

    test('静的定数の primary 系は青緑へ寄っている', () {
      expect(AppColors.primary, const Color(0xFF17685D));
      expect(AppColors.primary600, const Color(0xFF17685D));
      expect(AppColors.primary400, const Color(0xFF78D6B5));
      expect(AppColors.background, const Color(0xFFF2F2F7));
      expect(AppColors.success, const Color(0xFF1F7A36));
      expect(AppColors.error, const Color(0xFFC4271D));
    });
  });

  group('AppColorsExtension copyWith / lerp', () {
    test('copyWith(accent:) は accent だけを上書きする', () {
      const override = Color(0xFF123456);
      final result = AppColorsExtension.light.copyWith(accent: override);
      expect(result.accent, override);
      expect(result.actionFill, AppColorsExtension.light.actionFill);
      expect(result.surface, AppColorsExtension.light.surface);
    });

    test('copyWith(errorSurface:) は旧名 dangerTint に影響しない', () {
      const override = Color(0xFF654321);
      final result = AppColorsExtension.light.copyWith(errorSurface: override);
      expect(result.errorSurface, override);
      expect(result.dangerTint, AppColorsExtension.light.dangerTint);
    });

    test('lerp(t: 0.0) は light、lerp(t: 1.0) は dark の値', () {
      final at0 = AppColorsExtension.light.lerp(AppColorsExtension.dark, 0.0);
      final at1 = AppColorsExtension.light.lerp(AppColorsExtension.dark, 1.0);
      expect(at0.background, AppColorsExtension.light.background);
      expect(at0.accent, AppColorsExtension.light.accent);
      expect(at1.background, AppColorsExtension.dark.background);
      expect(at1.accent, AppColorsExtension.dark.accent);
      expect(at1.navigationSurface, AppColorsExtension.dark.navigationSurface);
    });

    test('lerp(other が null 以外の型) は自分自身を返す', () {
      expect(
        AppColorsExtension.light.lerp(null, 0.5),
        same(AppColorsExtension.light),
      );
    });
  });

  group('AppTheme', () {
    test('ThemeExtension が登録され、of(context) で取れる', () {
      expect(
        AppTheme.lightTheme.extension<AppColorsExtension>(),
        AppColorsExtension.light,
      );
      expect(
        AppTheme.darkTheme.extension<AppColorsExtension>(),
        AppColorsExtension.dark,
      );
    });

    test('ColorScheme は accent を primary、surface を面にして明示的に組む', () {
      final light = AppTheme.lightTheme.colorScheme;
      expect(light.brightness, Brightness.light);
      expect(light.primary, AppColorsExtension.light.accent);
      expect(light.surface, AppColorsExtension.light.surface);
      expect(light.onSurface, AppColorsExtension.light.textPrimary);
      expect(light.error, AppColorsExtension.light.error);

      final dark = AppTheme.darkTheme.colorScheme;
      expect(dark.brightness, Brightness.dark);
      expect(dark.primary, AppColorsExtension.dark.accent);
      expect(dark.surface, AppColorsExtension.dark.surface);
    });

    test('scaffold 背景は background', () {
      expect(
        AppTheme.lightTheme.scaffoldBackgroundColor,
        AppColorsExtension.light.background,
      );
      expect(
        AppTheme.darkTheme.scaffoldBackgroundColor,
        AppColorsExtension.dark.background,
      );
    });

    test('カードは角丸 23・影なし・枠線なし', () {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final card = theme.cardTheme;
        expect(card.elevation, 0);
        final shape = card.shape as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(23));
        expect(shape.side, BorderSide.none);
      }
    });

    test('主要ボタンの塗りは actionFill', () {
      final light = AppTheme.lightTheme.filledButtonTheme.style!;
      expect(
        light.backgroundColor!.resolve(<WidgetState>{}),
        AppColorsExtension.light.actionFill,
      );
      final dark = AppTheme.darkTheme.filledButtonTheme.style!;
      expect(
        dark.backgroundColor!.resolve(<WidgetState>{}),
        AppColorsExtension.dark.actionFill,
      );
    });

    test('入力欄は角丸 12', () {
      final border = AppTheme.lightTheme.inputDecorationTheme.border!
          as WidgetStateInputBorder;
      final resolved = border.resolve(<WidgetState>{}) as OutlineInputBorder;
      expect(resolved.borderRadius, BorderRadius.circular(12));
    });

    testWidgets('Text の既定色は textPrimary（ダークでも読める）', (tester) async {
      final cases = <ThemeData, AppColorsExtension>{
        AppTheme.lightTheme: AppColorsExtension.light,
        AppTheme.darkTheme: AppColorsExtension.dark,
      };
      for (final entry in cases.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.key,
            home: const Scaffold(body: Text('あ')),
          ),
        );
        // MaterialApp はテーマ切替を 200ms かけてアニメーションするので落ち着かせる
        await tester.pumpAndSettle();
        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.byType(Scaffold),
            matching: find.byType(RichText),
          ),
        );
        expect(richText.text.style?.color, entry.value.textPrimary);
      }
    });
  });
}
