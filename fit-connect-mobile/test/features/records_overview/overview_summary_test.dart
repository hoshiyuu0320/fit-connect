import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/widgets/overview_summary.dart';

import 'records_test_fixtures.dart';

void main() {
  // 2026-09-13（日）
  final today = DateTime(2026, 9, 13);

  group('OverviewSummary（正本 record-screens.js のサンプル）', () {
    final summary = OverviewSummary.from(sampleDays(today), today: today);

    test('1 日平均は今日を含めず、記録した 10 日の平均（1,987 kcal）', () {
      expect(summary.averageCalories, closeTo(1987, 0.001));
      expect(summary.calorieDayCount, 10);
      expect(summary.averageStart, DateTime(2026, 9, 1));
      expect(summary.averageEnd, DateTime(2026, 9, 12));
    });

    test('PFC の 1 日平均は記録した日だけで割る（0 の日を混ぜない）', () {
      expect(summary.pfcDayCount, 10);
      expect(summary.averageProtein, closeTo(95, 0.001));
      expect(summary.averageFat, closeTo(64, 0.001));
      expect(summary.averageCarbs, closeTo(250, 0.001));
    });

    test('13 日は 1 日ごとの棒。記録のない日は null（0 と区別）、今日がハイライト', () {
      expect(summary.weeklyBars, isFalse);
      expect(summary.bars.length, 13);
      expect(summary.bars[2].calories, isNull);
      expect(summary.bars[5].calories, isNull);
      expect(summary.bars[0].calories, 1920);
      expect(summary.bars.last.highlighted, isTrue);
      expect(summary.bars.where((b) => b.highlighted).length, 1);
    });

    test('x ラベルは 1・4・7・10・13 日だけ（正本）', () {
      final labels = [
        for (final b in summary.bars)
          if (b.label.isNotEmpty) b.label,
      ];
      expect(labels, ['1', '4', '7', '10', '13']);
    });

    test('体重を記録した日だけを古い順に持つ', () {
      expect(summary.weightDays.length, 7);
      expect(summary.weightDays.first.weight, 61.6);
      expect(summary.weightDays.last.weight, 62.4);
      expect(summary.hasAnyRecord, isTrue);
    });
  });

  group('1 日平均の対象', () {
    test('過去に食事の記録が 1 日もなければ、今日を含めて平均する', () {
      final days = [
        DailyNutritionStat(date: DateTime(2026, 9, 12)),
        DailyNutritionStat(
          date: DateTime(2026, 9, 13),
          calories: 800,
          protein: 40,
          fat: 20,
          carbs: 90,
        ),
      ];
      final summary = OverviewSummary.from(days, today: today);
      expect(summary.averageCalories, 800);
      expect(summary.calorieDayCount, 1);
      expect(summary.averageEnd, DateTime(2026, 9, 13));
    });

    test('期間が今日だけ（月曜の今週など）でも平均を出す', () {
      final days = [
        DailyNutritionStat(date: DateTime(2026, 9, 13), calories: 900),
      ];
      final summary = OverviewSummary.from(days, today: today);
      expect(summary.averageCalories, 900);
    });

    test('食事の記録が無ければ平均は null（0 にしない）', () {
      final days = [
        for (var i = 0; i < 5; i++)
          DailyNutritionStat(
            date: DateTime(2026, 9, 9 + i),
            weight: i == 4 ? 62.4 : null,
          ),
      ];
      final summary = OverviewSummary.from(days, today: today);
      expect(summary.averageCalories, isNull);
      expect(summary.averageProtein, isNull);
      expect(summary.pfcDayCount, 0);
      expect(summary.hasAnyRecord, isTrue);
    });

    test('何も記録が無ければ hasAnyRecord は false', () {
      final days = [
        for (var i = 0; i < 5; i++) DailyNutritionStat(date: DateTime(2026, 9, 9 + i)),
      ];
      expect(OverviewSummary.from(days, today: today).hasAnyRecord, isFalse);
    });

    test('PFC を入れていない日は PFC の平均に入れない（カロリーだけの記録）', () {
      final days = [
        DailyNutritionStat(date: DateTime(2026, 9, 10), calories: 1800),
        DailyNutritionStat(
          date: DateTime(2026, 9, 11),
          calories: 2000,
          protein: 100,
          fat: 60,
          carbs: 240,
        ),
        DailyNutritionStat(date: DateTime(2026, 9, 13)),
      ];
      final summary = OverviewSummary.from(days, today: today);
      expect(summary.averageCalories, 1900);
      expect(summary.calorieDayCount, 2);
      expect(summary.pfcDayCount, 1);
      expect(summary.averageProtein, 100);
    });
  });

  group('棒グラフの束ね方', () {
    test('7 日以内は曜日ラベルを全部出す', () {
      // 9/7（月）〜9/13（日）
      final days = sampleDays(today, count: 7);
      final summary = OverviewSummary.from(days, today: today);
      expect(summary.weeklyBars, isFalse);
      expect(
        [for (final b in summary.bars) b.label],
        ['月', '火', '水', '木', '金', '土', '日'],
      );
    });

    test('14 日を超えると 1 週間ごと（月曜はじまり）の棒になり、今日を含む週がハイライト', () {
      // 9/13 の 28 日前まで（8/17（月）〜9/13（日）= ちょうど 4 週）
      final days = sampleDays(today, count: 28);
      final summary = OverviewSummary.from(days, today: today);
      expect(summary.weeklyBars, isTrue);
      expect(summary.bars.length, 4);
      expect(summary.bars.first.date, DateTime(2026, 8, 17));
      expect(summary.bars.last.date, DateTime(2026, 9, 7));
      expect(summary.bars.last.highlighted, isTrue);
      expect(summary.bars.where((b) => b.highlighted).length, 1);
      expect(summary.bars.first.label, '8/17');
    });

    test('週の棒は、記録した日の平均（今日は途中なので、ほかに記録があれば入れない）', () {
      // 9/7（月）〜9/13（日）の 1 週と、その前の週で 15 日にする
      final days = [
        for (var i = 0; i < 15; i++)
          DailyNutritionStat(
            date: DateTime(2026, 8, 30 + i),
            calories: 2000,
            protein: 90,
            fat: 60,
            carbs: 240,
          ),
      ];
      // 今日（9/13）だけ極端に低くする
      days[days.length - 1] = DailyNutritionStat(
        date: DateTime(2026, 9, 13),
        calories: 100,
        protein: 5,
        fat: 3,
        carbs: 10,
      );
      final summary = OverviewSummary.from(days, today: today);
      expect(summary.weeklyBars, isTrue);
      expect(summary.bars.last.calories, 2000);
    });

    test('記録のない週の棒は null', () {
      final days = [
        for (var i = 0; i < 20; i++)
          DailyNutritionStat(date: DateTime(2026, 8, 25 + i)),
      ];
      final summary = OverviewSummary.from(days, today: DateTime(2026, 9, 13));
      expect(summary.bars.every((b) => b.calories == null), isTrue);
    });
  });
}
