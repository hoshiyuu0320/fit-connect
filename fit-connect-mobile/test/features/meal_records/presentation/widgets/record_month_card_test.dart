import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_week_calendar.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_month_card.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import 'meal_summary_card_test.dart' show pumpCard;

void main() {
  // 2026-09-13（日）を今日とした 9 月。正本 `MonthGrid` と同じ: 1 日は火曜はじまり
  final today = DateTime(2026, 9, 13);
  final month = DateTime(2026, 9, 1);
  final recorded = <DateTime>{
    for (var day = 1; day <= 13; day++)
      if (day != 3 && day != 6) DateTime(2026, 9, day),
  };

  group('RecordMonthCard', () {
    testWidgets('見出し「9月」と「記録した日 11日」、曜日、日付が出る', (tester) async {
      await pumpCard(
        tester,
        RecordMonthCard(month: month, recordedDays: recorded, today: today),
      );

      expect(find.text('9月'), findsOneWidget);
      expect(find.text('記録した日 11日'), findsOneWidget);
      for (final weekday in ['月', '火', '水', '木', '金', '土', '日']) {
        expect(find.text(weekday), findsOneWidget);
      }
      expect(find.text('1'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('31'), findsNothing);
    });

    testWidgets('今年でない月は年も出す', (tester) async {
      await pumpCard(
        tester,
        RecordMonthCard(
          month: DateTime(2025, 12, 1),
          recordedDays: const {},
          today: today,
        ),
      );
      expect(find.text('2025年12月'), findsOneWidget);
    });

    testWidgets('記録した日の下に単色の点（11 日ぶん）。回数の濃淡は使わない', (tester) async {
      await pumpCard(
        tester,
        RecordMonthCard(month: month, recordedDays: recorded, today: today),
      );

      final dots = tester.widgetList<FcDot>(find.byType(FcDot)).toList();
      expect(dots, hasLength(11));
      for (final dot in dots) {
        expect(dot.size, 5);
        expect(dot.filled, isTrue);
        expect(dot.color, isNull); // 既定の accent の単色
      }

      // 緑・青の濃淡（旧 grass / blue レベル）の面が 1 つも無い
      final decorationColors = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>()
          .toSet();
      for (final old in [
        AppColors.grassLevel1,
        AppColors.grassLevel2,
        AppColors.grassLevel3,
        const Color(0xFFBFDBFE),
        const Color(0xFF60A5FA),
        const Color(0xFF2563EB),
      ]) {
        expect(decorationColors, isNot(contains(old)));
      }
    });

    testWidgets('今日は surfaceSecondary の円 + accent + 500、未来は textSecondary',
        (tester) async {
      await pumpCard(
        tester,
        RecordMonthCard(month: month, recordedDays: recorded, today: today),
      );
      final colors = AppColorsExtension.light;

      final todayText = tester.widget<Text>(find.text('13'));
      expect(todayText.style!.color, colors.accent);
      expect(todayText.style!.fontWeight, FontWeight.w500);
      final todayCircle = tester
          .widgetList<Container>(
            find.ancestor(
                of: find.text('13'), matching: find.byType(Container)),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.shape == BoxShape.circle);
      expect(todayCircle.color, colors.surfaceSecondary);

      final futureText = tester.widget<Text>(find.text('20'));
      expect(futureText.style!.color, colors.textSecondary);
      final pastText = tester.widget<Text>(find.text('10'));
      expect(pastText.style!.color, colors.textPrimary);
    });

    testWidgets('日付の円は 28 を下限にし、マスの幅いっぱいには広がらない', (tester) async {
      await pumpCard(
        tester,
        RecordMonthCard(month: month, recordedDays: recorded, today: today),
      );
      for (final label in ['10', '13']) {
        final circle = tester
            .widgetList<Container>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(Container),
              ),
            )
            .firstWhere(
              (c) =>
                  c.decoration is BoxDecoration &&
                  (c.decoration as BoxDecoration).shape == BoxShape.circle,
            );
        final size = tester.getSize(find.byWidget(circle));
        // 下限は 28。文字が広ければ円が広がる（テストの代用フォントは実機より幅が広い）
        expect(size.height, 28, reason: label);
        expect(size.width, greaterThanOrEqualTo(28), reason: label);
        expect(size.width, lessThan(40), reason: label);
      }
    });

    testWidgets('前の月・次の月ボタンは 44×44 以上で、押せるときだけ反応する', (tester) async {
      var previous = 0;
      var next = 0;
      await pumpCard(
        tester,
        RecordMonthCard(
          month: month,
          recordedDays: recorded,
          today: today,
          onPreviousMonth: () => previous++,
          onNextMonth: () => next++,
        ),
      );

      final previousButton = find.bySemanticsLabel('前の月');
      final nextButton = find.bySemanticsLabel('次の月');
      expect(tester.getSize(previousButton).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(previousButton).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(nextButton).height, greaterThanOrEqualTo(44));

      await tester.tap(previousButton);
      await tester.tap(nextButton);
      expect(previous, 1);
      expect(next, 1);
    });

    testWidgets('次の月が無い（今月）ときは次の月が押せない', (tester) async {
      var previous = 0;
      await pumpCard(
        tester,
        RecordMonthCard(
          month: month,
          recordedDays: recorded,
          today: today,
          onPreviousMonth: () => previous++,
          onNextMonth: null,
        ),
      );

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('次の月')),
        isSemantics(isEnabled: false, isButton: true),
      );
      handle.dispose();
      await tester.tap(find.bySemanticsLabel('前の月'));
      expect(previous, 1);
    });

    testWidgets('読込中は点を出さず、記録した日の数はスケルトンにする', (tester) async {
      await pumpCard(
        tester,
        RecordMonthCard(month: month, recordedDays: null, today: today),
      );

      expect(find.byType(FcDot), findsNothing);
      expect(find.textContaining('記録した日'), findsNothing);
      expect(find.byType(FcSkeleton), findsOneWidget);
      // 日付は配置を保つために出す
      expect(find.text('13'), findsOneWidget);
    });

    testWidgets('取得に失敗したときは点も数も出さず、再試行を出す', (tester) async {
      var retried = 0;
      await pumpCard(
        tester,
        RecordMonthCard(
          month: month,
          recordedDays: null,
          today: today,
          hasError: true,
          onRetry: () => retried++,
        ),
      );

      expect(find.text('記録した日を読み込めませんでした'), findsOneWidget);
      expect(find.byType(FcDot), findsNothing);
      await tester.tap(find.text('再試行'));
      expect(retried, 1);
    });

    testWidgets('日付を押せるのは今日まで（未来は押せない）', (tester) async {
      final tapped = <DateTime>[];
      await pumpCard(
        tester,
        RecordMonthCard(
          month: month,
          recordedDays: recorded,
          today: today,
          onDayTap: tapped.add,
        ),
      );

      await tester.tap(find.text('12'));
      await tester.tap(find.text('20'), warnIfMissed: false);
      expect(tapped, [DateTime(2026, 9, 12)]);
    });

    for (final brightness in Brightness.values) {
      testWidgets('文字 1.35 倍（${brightness.name}）でも見出しも 7 列もはみ出さない',
          (tester) async {
        await pumpCard(
          tester,
          RecordMonthCard(
            month: month,
            recordedDays: recorded,
            today: today,
            onPreviousMonth: () {},
            onNextMonth: () {},
          ),
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('9月'), findsOneWidget);
      });
    }

    testWidgets('狭い画面（320）× 文字 1.35 倍でもはみ出さない', (tester) async {
      tester.view.physicalSize = const Size(320, 800) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.35)),
            child: c!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: RecordMonthCard(
                  month: DateTime(2025, 12, 1),
                  recordedDays: recorded,
                  today: today,
                  onPreviousMonth: () {},
                  onNextMonth: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final error = tester.takeException();
      expect(error, isNull, reason: '$error');
    });
  });

  group('MealWeekCard', () {
    // 2026-09-13（日）= 週の最終日（9/7〜9/13）
    final counts = <DateTime, int>{
      DateTime(2026, 9, 7): 3,
      DateTime(2026, 9, 8): 2,
      DateTime(2026, 9, 9): 3,
      DateTime(2026, 9, 10): 2,
      DateTime(2026, 9, 11): 1,
      DateTime(2026, 9, 12): 3,
      DateTime(2026, 9, 13): 2,
    };

    testWidgets('見出し「今週の記録」と期間、各日の印は「3回」の回数の文字', (tester) async {
      await pumpCard(tester, MealWeekCard(today: today, counts: counts));

      expect(find.text('今週の記録'), findsOneWidget);
      expect(find.text('9/7〜9/13'), findsOneWidget);
      expect(find.text('3回'), findsNWidgets(3));
      expect(find.text('2回'), findsNWidgets(3));
      expect(find.text('1回'), findsOneWidget);
      // 回数の文字は textPrimary
      final mark = tester.widget<Text>(find.text('1回'));
      expect(mark.style!.color, AppColorsExtension.light.textPrimary);
    });

    testWidgets('記録のない日は何も出さない（0回とは書かない）', (tester) async {
      await pumpCard(
        tester,
        MealWeekCard(today: today, counts: {DateTime(2026, 9, 7): 1}),
      );
      expect(find.text('1回'), findsOneWidget);
      expect(find.textContaining('0回'), findsNothing);
    });

    testWidgets('未来の日には印を出さない', (tester) async {
      // 水曜（9/9）を今日とした週。木曜以降に件数があっても出さない
      await pumpCard(
        tester,
        MealWeekCard(
          today: DateTime(2026, 9, 9),
          counts: {
            DateTime(2026, 9, 9): 2,
            DateTime(2026, 9, 10): 3,
          },
        ),
      );
      expect(find.text('2回'), findsOneWidget);
      expect(find.text('3回'), findsNothing);
    });

    testWidgets('読込中は印をスケルトンにする', (tester) async {
      await pumpCard(tester, MealWeekCard(today: today, counts: null));
      expect(find.byType(FcSkeleton), findsNWidgets(7));
      expect(find.textContaining('回'), findsNothing);
    });

    testWidgets('文字 1.35 倍でもはみ出さない', (tester) async {
      await pumpCard(
        tester,
        MealWeekCard(today: today, counts: counts),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
