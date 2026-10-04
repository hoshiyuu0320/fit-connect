import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/consent/presentation/consent_dialog.dart';

void main() {
  group('ConsentAiNoticeBox', () {
    testWidgets('ダークテーマではテーマ追従の濃い青緑トーンで背景・文字色が描画される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: ConsentAiNoticeBox()),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ConsentAiNoticeBox),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(
        decoration.color,
        AppColorsExtension.dark.primaryTint.withValues(alpha: 0.6),
      );
      final border = decoration.border as Border;
      // 枠は静的な primary600 ではなくテーマ追従の accent（ダークで読める明るい青緑）
      expect(
        border.top.color,
        AppColorsExtension.dark.accent.withValues(alpha: 0.3),
      );

      final titleText = tester.widget<Text>(find.text('AI解析について'));
      expect(
        titleText.style!.color,
        AppColorsExtension.dark.primaryTintForeground,
      );

      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.sparkles));
      expect(icon.color, AppColorsExtension.dark.primaryTintForeground);
    });

    testWidgets('ライトテーマでは背景は淡い青緑、見出しは primaryTintForeground（accent）で描画される',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ConsentAiNoticeBox()),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ConsentAiNoticeBox),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(
        decoration.color,
        AppColorsExtension.light.primaryTint.withValues(alpha: 0.6),
      );

      final titleText = tester.widget<Text>(find.text('AI解析について'));
      expect(
        titleText.style!.color,
        AppColorsExtension.light.primaryTintForeground,
      );
    });
  });
}
