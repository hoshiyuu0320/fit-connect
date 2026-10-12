import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/completed_workout_card.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_kind.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_record_card.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_week_calendar.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../../../meal_records/presentation/widgets/meal_summary_card_test.dart'
    show pumpCard;
import '../exercise_test_support.dart';

void main() {
  group('exerciseKindOf（筋トレ系・有酸素系のグルーピング）', () {
    test('筋トレ = strength_training', () {
      expect(exerciseKindOf('strength_training'), ExerciseKind.strength);
    });

    test('有酸素 = cardio / walking / running / cycling / swimming', () {
      for (final type in [
        'cardio',
        'walking',
        'running',
        'cycling',
        'swimming',
      ]) {
        expect(exerciseKindOf(type), ExerciseKind.cardio, reason: type);
      }
    });

    test('どちらでもない = yoga / pilates / other / 未知の値（「すべて」にだけ出る）', () {
      for (final type in ['yoga', 'pilates', 'other', 'boxing']) {
        expect(exerciseKindOf(type), ExerciseKind.other, reason: type);
      }
    });

    test('アイコンは筋トレ = dumbbell、有酸素 = footprints（絵文字ではない）', () {
      expect(ExerciseKind.strength.icon, LucideIcons.dumbbell);
      expect(ExerciseKind.cardio.icon, LucideIcons.footprints);
      expect(ExerciseKind.strength.label, '筋トレ');
      expect(ExerciseKind.cardio.label, '有酸素');
    });
  });

  group('exerciseMemoIsMeaningful', () {
    test('数値と単位だけのメモは意味なし（題名・補足と二重になる）', () {
      expect(exerciseMemoIsMeaningful('5km 30分 320kcal'), isFalse);
      expect(exerciseMemoIsMeaningful('30分'), isFalse);
      expect(exerciseMemoIsMeaningful('  '), isFalse);
      expect(exerciseMemoIsMeaningful(null), isFalse);
    });

    test('文字が残るメモは意味あり', () {
      expect(exerciseMemoIsMeaningful('プランク 1分 × 3セット'), isTrue);
      expect(exerciseMemoIsMeaningful('朝のストレッチを中心に'), isTrue);
    });

    test('種類の名前だけのメモは意味なし（題名にすでにある）', () {
      expect(
        exerciseMemoIsMeaningful('ランニング 5km', exerciseType: 'running'),
        isFalse,
      );
      expect(
        exerciseMemoIsMeaningful('ランニング 公園を一周', exerciseType: 'running'),
        isTrue,
      );
    });
  });

  group('運動の記録カードの文言', () {
    final at = DateTime(2026, 9, 12, 18, 20);

    test('ランニング: 題名「ランニング 5.0 km · 30分」、補足「消費 320 kcal · メッセージから」', () {
      final record = testExercise('1', 'running', at,
          duration: 30, distance: 5, calories: 320, memo: '5km 30分 320kcal');
      expect(exerciseRecordTitle(record), 'ランニング 5.0 km · 30分');
      expect(exerciseRecordNote(record), isNull); // 数値だけのメモは出さない
      expect(exerciseRecordMeta(record), '消費 320 kcal · メッセージから');
      expect(exerciseRecordKindLabel(record), '有酸素');
    });

    test('筋トレ: メモが題名になる（「プランク 1分 × 3セット」）。補足は「メッセージから」だけ', () {
      final record =
          testExercise('2', 'strength_training', at, memo: 'プランク 1分 × 3セット');
      expect(exerciseRecordTitle(record), 'プランク 1分 × 3セット');
      expect(exerciseRecordNote(record), isNull);
      expect(exerciseRecordMeta(record), 'メッセージから');
      expect(exerciseRecordKindLabel(record), '筋トレ');
    });

    test('筋トレでメモが無ければ種類の名前 + 時間', () {
      final record = testExercise('3', 'strength_training', at, duration: 45);
      expect(exerciseRecordTitle(record), '筋トレ · 45分');
    });

    test('ヨガ: 種類の名前が見出し、メモはノートになる。手入力は「メッセージから」を付けない', () {
      final record = testExercise('4', 'yoga', at,
          duration: 45, memo: '朝のストレッチを中心に', source: 'manual');
      expect(exerciseRecordKindLabel(record), 'ヨガ');
      expect(exerciseRecordTitle(record), 'ヨガ · 45分');
      expect(exerciseRecordNote(record), '朝のストレッチを中心に');
      expect(exerciseRecordMeta(record), isNull);
    });

    test('距離だけ・時間だけでも崩れない', () {
      expect(
        exerciseRecordTitle(testExercise('5', 'walking', at, distance: 3.25)),
        'ウォーキング 3.3 km',
      );
      expect(
        exerciseRecordTitle(testExercise('6', 'cycling', at)),
        'サイクリング',
      );
    });
  });

  group('ExerciseRecordCard', () {
    testWidgets('見出しは系統のアイコンと言葉、右に日時。絵文字を使わない', (tester) async {
      await pumpCard(
        tester,
        ExerciseRecordCard(
          record: testExercise(
            '1',
            'running',
            DateTime(2026, 9, 12, 18, 20),
            duration: 30,
            distance: 5,
            calories: 320,
          ),
        ),
      );

      expect(find.text('有酸素'), findsOneWidget);
      expect(find.text('9月12日（土）18:20'), findsOneWidget);
      expect(find.text('ランニング 5.0 km · 30分'), findsOneWidget);
      expect(find.text('消費 320 kcal · メッセージから'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == LucideIcons.footprints,
        ),
        findsOneWidget,
      );
      final emoji =
          RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
      final texts =
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '');
      expect(texts.where(emoji.hasMatch), isEmpty);
    });

    testWidgets('題名は 17 / 500、カードはカテゴリ色を持たず surface', (tester) async {
      await pumpCard(
        tester,
        ExerciseRecordCard(
          record: testExercise('1', 'running', DateTime(2026, 9, 12, 18, 20),
              duration: 30),
        ),
      );
      final title = tester.widget<Text>(find.text('ランニング · 30分'));
      expect(title.style!.fontSize, 17);
      expect(title.style!.fontWeight, FontWeight.w500);

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
        AppColorsExtension.light.surface,
      );
    });

    testWidgets('文字 1.35 倍でも長いノートが折り返して、はみ出さない', (tester) async {
      await pumpCard(
        tester,
        ExerciseRecordCard(
          record: testExercise(
            '1',
            'yoga',
            DateTime(2026, 9, 12, 18, 20),
            duration: 45,
            calories: 1200,
            memo: '朝のストレッチを中心に、肩まわりと股関節をゆっくり時間をかけてほぐしました',
          ),
        ),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('CompletedWorkoutCard（プランの完了）', () {
    testWidgets('種別は「プランの完了」、題名「プラン名 · 4種目」、感想と消費カロリー', (tester) async {
      await pumpCard(
        tester,
        CompletedWorkoutCard(
          assignment: testAssignment(
            'a1',
            DateTime(2026, 9, 9, 18, 40),
            title: '全身',
            exerciseCount: 4,
            calories: 280,
            feedback: 'スクワットのフォームを意識できました。',
          ),
        ),
      );

      expect(find.text('プランの完了'), findsOneWidget);
      // 日付だけ（時刻は出さない）
      expect(find.text('9月9日（水）'), findsOneWidget);
      expect(find.text('全身 · 4種目'), findsOneWidget);
      expect(find.text('スクワットのフォームを意識できました。'), findsOneWidget);
      expect(find.text('消費 280 kcal'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == LucideIcons.dumbbell,
        ),
        findsOneWidget,
      );
    });

    testWidgets('感想も消費カロリーも無ければ、その行を出さない', (tester) async {
      await pumpCard(
        tester,
        CompletedWorkoutCard(
          assignment: testAssignment(
            'a2',
            DateTime(2026, 9, 7, 7, 0),
            title: '下半身',
            exerciseCount: 0,
          ),
        ),
      );
      expect(find.text('下半身'), findsOneWidget); // 種目が無ければプラン名だけ
      expect(find.textContaining('kcal'), findsNothing);
      expect(find.textContaining('完了報告'), findsNothing);
      expect(tester.widgetList<Text>(find.byType(Text)), hasLength(3));
    });

    testWidgets('旧デザインの「完了」バッジ・セットの実績の一覧・絵文字は出さない', (tester) async {
      await pumpCard(
        tester,
        CompletedWorkoutCard(
          assignment: testAssignment('a3', DateTime(2026, 9, 9, 18, 40)),
        ),
      );
      expect(find.text('完了'), findsNothing);
      expect(find.textContaining('目標:'), findsNothing);
      expect(find.textContaining('Set '), findsNothing);
    });

    testWidgets('文字 1.35 倍でもはみ出さない', (tester) async {
      await pumpCard(
        tester,
        CompletedWorkoutCard(
          assignment: testAssignment(
            'a4',
            DateTime(2026, 9, 9, 18, 40),
            title: '上半身プッシュと体幹の長いプラン名',
            calories: 1280,
            feedback: 'ベンチプレスの最後のセットが重かったけれど、フォームは崩さずに終えられました。',
          ),
        ),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ExerciseWeekCalendar', () {
    // 2026-09-13（日）= 週の最終日（9/7〜9/13）
    final today = DateTime(2026, 9, 13);
    final kinds = <DateTime, Set<ExerciseKind>>{
      DateTime(2026, 9, 7): {ExerciseKind.strength},
      DateTime(2026, 9, 9): {ExerciseKind.strength, ExerciseKind.cardio},
      DateTime(2026, 9, 12): {ExerciseKind.cardio},
      DateTime(2026, 9, 13): {ExerciseKind.other},
    };

    int iconCount(WidgetTester tester, IconData icon) => tester
        .widgetList<Icon>(find.byType(Icon))
        .where((i) => i.icon == icon)
        .length;

    testWidgets('見出し「今週の記録」と期間。主な種類のアイコン（筋トレがあれば dumbbell）', (tester) async {
      await pumpCard(
        tester,
        ExerciseWeekCalendar(today: today, kindsByDay: kinds),
      );

      expect(find.text('今週の記録'), findsOneWidget);
      expect(find.text('9/7〜9/13'), findsOneWidget);
      // 9/7・9/9 は筋トレ、9/12 は有酸素
      expect(iconCount(tester, LucideIcons.dumbbell), 2);
      expect(iconCount(tester, LucideIcons.footprints), 1);
      // どちらでもない運動（9/13）は単色の点
      expect(find.byType(FcDot), findsOneWidget);
    });

    testWidgets('種類フィルタに合わせて、その系統の日だけに印を出す', (tester) async {
      await pumpCard(
        tester,
        ExerciseWeekCalendar(
          today: today,
          kindsByDay: kinds,
          filter: ExerciseKind.cardio,
        ),
      );
      // 有酸素がある 9/9・9/12 に footprints
      expect(iconCount(tester, LucideIcons.footprints), 2);
      expect(iconCount(tester, LucideIcons.dumbbell), 0);
      expect(find.byType(FcDot), findsNothing);
    });

    testWidgets('印の色は accent の単色（カテゴリ色を使わない）', (tester) async {
      await pumpCard(
        tester,
        ExerciseWeekCalendar(today: today, kindsByDay: kinds),
      );
      final iconTheme = tester
          .widgetList<IconTheme>(
            find.ancestor(
              of: find.byIcon(LucideIcons.dumbbell).first,
              matching: find.byType(IconTheme),
            ),
          )
          .map((t) => t.data.color);
      expect(iconTheme, contains(AppColorsExtension.light.accent));
    });

    testWidgets('読込中は印をスケルトンにし、失敗時は印を出さず再試行を出す', (tester) async {
      await pumpCard(
        tester,
        ExerciseWeekCalendar(today: today, kindsByDay: null),
      );
      expect(find.byType(FcSkeleton), findsNWidgets(7));
      expect(iconCount(tester, LucideIcons.dumbbell), 0);

      var retried = 0;
      await pumpCard(
        tester,
        ExerciseWeekCalendar(
          today: today,
          kindsByDay: null,
          hasError: true,
          onRetry: () => retried++,
        ),
      );
      expect(find.byType(FcSkeleton), findsNothing);
      await tester.tap(find.text('再試行'));
      expect(retried, 1);
    });

    testWidgets('文字 1.35 倍でもはみ出さない', (tester) async {
      await pumpCard(
        tester,
        ExerciseWeekCalendar(today: today, kindsByDay: kinds),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
