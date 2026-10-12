import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_screen_state.dart';
import 'package:fit_connect_mobile/features/workout/presentation/screens/workout_screen.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_completion_overlay.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_progress_bar.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_format.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../workout_test_helpers.dart';

WorkoutScreenState _fullState({int doneCount = 1}) {
  return WorkoutScreenState(
    overdueAssignments: [makeOverduePlan()],
    todayAssignments: [makeTodayPlan(doneCount: doneCount)],
    upcomingAssignments: [
      makeUpcomingPlan(daysAhead: 3, title: '全身'),
      makeUpcomingPlan(daysAhead: 5, title: '下半身'),
    ],
    weeklyData: const {},
  );
}

Future<WorkoutCalls> _pump(
  WidgetTester tester,
  WorkoutScreenState state, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 2600),
  Completer<WorkoutScreenState>? completer,
  Object? error,
  Object? submitError,
  bool settle = true,
  double bottomPadding = 0,
}) async {
  final calls = WorkoutCalls();
  await pumpWorkout(
    tester,
    const WorkoutScreen(),
    brightness: brightness,
    textScale: textScale,
    size: size,
    settle: settle,
    bottomPadding: bottomPadding,
    overrides: [
      workoutScreenNotifierProvider.overrideWith(
        () => FakeWorkoutScreenNotifier(
          state,
          calls: calls,
          completer: completer,
          error: error,
          submitError: submitError,
        ),
      ),
    ],
  );
  return calls;
}

FcButton _reportButton(WidgetTester tester) => tester.widget<FcButton>(
      find.ancestor(of: find.text('完了を報告する'), matching: find.byType(FcButton)),
    );

