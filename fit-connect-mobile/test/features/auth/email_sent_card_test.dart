import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/presentation/widgets/email_sent_card.dart';

void main() {
  group('EmailSentCard', () {
    testWidgets('ダークモード: 背景色が successTint(dark) になり、テキストが表示される',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: EmailSentCard(email: 'user@example.com'),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(EmailSentCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, AppColorsExtension.dark.successTint);
      final border = decoration.border as Border;
      expect(border.top.color, AppColors.success.withValues(alpha: 0.3));
      expect(find.text('メールを確認してください'), findsOneWidget);
      expect(find.textContaining('user@example.com'), findsOneWidget);

      final titleText = tester.widget<Text>(find.text('メールを確認してください'));
      expect(titleText.style!.color, AppColorsExtension.dark.textPrimary);
    });

    testWidgets('ライトモード: 背景色が successTint(light) になる', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: EmailSentCard(email: 'user@example.com'),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(EmailSentCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, AppColorsExtension.light.successTint);
      expect(find.text('メールを確認してください'), findsOneWidget);
      expect(find.textContaining('user@example.com'), findsOneWidget);

      final titleText = tester.widget<Text>(find.text('メールを確認してください'));
      expect(titleText.style!.color, AppColorsExtension.light.textPrimary);
    });
  });
}
