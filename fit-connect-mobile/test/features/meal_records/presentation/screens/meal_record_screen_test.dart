import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/features/meal_records/presentation/screens/meal_record_screen.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_card.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_summary_card.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_week_calendar.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_month_card.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../meal_test_support.dart';

void main() {
  final lunch = testMeal(
    'lunch-1',
    'lunch',
    todayAt(12, 30),
    notes: '鶏むね肉のグリル定食',
    calories: 640,
    protein: 38,
    fat: 18,
    carbs: 82,
    estimatedByAi: true,
  );
  final breakfast = testMeal(
    'breakfast-1',
    'breakfast',
    todayAt(8, 10),
    notes: 'ごはん・卵・ヨーグルト',
  );
  final now = DateTime.now();
  final old = testMeal(
    'old-1',
    'dinner',
    DateTime(now.year, now.month, now.day - 40, 19, 0),
    notes: '40日前の夕食',
  );

  group('MealRecordScreen', () {
    testWidgets('上から 期間 → 今日の食事 → 今週の記録 → 月 → 記録一覧 → 食事カード の順に出る',
        (tester) async {
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository([lunch, breakfast]),
      );

      for (final label in ['今日', '今週', '今月', '全期間']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('今日の食事'), findsOneWidget);
      expect(find.text('今週の記録'), findsOneWidget);
      expect(find.text('記録一覧'), findsOneWidget);
      expect(find.byType(MealSummaryCard), findsOneWidget);
      expect(find.byType(MealWeekCard), findsOneWidget);
      expect(find.byType(RecordMonthCard), findsOneWidget);
      expect(find.byType(MealCard), findsNWidgets(2));

      // 縦の並び
      double top(Finder finder) => tester.getTopLeft(finder).dy;
      expect(top(find.byType(MealSummaryCard)),
          lessThan(top(find.byType(MealWeekCard))));
      expect(top(find.byType(MealWeekCard)),
          lessThan(top(find.byType(RecordMonthCard))));
      expect(
          top(find.byType(RecordMonthCard)), lessThan(top(find.text('記録一覧'))));
      expect(
          top(find.text('記録一覧')), lessThan(top(find.byType(MealCard).first)));
    });

    testWidgets('今日の食事: 朝食・昼食は記録あり（時刻つき）、夕食・間食は未記録', (tester) async {
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository([lunch, breakfast]),
      );

      final card = find.byType(MealSummaryCard);
      expect(
        find.descendant(of: card, matching: find.text('8:10')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('12:30')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('未記録')),
        findsNWidgets(2),
      );
    });

    testWidgets('食事カード: AI の推定は「推定」と明記し、推定が無い食事は推定の行が無い', (tester) async {
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository([lunch, breakfast]),
      );

      expect(
        find.text('推定 640 kcal · たんぱく質 38 g · 脂質 18 g · 炭水化物 82 g'),
        findsOneWidget,
      );
      expect(find.textContaining('推定'), findsOneWidget);
      expect(find.text('鶏むね肉のグリル定食'), findsOneWidget);
      expect(find.text('ごはん・卵・ヨーグルト'), findsOneWidget);
    });

    testWidgets('一覧は新しい順', (tester) async {
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository([breakfast, lunch]),
      );

      final cards = tester.widgetList<MealCard>(find.byType(MealCard)).toList();
      expect(cards.map((c) => c.record.id), ['lunch-1', 'breakfast-1']);
    });

    testWidgets('期間を「全期間」に切り替えると、古い記録も一覧に出る', (tester) async {
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository([lunch, old]),
      );

      expect(find.text('40日前の夕食'), findsNothing);
      await tester.tap(find.text('全期間'));
      await tester.pumpAndSettle();
      expect(find.text('40日前の夕食'), findsOneWidget);
      expect(find.text('鶏むね肉のグリル定食'), findsOneWidget);

      // 今日の食事・今週・月の 3 枚は期間を替えても残る
      expect(find.byType(MealSummaryCard), findsOneWidget);
      expect(find.byType(MealWeekCard), findsOneWidget);
      expect(find.byType(RecordMonthCard), findsOneWidget);
    });

    testWidgets('期間の選択は選択中の状態が伝わる（Semantics selected）', (tester) async {
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository([lunch]),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('今日')),
        isSemantics(isSelected: true, isButton: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('今週')),
        isSemantics(isSelected: false, isButton: true),
      );
      handle.dispose();
    });

    testWidgets('月カードの前の月を押すと月が替わり、「今月」の一覧もその月になる', (tester) async {
      final lastMonthRecord = testMeal(
        'last-month',
        'lunch',
        DateTime(now.year, now.month - 1, 10, 12, 0),
        notes: '先月の昼食',
      );
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository([lunch, lastMonthRecord]),
      );

      await tester.tap(find.text('今月'));
      await tester.pumpAndSettle();
      expect(find.text('先月の昼食'), findsNothing);

      await tester.tap(find.bySemanticsLabel('前の月'));
      await tester.pumpAndSettle();
      expect(find.text('先月の昼食'), findsOneWidget);
      expect(find.text('鶏むね肉のグリル定食'), findsNothing);

      // 次の月へ戻る
      await tester.tap(find.bySemanticsLabel('次の月'));
      await tester.pumpAndSettle();
      expect(find.text('先月の昼食'), findsNothing);
      expect(find.text('鶏むね肉のグリル定食'), findsOneWidget);
    });

    testWidgets('記録が無いときは「まだ記録がありません」とメッセージからの記録の案内', (tester) async {
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository(const []),
      );

      expect(find.text('まだ記録がありません'), findsOneWidget);
      expect(find.textContaining('メッセージ'), findsOneWidget);
      expect(find.byType(MealCard), findsNothing);
      // 今日の食事は 4 区分とも未記録
      expect(find.text('未記録'), findsNWidgets(4));
    });

    group('空の状態の「メッセージから記録する」', () {
      testWidgets('コールバックがあれば入口が出て、押すと呼ばれる', (tester) async {
        var opened = 0;
        await pumpMealScreen(
          tester,
          MealRecordScreen(onOpenMessages: () => opened++),
          repository: FakeMealRepository(const []),
        );

        expect(find.text('メッセージから記録する'), findsOneWidget);
        expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);

        await tester.tap(find.text('メッセージから記録する'));
        await tester.pump();
        expect(opened, 1);
      });

      testWidgets('コールバックが null なら入口は出さず、文言だけ', (tester) async {
        await pumpMealScreen(
          tester,
          const MealRecordScreen(),
          repository: FakeMealRepository(const []),
        );

        expect(find.text('まだ記録がありません'), findsOneWidget);
        expect(find.text('メッセージから記録する'), findsNothing);
        expect(find.byIcon(LucideIcons.messageCircle), findsNothing);
      });

      testWidgets('記録があるときは、コールバックがあっても入口は出さない', (tester) async {
        await pumpMealScreen(
          tester,
          MealRecordScreen(onOpenMessages: () {}),
          repository: FakeMealRepository([lunch]),
        );

        expect(find.text('メッセージから記録する'), findsNothing);
      });
    });

    testWidgets('読み込みに失敗したときは失敗を伝えて再試行できる（例外の文字は出さない）', (tester) async {
      final repository =
          FakeMealRepository([lunch], failWith: Exception('boom'));
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: repository,
      );

      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      // 今日の食事も「未記録」とは見せない
      expect(find.text('今日の食事を読み込めませんでした'), findsOneWidget);

      repository.failWith = null;
      await tester.tap(find.text('再試行').first);
      await tester.pumpAndSettle();
      expect(find.text('鶏むね肉のグリル定食'), findsOneWidget);
    });

    testWidgets('読み込み中はスケルトンで配置を保ち、「未記録」とは見せない', (tester) async {
      final repository = FakeMealRepository([lunch])..gate = Completer<void>();
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: repository,
      );

      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(MealCard), findsNothing);
      expect(find.text('未記録'), findsNothing);
      expect(find.text('まだ記録がありません'), findsNothing);
      // 見出しと期間の切り替えは出ている
      expect(find.text('今日の食事'), findsOneWidget);
      expect(find.text('記録一覧'), findsOneWidget);

      repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MealCard), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('文字 1.35 倍（${brightness.name}）でもはみ出さない', (tester) async {
        await pumpMealScreen(
          tester,
          const MealRecordScreen(),
          repository: FakeMealRepository([lunch, breakfast]),
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('今日の食事'), findsOneWidget);
        expect(find.byType(MealCard), findsNWidgets(2));
      });
    }

    testWidgets('幅 320 × 文字 1.35 倍でもはみ出さない', (tester) async {
      await pumpMealScreen(
        tester,
        const MealRecordScreen(),
        repository: FakeMealRepository([lunch, breakfast]),
        textScale: 1.35,
        size: const Size(320, 3200),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
