import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/features/exercise_records/models/exercise_record_model.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/screens/exercise_record_screen.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/completed_workout_card.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_month_calendar.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_record_card.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_week_calendar.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../exercise_test_support.dart';

void main() {
  // 今週（月曜はじまり）に、正本と同じ 3 件: ランニング（有酸素）・プランの完了（筋トレ）・プランク（筋トレ）
  final running = testExercise(
    'run-1',
    'running',
    thisWeekAt(0, 18, 20),
    duration: 30,
    distance: 5,
    calories: 320,
    memo: '5km 30分 320kcal',
  );
  final plank = testExercise(
    'plank-1',
    'strength_training',
    thisWeekAt(0, 21, 0),
    memo: 'プランク 1分 × 3セット',
  );
  final plan = testAssignment(
    'plan-1',
    thisWeekAt(0, 7, 30),
    title: '全身',
    exerciseCount: 4,
    calories: 280,
    feedback: 'スクワットのフォームを意識できました。',
  );
  final yoga = testExercise(
    'yoga-1',
    'yoga',
    thisWeekAt(0, 6, 0),
    duration: 45,
  );

  FakeExerciseRepository exercises(List<ExerciseRecord> list) =>
      FakeExerciseRepository(list);

  Future<void> pumpDefault(
    WidgetTester tester, {
    FakeExerciseRepository? exerciseRepository,
    FakeWorkoutRepository? workoutRepository,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    Size size = const Size(390, 2600),
  }) {
    return pumpExerciseScreen(
      tester,
      const ExerciseRecordScreen(),
      exercises: exerciseRepository ?? exercises([running, plank]),
      workouts: workoutRepository ?? FakeWorkoutRepository([plan]),
      brightness: brightness,
      textScale: textScale,
      size: size,
    );
  }

  // 型引数つき（FcSegmentedControl<PeriodFilter> など）は byType で拾えないので述語で探す
  final segmented = find.byWidgetPredicate((w) => w is FcSegmentedControl);
  final chips = find.byWidgetPredicate((w) => w is FcChips);

  group('ExerciseRecordScreen', () {
    testWidgets('上から 期間（今週/今月/全期間）→ 種類 → 今週の記録 → 合計 → 記録一覧 → カード',
        (tester) async {
      await pumpDefault(tester);

      for (final label in ['今週', '今月', '全期間']) {
        expect(find.text(label), findsWidgets);
      }
      // 運動に「今日」の期間は無い（正本は今週・今月・全期間）
      expect(find.text('今日'), findsNothing);
      for (final label in ['すべて', '筋トレ', '有酸素']) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.byType(ExerciseWeekCalendar), findsOneWidget);
      expect(find.byType(ExerciseMonthCalendar), findsNothing);
      expect(find.text('記録一覧'), findsOneWidget);

      double top(Finder finder) => tester.getTopLeft(finder.first).dy;
      expect(top(segmented), lessThan(top(chips)));
      expect(top(chips), lessThan(top(find.byType(ExerciseWeekCalendar))));
      expect(top(find.byType(ExerciseWeekCalendar)),
          lessThan(top(find.byType(FcStatList))));
      expect(top(find.byType(FcStatList)), lessThan(top(find.text('記録一覧'))));
      expect(top(find.text('記録一覧')),
          lessThan(top(find.byType(ExerciseRecordCard).first)));
    });

    testWidgets('合計: 合計 3回 / 筋トレ 2回 / 有酸素 1回 / 消費カロリー 600 kcal（入力があった2件）',
        (tester) async {
      await pumpDefault(tester);

      expect(find.text('${recordRange()}の運動記録'), findsOneWidget);
      expect(find.text('3回'), findsOneWidget);
      expect(find.text('2回'), findsOneWidget);
      expect(find.text('1回'), findsOneWidget);
      expect(find.text('入力があった2件の合計'), findsOneWidget);
      expect(find.text('600 kcal'), findsOneWidget);
    });

    testWidgets('合計の 筋トレ・有酸素 にはアイコン（dumbbell / footprints）が付く', (tester) async {
      await pumpDefault(tester);
      final stat = find.byType(FcStatList);
      expect(
        find.descendant(
          of: stat,
          matching: find.byWidgetPredicate(
            (w) => w is Icon && w.icon == LucideIcons.dumbbell,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stat,
          matching: find.byWidgetPredicate(
            (w) => w is Icon && w.icon == LucideIcons.footprints,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('消費カロリーの入力が 1 件も無ければ「未記録」（0 kcal とは書かない）', (tester) async {
      await pumpDefault(
        tester,
        exerciseRepository: exercises([plank]),
        workoutRepository: FakeWorkoutRepository(const []),
      );
      expect(find.text('未記録'), findsOneWidget);
      expect(find.textContaining('0 kcal'), findsNothing);
      expect(find.textContaining('入力があった'), findsNothing);
      expect(find.text('1回'), findsNWidgets(2)); // 合計 1回・筋トレ 1回
      expect(find.text('0回'), findsOneWidget); // 有酸素 0回（回数は 0 が実際の値）
    });

    testWidgets('一覧は運動の記録とプランの完了を新しい順に並べる', (tester) async {
      await pumpDefault(tester);

      final titles = <String>[];
      for (final widget in tester.widgetList(find.byWidgetPredicate(
        (w) => w is ExerciseRecordCard || w is CompletedWorkoutCard,
      ))) {
        titles.add(widget is ExerciseRecordCard
            ? exerciseRecordTitle(widget.record)
            : completedWorkoutTitle(
                (widget as CompletedWorkoutCard).assignment));
      }
      // 月曜の 21:00 プランク → 18:20 ランニング → 7:30 プランの完了
      expect(titles, [
        'プランク 1分 × 3セット',
        'ランニング 5.0 km · 30分',
        '全身 · 4種目',
      ]);
      expect(find.text('プランの完了'), findsOneWidget);
      expect(find.text('消費 280 kcal'), findsOneWidget);
      expect(find.text('スクワットのフォームを意識できました。'), findsOneWidget);
    });

    testWidgets('種類フィルタ「筋トレ」: 筋トレの記録とプランの完了だけ。有酸素は消える', (tester) async {
      final repository = exercises([running, plank, yoga]);
      await pumpDefault(tester, exerciseRepository: repository);
      expect(find.byType(ExerciseRecordCard), findsNWidgets(3));

      await tester.tap(find.text('筋トレ').first);
      await tester.pumpAndSettle();
      expect(find.text('ランニング 5.0 km · 30分'), findsNothing);
      expect(find.text('ヨガ · 45分'), findsNothing);
      expect(find.text('プランク 1分 × 3セット'), findsOneWidget);
      expect(find.text('全身 · 4種目'), findsOneWidget);

      // 絞り込みは画面側。取得は常に全種類（種類は渡さない）
      expect(repository.requestedTypes.every((t) => t == null), isTrue);
    });

    testWidgets('種類フィルタ「有酸素」: プランの完了も出さない', (tester) async {
      await pumpDefault(tester,
          exerciseRepository: exercises([running, plank, yoga]));

      await tester.tap(find.text('有酸素').first);
      await tester.pumpAndSettle();
      expect(find.text('ランニング 5.0 km · 30分'), findsOneWidget);
      expect(find.text('プランク 1分 × 3セット'), findsNothing);
      expect(find.byType(CompletedWorkoutCard), findsNothing);
      expect(find.text('ヨガ · 45分'), findsNothing);
    });

    testWidgets('「すべて」に戻すと、ヨガのようにどちらにも入らない種類も出る', (tester) async {
      await pumpDefault(tester, exerciseRepository: exercises([running, yoga]));
      expect(find.text('ヨガ · 45分'), findsOneWidget);

      await tester.tap(find.text('筋トレ').first);
      await tester.pumpAndSettle();
      expect(find.text('ヨガ · 45分'), findsNothing);

      await tester.tap(find.text('すべて'));
      await tester.pumpAndSettle();
      expect(find.text('ヨガ · 45分'), findsOneWidget);
    });

    testWidgets('絞り込みで空になったときは、絞り込みのせいだと伝える', (tester) async {
      await pumpDefault(
        tester,
        exerciseRepository: exercises([running]),
        workoutRepository: FakeWorkoutRepository(const []),
      );
      await tester.tap(find.text('筋トレ').first);
      await tester.pumpAndSettle();
      expect(find.text('この種類の記録はありません'), findsOneWidget);
      expect(find.text('まだ記録がありません'), findsNothing);
    });

    testWidgets('種類フィルタは選択中の状態が伝わる（Semantics selected）', (tester) async {
      await pumpDefault(tester);
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('すべて')),
        isSemantics(isSelected: true, isButton: true),
      );
      await tester.tap(find.text('筋トレ').first);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('筋トレ').first),
        isSemantics(isSelected: true, isButton: true),
      );
      handle.dispose();
    });

    testWidgets('期間「今月」: 月カード（点）に切り替わり、前の月へ移せる', (tester) async {
      final now = DateTime.now();
      // 今週が月をまたぐ日でも崩れないよう、今月・先月の固定の日に置く
      final thisMonth = testExercise(
        'this-1',
        'running',
        DateTime(now.year, now.month, 1, 7, 0),
        duration: 30,
      );
      final thisMonthPlan =
          testAssignment('this-plan', DateTime(now.year, now.month, 1, 20, 0));
      final lastMonth = testExercise(
        'last-1',
        'cycling',
        DateTime(now.year, now.month - 1, 10, 9, 0),
        duration: 60,
      );
      await pumpDefault(
        tester,
        exerciseRepository: exercises([thisMonth, lastMonth]),
        workoutRepository: FakeWorkoutRepository([thisMonthPlan]),
      );

      await tester.tap(find.text('今月'));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseWeekCalendar), findsNothing);
      expect(find.byType(ExerciseMonthCalendar), findsOneWidget);
      expect(find.text('ランニング · 30分'), findsOneWidget);
      expect(find.text('サイクリング · 60分'), findsNothing);
      // 運動した日に単色の点（記録とプランの完了が同じ日なので 1 つ）
      expect(find.byType(FcDot), findsOneWidget);
      expect(find.text('${now.month}月の運動記録'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('前の月'));
      await tester.pumpAndSettle();
      expect(find.text('サイクリング · 60分'), findsOneWidget);
      expect(find.byType(FcDot), findsOneWidget);
      expect(find.text('ランニング · 30分'), findsNothing);
      expect(find.byType(CompletedWorkoutCard), findsNothing);
    });

    testWidgets('期間「全期間」: カレンダーは出さず、古い記録も出る', (tester) async {
      final now = DateTime.now();
      final old = testExercise(
        'old-1',
        'swimming',
        DateTime(now.year, now.month - 3, 5, 9, 0),
        duration: 40,
      );
      await pumpDefault(tester, exerciseRepository: exercises([running, old]));
      expect(find.text('水泳 · 40分'), findsNothing);

      await tester.tap(find.text('全期間'));
      await tester.pumpAndSettle();
      expect(find.text('水泳 · 40分'), findsOneWidget);
      expect(find.byType(ExerciseWeekCalendar), findsNothing);
      expect(find.byType(ExerciseMonthCalendar), findsNothing);
      expect(find.text('全期間の運動記録'), findsOneWidget);
    });

    testWidgets('記録が無いときは「まだ記録がありません」とメッセージからの記録の案内', (tester) async {
      await pumpDefault(
        tester,
        exerciseRepository: exercises(const <ExerciseRecord>[]),
        workoutRepository: FakeWorkoutRepository(const []),
      );
      expect(find.text('まだ記録がありません'), findsOneWidget);
      expect(find.textContaining('メッセージ'), findsOneWidget);
      expect(find.byType(ExerciseRecordCard), findsNothing);
      // 合計は 0回（実際の値）、消費カロリーは未記録
      expect(find.text('未記録'), findsOneWidget);
    });

    group('空の状態の「メッセージから記録する」', () {
      Future<void> pumpEmpty(
        WidgetTester tester, {
        VoidCallback? onOpenMessages,
      }) {
        return pumpExerciseScreen(
          tester,
          ExerciseRecordScreen(onOpenMessages: onOpenMessages),
          exercises: exercises(const <ExerciseRecord>[]),
          workouts: FakeWorkoutRepository(const []),
        );
      }

      testWidgets('コールバックがあれば入口が出て、押すと呼ばれる', (tester) async {
        var opened = 0;
        await pumpEmpty(tester, onOpenMessages: () => opened++);

        expect(find.text('メッセージから記録する'), findsOneWidget);
        expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);

        await tester.tap(find.text('メッセージから記録する'));
        await tester.pump();
        expect(opened, 1);
      });

      testWidgets('コールバックが null なら入口は出さず、文言だけ', (tester) async {
        await pumpEmpty(tester);

        expect(find.text('まだ記録がありません'), findsOneWidget);
        expect(find.text('メッセージから記録する'), findsNothing);
        expect(find.byIcon(LucideIcons.messageCircle), findsNothing);
      });

      testWidgets('記録があるときと、種類の絞り込みで空になったときは入口を出さない', (tester) async {
        await pumpExerciseScreen(
          tester,
          ExerciseRecordScreen(onOpenMessages: () {}),
          exercises: exercises([running]),
          workouts: FakeWorkoutRepository(const []),
        );
        expect(find.text('メッセージから記録する'), findsNothing);

        await tester.tap(find.text('筋トレ').first);
        await tester.pumpAndSettle();
        expect(find.text('この種類の記録はありません'), findsOneWidget);
        expect(find.text('メッセージから記録する'), findsNothing);
      });
    });

    testWidgets('読み込みに失敗したときは失敗を伝えて再試行できる（合計は出さない）', (tester) async {
      final repository =
          FakeExerciseRepository([running], failWith: Exception('boom'));
      await pumpDefault(tester, exerciseRepository: repository);

      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      expect(find.byType(FcStatList), findsNothing);

      repository.failWith = null;
      await tester.tap(find.text('再試行').first);
      await tester.pumpAndSettle();
      expect(find.byType(FcStatList), findsOneWidget);
      expect(find.text('ランニング 5.0 km · 30分'), findsOneWidget);
    });

    testWidgets('読み込み中はスケルトンで配置を保ち、0回や未記録とは見せない', (tester) async {
      final repository = FakeExerciseRepository([running])
        ..gate = Completer<void>();
      await pumpDefault(tester, exerciseRepository: repository);

      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(FcStatList), findsNothing);
      expect(find.text('未記録'), findsNothing);
      expect(find.text('まだ記録がありません'), findsNothing);
      expect(find.text('記録一覧'), findsOneWidget);

      repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(FcStatList), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('文字 1.35 倍（${brightness.name}）でもはみ出さない', (tester) async {
        await pumpDefault(
          tester,
          exerciseRepository: exercises([running, plank, yoga]),
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('記録一覧'), findsOneWidget);
      });
    }

    testWidgets('幅 320 × 文字 1.35 倍でもはみ出さない', (tester) async {
      await pumpDefault(
        tester,
        textScale: 1.35,
        size: const Size(320, 3400),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// 今週の範囲の文字（「9/28〜10/4」）
String recordRange() {
  final monday = thisWeekAt(0, 0, 0);
  final sunday = thisWeekAt(6, 0, 0);
  return '${monday.month}/${monday.day}〜${sunday.month}/${sunday.day}';
}