void main() {
  group('今日のプラン', () {
    testWidgets('見出し: eyebrow = 今日の日付、title =「プラン」。旧 AppBar「ワークアウト」は出ない',
        (tester) async {
      await _pump(tester, _fullState());

      expect(find.text(formatWorkoutLongDate(DateTime.now())), findsOneWidget);
      expect(find.text('プラン'), findsOneWidget);
      expect(tester.widget<Text>(find.text('プラン')).style!.fontSize, 32);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('ワークアウト'), findsNothing);
    });

    testWidgets('プランのカード: 見出し・プラン名・「{トレーナー} · 3種目」・説明・進み具合', (tester) async {
      await _pump(tester, _fullState());

      expect(find.text('今日のプラン'), findsOneWidget);
      final name = tester.widget<Text>(find.text('上半身')).style!;
      expect(name.fontSize, 26);
      expect(name.fontWeight, FontWeight.w500);
      expect(find.text('田中トレーナー · 3種目'), findsOneWidget);
      expect(find.text('肩の動きを確認しながら、ひとつずつ丁寧に。'), findsOneWidget);
      expect(tester.widget<Text>(find.text('肩の動きを確認しながら、ひとつずつ丁寧に。')).style!.height, 1.6);
      expect(find.text('進み具合'), findsOneWidget);
      expect(find.text('1 / 3 種目'), findsOneWidget);
      expect(find.byType(WorkoutProgressBar), findsOneWidget);
    });

    testWidgets('進み具合のバーは 4px・surfaceSecondary の地に accent の塗り（1/3）', (tester) async {
      await _pump(tester, _fullState());

      final colors = AppColorsExtension.light;
      final fill = find.byKey(const ValueKey('workout-progress-fill'));
      expect(tester.widget<ColoredBox>(fill).color, colors.accent);
      final track = find.ancestor(
        of: fill,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == colors.surfaceSecondary,
        ),
      );
      expect(track, findsOneWidget);
      expect(tester.getSize(track).height, 4);
      expect(tester.getSize(fill).width / tester.getSize(track).width, closeTo(1 / 3, 0.01));
    });

    testWidgets('種目のカードが 3 枚。いま取り組む種目（最初の未完了）だけ開いている', (tester) async {
      await _pump(tester, _fullState());

      expect(find.text('ダンベルプレス'), findsOneWidget);
      expect(find.text('ラットプルダウン'), findsOneWidget);
      expect(find.text('シーテッドロー'), findsOneWidget);
      // 開いているのは「ラットプルダウン」だけ（セット 1〜3 が 1 回ずつ）
      expect(find.text('セット1'), findsOneWidget);
      expect(find.text('田中トレーナーのメモ'), findsOneWidget);
      expect(find.text('3セット × 12回 · 30 kg'), findsOneWidget);
    });

    testWidgets('「完了を報告する」は全種目が完了するまで押せず、理由の一文が下に出る', (tester) async {
      await _pump(tester, _fullState(doneCount: 1));

      expect(_reportButton(tester).onPressed, isNull);
      expect(find.text('すべての種目を終えると報告できます'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('すべての種目を終えると報告できます')).textAlign,
        TextAlign.center,
      );
    });

    testWidgets('全種目が完了すると押せるようになり、一文は消える', (tester) async {
      await _pump(tester, _fullState(doneCount: 3));

      expect(_reportButton(tester).onPressed, isNotNull);
      expect(find.text('すべての種目を終えると報告できます'), findsNothing);
      expect(find.text('3 / 3 種目'), findsOneWidget);
      // 完了しても演出はなく、旧「完了報告」の文言も使わない
      expect(find.text('完了報告'), findsNothing);
      expect(find.textContaining('✓'), findsNothing);
    });

    testWidgets('セット完了を押すと、その種目のセットの保存が呼ばれる', (tester) async {
      final calls = await _pump(tester, _fullState());

      await tester.tap(
        find.byWidgetPredicate((w) => w is FcDoneMark && w.size == 28).first,
      );
      await tester.pumpAndSettle();

      expect(calls.updatedSets, hasLength(1));
      expect(calls.updatedSets.single.assignmentId, 'today');
      expect(calls.updatedSets.single.exerciseId, 'ex-1');
      expect(calls.updatedSets.single.sets.first.done, isTrue);
    });

    testWidgets('種目の見出しを押すと、その種目が開く', (tester) async {
      await _pump(tester, _fullState());

      await tester.tap(find.text('シーテッドロー'));
      await tester.pumpAndSettle();

      expect(find.text('セット1'), findsNWidgets(2));
    });
  });

  group('完了を報告（ボトムシート）', () {
    testWidgets('「完了を報告する」→ シートで入力して報告 → 記録され、報告済みの表示になる', (tester) async {
      final calls = await _pump(tester, _fullState(doneCount: 3));

      await tester.tap(find.text('完了を報告する'));
      await tester.pumpAndSettle();

      // 演出ではなくボトムシート
      expect(find.byType(WorkoutCompletionSheet), findsOneWidget);
      expect(find.text('完了を報告'), findsOneWidget);
      expect(find.text('上半身 · 3種目 · ${formatWorkoutLongDate(DateTime.now())}'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'いい感じでした');
      await tester.enterText(find.byType(TextField).at(1), '280');
      await tester.tap(find.text('田中トレーナーに報告する'));
      await tester.pumpAndSettle();

      expect(calls.submitted, hasLength(1));
      expect(calls.submitted.single.assignmentId, 'today');
      expect(calls.submitted.single.feedback, 'いい感じでした');
      expect(calls.submitted.single.calories, 280);

      // シートは閉じ、ボタンの代わりに「報告しました」を示す
      expect(find.byType(WorkoutCompletionSheet), findsNothing);
      expect(find.text('完了を報告する'), findsNothing);
      expect(find.byType(FcInlineNotice), findsOneWidget);
      expect(find.text('完了を報告しました。消費カロリー 280 kcal'), findsOneWidget);
    });

    testWidgets('キャンセルしたら何も記録されない', (tester) async {
      final calls = await _pump(tester, _fullState(doneCount: 3));

      await tester.tap(find.text('完了を報告する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(calls.submitted, isEmpty);
      expect(find.text('完了を報告する'), findsOneWidget);
    });

    testWidgets('記録に失敗したらシートが残り、入力を保ったままエラーを示す', (tester) async {
      final calls = await _pump(
        tester,
        _fullState(doneCount: 3),
        submitError: Exception('failed'),
      );

      await tester.tap(find.text('完了を報告する'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '重かった');
      await tester.tap(find.text('田中トレーナーに報告する'));
      await tester.pumpAndSettle();

      expect(calls.submitted, isEmpty);
      expect(find.byType(WorkoutCompletionSheet), findsOneWidget);
      expect(find.textContaining('報告できませんでした'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, '重かった');
    });
  });

  group('日付が過ぎたプラン', () {
    testWidgets('小見出し・プラン名・日付・「4種目 · {トレーナー}」・3 つの操作', (tester) async {
      await _pump(tester, _fullState());

      expect(find.text('日付が過ぎたプラン（1件）'), findsOneWidget);
      expect(find.text('下半身'), findsWidgets);
      expect(
        find.text(formatWorkoutShortDate(dayFromToday(-2))),
        findsOneWidget,
      );
      expect(find.text('4種目 · 田中トレーナー'), findsOneWidget);
      expect(find.text('今日やる'), findsOneWidget);
      expect(find.text('スキップ'), findsOneWidget);
      // 「日付を変更」は 日付が過ぎたプラン 1 + 今後の予定 2
      expect(find.text('日付を変更'), findsNWidgets(3));
      // 旧デザインの警告表示（N日前・「未完了のワークアウト」）は出さない
      expect(find.textContaining('日前'), findsNothing);
      expect(find.textContaining('未完了のワークアウト'), findsNothing);
    });

    testWidgets('「今日やる」で今日に移し、確認のメッセージを出す', (tester) async {
      final calls = await _pump(tester, _fullState());

      await tester.tap(find.text('今日やる'));
      await tester.pumpAndSettle();

      expect(calls.doneToday, ['overdue']);
      expect(find.text('今日に移動しました'), findsOneWidget);
    });

    testWidgets('「スキップ」は確認してから実行する（キャンセルなら何も起きない）', (tester) async {
      final calls = await _pump(tester, _fullState());

      await tester.tap(find.text('スキップ'));
      await tester.pumpAndSettle();
      expect(find.text('スキップしますか？'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(calls.skipped, isEmpty);

      await tester.tap(find.text('スキップ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('スキップする'));
      await tester.pumpAndSettle();
      expect(calls.skipped, ['overdue']);
    });

    testWidgets('「日付を変更」で日付ピッカー → 変更するで日付が移る', (tester) async {
      final calls = await _pump(tester, _fullState());

      await tester.tap(find.text('日付を変更').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('変更する'));
      await tester.pumpAndSettle();

      expect(calls.rescheduled, hasLength(1));
      expect(calls.rescheduled.single.assignmentId, 'overdue');
      expect(find.textContaining('に移動しました'), findsOneWidget);
    });

    testWidgets('今日のプランがなく、日付が過ぎたプランだけがあるときも両方出る', (tester) async {
      await _pump(
        tester,
        WorkoutScreenState(
          overdueAssignments: [makeOverduePlan()],
          todayAssignments: const [],
          upcomingAssignments: const [],
          weeklyData: const {},
        ),
      );

      expect(find.text('日付が過ぎたプラン（1件）'), findsOneWidget);
      expect(find.text('今日のプランはありません'), findsOneWidget);
    });
  });

  group('プランがない日', () {
    testWidgets('「今日のプランはありません」と{トレーナー}の一文だけ。運動や休養の指示は出さない', (tester) async {
      await _pump(
        tester,
        const WorkoutScreenState(
          overdueAssignments: [],
          todayAssignments: [],
          upcomingAssignments: [],
          weeklyData: {},
        ),
      );

      expect(find.text('今日のプランはありません'), findsOneWidget);
      expect(find.text('田中トレーナーがプランを設定すると、ここに表示されます。'), findsOneWidget);
      // 左寄せのカード（アイコンなし）
      expect(find.byType(FcStateMessage), findsOneWidget);
      expect(tester.widget<FcStateMessage>(find.byType(FcStateMessage)).kind, FcStateKind.empty);
      expect(find.text('今日のプラン'), findsNothing);
      expect(find.text('完了を報告する'), findsNothing);
      expect(find.textContaining('今日は休'), findsNothing);
      expect(find.textContaining('今後の予定'), findsNothing);
    });

    testWidgets('週ストリップに今日の印は出ない', (tester) async {
      await _pump(
        tester,
        const WorkoutScreenState(
          overdueAssignments: [],
          todayAssignments: [],
          upcomingAssignments: [],
          weeklyData: {},
        ),
      );

      expect(
        find.descendant(of: find.byType(FcWeekStrip), matching: find.byType(FcDot)),
        findsNothing,
      );
      expect(
        find.descendant(of: find.byType(FcWeekStrip), matching: find.byType(FcDoneMark)),
        findsNothing,
      );
    });
  });

  group('下部ナビとの重なり（内容はナビの下まで潜る）', () {
    // FcBottomNavLayout が足す下余白（ナビ 93 + 余白 28）
    const navReserved = 121.0;

    Future<void> pumpWithNav(
      WidgetTester tester,
      WorkoutScreenState state, {
      Completer<WorkoutScreenState>? completer,
      Object? error,
      bool settle = true,
    }) {
      return _pump(
        tester,
        state,
        size: const Size(390, 844),
        bottomPadding: navReserved,
        completer: completer,
        error: error,
        settle: settle,
      );
    }

    void expectScrollsUnderNav(WidgetTester tester) {
      // スクロール領域は画面の下端まで届く（ナビぶんの帯で平らに切れない）
      final list = find.byType(ListView);
      expect(tester.getRect(list).bottom, 844);
      // 下余白はナビが確保する分だけ（二重に足さない）
      final padding = tester.widget<ListView>(list).padding!.resolve(TextDirection.ltr);
      expect(padding.bottom, navReserved);
    }

    testWidgets('今日のプラン: スクロール領域が下端まで届き、下余白はナビぶん 1 回だけ', (tester) async {
      await pumpWithNav(tester, _fullState());

      expectScrollsUnderNav(tester);
    });

    testWidgets('スクロールの終端で、最後の内容がナビの上（余白 28）に収まる', (tester) async {
      await pumpWithNav(tester, _fullState());

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      final lastCard = find.text('今後の予定（2件）');
      expect(lastCard, findsOneWidget);
      // 今後の予定のカードの下端 + 余白 = 画面の下端 - ナビの高さ（93）
      final upcomingCard = find.ancestor(
        of: find.text('下半身').last,
        matching: find.byType(FcCard),
      );
      expect(
        tester.getRect(upcomingCard).bottom,
        closeTo(844 - navReserved, 0.5),
      );
    });

    testWidgets('読込中・プランなし・読み込めないでも同じ（下まで潜る）', (tester) async {
      await pumpWithNav(
        tester,
        _fullState(),
        completer: Completer<WorkoutScreenState>(),
        settle: false,
      );
      expectScrollsUnderNav(tester);

      await tester.pumpWidget(const SizedBox());
      await pumpWithNav(
        tester,
        const WorkoutScreenState(
          overdueAssignments: [],
          todayAssignments: [],
          upcomingAssignments: [],
          weeklyData: {},
        ),
      );
      expectScrollsUnderNav(tester);

      await tester.pumpWidget(const SizedBox());
      await pumpWithNav(tester, _fullState(), error: Exception('network'));
      expectScrollsUnderNav(tester);
    });
  });

  group('読込中・読み込めない', () {
    testWidgets('読込中は見出しを保ったままスケルトンを出す（スピナーは出さない）', (tester) async {
      final handle = tester.ensureSemantics();
      final completer = Completer<WorkoutScreenState>();
      await _pump(tester, _fullState(), completer: completer, settle: false);

      expect(find.text('プラン'), findsOneWidget);
      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.bySemanticsLabel('読み込み中'), findsOneWidget);
      // 読み込めるまでは 0 や空のプランを見せない
      expect(find.text('今日のプランはありません'), findsNothing);
      expect(find.text('完了を報告する'), findsNothing);
      handle.dispose();
    });

    testWidgets('読み込みに失敗したら理由と「再試行」を示す', (tester) async {
      await _pump(tester, _fullState(), error: Exception('network'));

      expect(find.text('プランを読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
      // 例外の文字列をそのまま画面に出さない
      expect(find.textContaining('Exception'), findsNothing);
      expect(tester.widget<FcStateMessage>(find.byType(FcStateMessage)).kind, FcStateKind.error);
    });
  });

  group('今日のプランが複数・文字拡大・ダーク', () {
    testWidgets('今日のプランが 2 件あっても、それぞれのカードと報告が出る', (tester) async {
      final a = makeTodayPlan(doneCount: 3);
      final b = makeTodayPlan(doneCount: 0).copyWith(id: 'today-2');
      await _pump(
        tester,
        WorkoutScreenState(
          overdueAssignments: const [],
          todayAssignments: [a, b],
          upcomingAssignments: const [],
          weeklyData: const {},
        ),
        size: const Size(390, 4000),
      );

      expect(find.text('今日のプラン'), findsNWidgets(2));
      expect(find.text('完了を報告する'), findsNWidgets(2));
    });

    for (final brightness in Brightness.values) {
      for (final width in [390.0, 320.0]) {
        testWidgets('${brightness.name}・文字 1.35 倍・${width.toInt()} 幅でも、すべての状態ではみ出さない', (tester) async {
          await _pump(
            tester,
            _fullState(),
            brightness: brightness,
            textScale: 1.35,
            size: Size(width, 6000),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('今日のプラン'), findsOneWidget);
          expect(find.text('今後の予定（2件）'), findsOneWidget);

          // シートも
          await tester.pumpWidget(const SizedBox());
          await _pump(
            tester,
            _fullState(doneCount: 3),
            brightness: brightness,
            textScale: 1.35,
            size: Size(width, 6000),
          );
          await tester.tap(find.text('完了を報告する'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(WorkoutCompletionSheet), findsOneWidget);
        });
      }
    }

    testWidgets('プランがない日・読込中も文字 1.35 倍でもはみ出さない', (tester) async {
      await _pump(
        tester,
        const WorkoutScreenState(
          overdueAssignments: [],
          todayAssignments: [],
          upcomingAssignments: [],
          weeklyData: {},
        ),
        textScale: 1.35,
        size: const Size(320, 1400),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        _fullState(),
        textScale: 1.35,
        size: const Size(320, 1400),
        completer: Completer<WorkoutScreenState>(),
        settle: false,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
