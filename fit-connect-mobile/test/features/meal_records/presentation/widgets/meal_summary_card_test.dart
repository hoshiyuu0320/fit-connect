import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_summary_card.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../meal_test_support.dart';

Future<void> pumpCard(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final records = [
    testMeal('1', 'breakfast', todayAt(8, 10), notes: 'ごはん・卵'),
    testMeal('2', 'lunch', todayAt(12, 30), notes: '定食'),
    testMeal('3', 'snack', todayAt(15, 5), notes: 'ナッツ'),
    testMeal('4', 'snack', todayAt(10, 0), notes: 'ヨーグルト'),
  ];

  group('MealSummaryCard.slotsFrom', () {
    test('朝食・昼食・夕食・間食の順に 4 区分を作り、最初の記録の時刻と件数を持つ', () {
      final slots = MealSummaryCard.slotsFrom(records);

      expect(slots.map((s) => s.label), ['朝食', '昼食', '夕食', '間食']);
      expect(slots[0].recorded, isTrue);
      expect(slots[0].firstRecordedAt, todayAt(8, 10));
      expect(slots[2].recorded, isFalse);
      expect(slots[2].firstRecordedAt, isNull);
      // 間食は 2 件。最初（早い方）の 10:00 を出す
      expect(slots[3].count, 2);
      expect(slots[3].firstRecordedAt, todayAt(10, 0));
    });

    test('知らない区分の記録は 4 区分に含めない', () {
      final slots = MealSummaryCard.slotsFrom(
        [testMeal('9', 'brunch', todayAt(11, 0))],
      );
      expect(slots.every((s) => !s.recorded), isTrue);
    });

    test('読み上げは「記録あり」「未記録」と時刻を含む', () {
      final slots = MealSummaryCard.slotsFrom(records);
      expect(slots[0].semanticLabel, '朝食、記録あり、8:10');
      expect(slots[2].semanticLabel, '夕食、未記録');
      expect(slots[3].semanticLabel, '間食、記録あり、10:00、ほか1件');
    });
  });

  group('MealSummaryCard', () {
    testWidgets('見出しに「今日の食事」と今日の日付、4 区分の記録の有無と時刻が出る', (tester) async {
      final now = DateTime.now();
      await pumpCard(
        tester,
        MealSummaryCard(
          date: now,
          slots: MealSummaryCard.slotsFrom(records),
        ),
      );

      expect(find.text('今日の食事'), findsOneWidget);
      const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
      expect(
        find.text(
          '${now.month}月${now.day}日（${weekdays[now.weekday - 1]}）',
        ),
        findsOneWidget,
      );
      for (final label in ['朝食', '昼食', '夕食', '間食']) {
        expect(find.text(label), findsOneWidget);
      }
      // 時は 0 埋めしない（正本: 8:10）
      expect(find.text('8:10'), findsOneWidget);
      expect(find.text('12:30'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      // 夕食だけが未記録
      expect(find.text('未記録'), findsOneWidget);
      // 完了マーク 4 つ（形でも区別する: 記録あり 3 / 未記録 1）
      final marks = tester
          .widgetList<FcDoneMark>(find.byType(FcDoneMark))
          .map((m) => m.done)
          .toList();
      expect(marks, [true, true, false, true]);
    });

    testWidgets('カードは不透明な surface で、グラデーションや枠線を持たない', (tester) async {
      await pumpCard(
        tester,
        MealSummaryCard(
          date: DateTime.now(),
          slots: MealSummaryCard.slotsFrom(records),
        ),
      );

      final card = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FcCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.border, isNull);
      expect(decoration.color, AppColorsExtension.light.surface);
    });

    testWidgets('ダークでも surface に追従する', (tester) async {
      await pumpCard(
        tester,
        MealSummaryCard(
          date: DateTime.now(),
          slots: MealSummaryCard.slotsFrom(records),
        ),
        brightness: Brightness.dark,
      );

      final card = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FcCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (card.decoration as BoxDecoration).color,
        AppColorsExtension.dark.surface,
      );
    });

    testWidgets('読込中は「未記録」と見せず、マークと時刻をスケルトンにする', (tester) async {
      await pumpCard(
        tester,
        MealSummaryCard(
          date: DateTime.now(),
          slots: MealSummaryCard.slotsFrom(const []),
          loading: true,
        ),
      );

      expect(find.text('未記録'), findsNothing);
      expect(find.byType(FcDoneMark), findsNothing);
      expect(find.byType(FcSkeleton), findsNWidgets(8));
      // ラベルは配置を保つために出す
      expect(find.text('朝食'), findsOneWidget);
    });

    testWidgets('取得に失敗したときは「未記録」ではなく失敗を伝え、再試行できる', (tester) async {
      var retried = 0;
      await pumpCard(
        tester,
        MealSummaryCard(
          date: DateTime.now(),
          slots: MealSummaryCard.slotsFrom(const []),
          hasError: true,
          onRetry: () => retried++,
        ),
      );

      expect(find.text('今日の食事を読み込めませんでした'), findsOneWidget);
      expect(find.text('未記録'), findsNothing);
      await tester.tap(find.text('再試行'));
      expect(retried, 1);
    });

    for (final brightness in Brightness.values) {
      testWidgets('文字 1.35 倍（${brightness.name}）でもはみ出さず、4 区分が残る',
          (tester) async {
        await pumpCard(
          tester,
          MealSummaryCard(
            date: DateTime.now(),
            slots: MealSummaryCard.slotsFrom(records),
          ),
          brightness: brightness,
          textScale: 1.35,
        );

        expect(tester.takeException(), isNull);
        for (final label in ['朝食', '昼食', '夕食', '間食']) {
          expect(find.text(label), findsOneWidget);
        }
      });
    }
  });
}
