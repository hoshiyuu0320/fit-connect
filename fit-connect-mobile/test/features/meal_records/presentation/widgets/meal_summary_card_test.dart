import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_summary_card.dart';

void main() {
  group('MealSummaryCard', () {
    testWidgets('dark mode: gradient uses dark primaryTint and accentIndigo',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MealSummaryCard(
                title: '今日のまとめ',
                meals: '3食',
                photos: '2枚',
                calories: '1,800 kcal',
              ),
            ),
          ),
        ),
      );

      final container = find
          .descendant(
            of: find.byType(MealSummaryCard),
            matching: find.byType(Container),
          )
          .first;
      final decoration =
          tester.widget<Container>(container).decoration as BoxDecoration;
      final gradient = decoration.gradient as LinearGradient;

      expect(gradient.colors.first, AppColorsExtension.dark.primaryTint);
      expect(gradient.colors.last, AppColorsExtension.dark.accentIndigo);
    });

    testWidgets(
        'light mode: gradient ends match light primaryTint and accentIndigo (gradient unchanged; only the border moved to a primary600 overlay)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MealSummaryCard(
                title: '今日のまとめ',
                meals: '3食',
                photos: '2枚',
                calories: '1,800 kcal',
              ),
            ),
          ),
        ),
      );

      final container = find
          .descendant(
            of: find.byType(MealSummaryCard),
            matching: find.byType(Container),
          )
          .first;
      final decoration =
          tester.widget<Container>(container).decoration as BoxDecoration;
      final gradient = decoration.gradient as LinearGradient;

      expect(gradient.colors.first, AppColorsExtension.light.primaryTint);
      expect(gradient.colors.last, AppColorsExtension.light.accentIndigo);
    });
  });
}
