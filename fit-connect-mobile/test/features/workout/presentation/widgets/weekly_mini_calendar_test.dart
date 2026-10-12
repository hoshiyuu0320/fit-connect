import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/weekly_mini_calendar.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../workout_test_helpers.dart';

/// 正本の見本と同じ週（9/7 月 〜 9/13 日）。今日は 9/13（日）
final _today = DateTime(2026, 9, 13);

WorkoutAssignment _assignment(DateTime day, String status, {String title = '上半身'}) {
  return WorkoutAssignment(
    id: 'a-${day.day}',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    planId: 'plan-1',
    assignedDate: fmtDate(day),
    status: status,
    planInfo: WorkoutPlanInfo(title: title, category: '筋トレ', estimatedMinutes: 45),
    exercises: [
      makeExercise(
        id: 'e-${day.day}',
        assignmentId: 'a-${day.day}',
        name: 'ダンベルプレス',
        weight: 12,
        done: status == 'completed',
      ),
    ],
  );
}

/// 水 9/9 = 完了、金 9/11 = 日付が過ぎた、土 9/12 = スキップ、日 9/13（今日）= 予定
Map<DateTime, List<WorkoutAssignment>> _week() {
  final wed = DateTime(2026, 9, 9);
  final fri = DateTime(2026, 9, 11);
  final sat = DateTime(2026, 9, 12);
  return {
    wed: [_assignment(wed, 'completed')],
    fri: [_assignment(fri, 'pending', title: '下半身')],
    sat: [_assignment(sat, 'skipped', title: '全身')],
    _today: [_assignment(_today, 'pending')],
  };
}

Future<void> _pumpCalendar(
  WidgetTester tester, {
  Map<DateTime, List<WorkoutAssignment>>? data,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 844),
}) {
  return pumpWorkout(
    tester,
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topCenter,
          child: WeeklyMiniCalendar(weeklyData: data ?? _week(), today: _today),
        ),
      ),
    ),
    brightness: brightness,
    textScale: textScale,
    size: size,
  );
}

Finder _stripDots() => find.descendant(
      of: find.byType(FcWeekStrip),
      matching: find.byType(FcDot),
    );

void main() {
  group('WeeklyMiniCalendar（週ストリップ）', () {
    testWidgets('曜日と日付が 7 日ぶん並び、今日は選択中の見た目', (tester) async {
      await _pumpCalendar(tester);

      for (final label in ['月', '火', '水', '木', '金', '土', '日']) {
        expect(find.text(label), findsOneWidget);
      }
      for (var d = 7; d <= 13; d++) {
        expect(find.text('$d'), findsOneWidget);
      }

      // 今日（13）だけ surfaceSecondary の円 + accent の文字
      final colors = AppColorsExtension.light;
      final todayText = tester.widget<Text>(find.text('13'));
      expect(todayText.style!.color, colors.accent);
      expect(todayText.style!.fontWeight, FontWeight.w500);
      final otherText = tester.widget<Text>(find.text('10'));
      expect(otherText.style!.color, colors.textPrimary);
      final circle = tester
          .widgetList<Container>(find.descendant(
            of: find.ancestor(of: find.text('13'), matching: find.byType(Column)).first,
            matching: find.byType(Container),
          ))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle && d.color == colors.surfaceSecondary);
      expect(circle, isNotEmpty);
    });

    testWidgets('印: 完了 = 完了マーク（16）、予定 = 塗りの点、日付が過ぎた = 中抜きの点', (tester) async {
      await _pumpCalendar(tester);

      // 完了マーク（ストリップ内の 16）は水曜の 1 つだけ。凡例の 12 は別
      final doneMarks = find.descendant(
        of: find.byType(FcWeekStrip),
        matching: find.byType(FcDoneMark),
      );
      expect(doneMarks, findsOneWidget);
      expect(tester.widget<FcDoneMark>(doneMarks).size, 16);
      expect(tester.widget<FcDoneMark>(doneMarks).done, isTrue);

      // 点は 金（中抜き）と 今日（塗り）の 2 つ。スキップの土曜には印がない
      final dots = tester.widgetList<FcDot>(_stripDots()).toList();
      expect(dots, hasLength(2));
      expect(dots.where((d) => d.filled), hasLength(1));
      expect(dots.where((d) => !d.filled), hasLength(1));
    });

    testWidgets('今日にプランがない週は、今日の印が出ない', (tester) async {
      final wed = DateTime(2026, 9, 9);
      await _pumpCalendar(tester, data: {
        wed: [_assignment(wed, 'completed')],
      });

      expect(_stripDots(), findsNothing);
    });

    testWidgets('凡例「完了 / 予定 / 日付が過ぎた」が下に並ぶ', (tester) async {
      await _pumpCalendar(tester);

      expect(find.text('完了'), findsOneWidget);
      expect(find.text('予定'), findsOneWidget);
      expect(find.text('日付が過ぎた'), findsOneWidget);
      // 凡例は週の下（日付より下）にある
      expect(
        tester.getTopLeft(find.text('完了')).dy,
        greaterThan(tester.getTopLeft(find.text('13')).dy),
      );
    });

    testWidgets('カード内余白は 上14・左右10・下10', (tester) async {
      await _pumpCalendar(tester);

      final card = tester.widget<FcCard>(find.byType(FcCard));
      expect(card.paddingOverride, const EdgeInsets.fromLTRB(10, 14, 10, 10));
    });

    testWidgets('プランのある日を押すと詳細シートが開く（完了の日）', (tester) async {
      await _pumpCalendar(tester);

      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();

      expect(find.text('9月9日（水）'), findsOneWidget);
      expect(find.text('上半身'), findsOneWidget);
      // 状態は色ではなく文字で示す
      expect(find.text('完了'), findsNWidgets(2)); // 凡例 + シートの状態
      expect(find.text('ダンベルプレス'), findsOneWidget);
      expect(find.text('3セット × 10回 · 12 kg'), findsOneWidget);
      // 旧デザインの英字表記・固定色は使わない
      expect(find.textContaining('Set'), findsNothing);
    });

    testWidgets('スキップした日も押すと詳細で「スキップ」と分かる', (tester) async {
      await _pumpCalendar(tester);

      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(find.text('9月12日（土）'), findsOneWidget);
      expect(find.text('全身'), findsOneWidget);
      expect(find.text('スキップ'), findsOneWidget);
    });

    testWidgets('プランのない日を押しても何も開かない', (tester) async {
      await _pumpCalendar(tester);

      await tester.tap(find.text('8'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('読み上げ: 日付・今日・状態を 1 つにまとめる', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpCalendar(tester);

      expect(find.bySemanticsLabel('9月9日 水曜日、完了'), findsOneWidget);
      expect(find.bySemanticsLabel('9月11日 金曜日、日付が過ぎた'), findsOneWidget);
      expect(find.bySemanticsLabel('9月13日 日曜日、今日、予定'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('読み上げ: 押して詳細が開く日（プランのある日）だけボタン。プランのない日はボタンにしない', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpCalendar(tester);

      bool isButton(String label) => tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData()
          .flagsCollection
          .isButton;

      // プランのある日: 完了（水）・日付が過ぎた（金）・スキップ（土）・今日（日）
      expect(isButton('9月9日 水曜日、完了'), isTrue);
      expect(isButton('9月11日 金曜日、日付が過ぎた'), isTrue);
      expect(isButton('9月12日 土曜日、スキップ'), isTrue);
      expect(isButton('9月13日 日曜日、今日、予定'), isTrue);
      // プランのない日（月・火・木）は、日付と曜日だけを読む（押しても何も起きない）
      expect(isButton('9月7日 月曜日'), isFalse);
      expect(isButton('9月8日 火曜日'), isFalse);
      expect(isButton('9月10日 木曜日'), isFalse);
      handle.dispose();
    });

    testWidgets('7 日は等幅のまま並び、列の位置・高さはそろっている', (tester) async {
      await _pumpCalendar(tester);

      final xs = [
        for (var d = 7; d <= 13; d++) tester.getCenter(find.text('$d')).dx,
      ];
      final gaps = [for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1]];
      for (final g in gaps) {
        expect(g, closeTo(gaps.first, 0.5));
      }
      final ys = {
        for (var d = 7; d <= 13; d++) tester.getCenter(find.text('$d')).dy,
      };
      expect(ys, hasLength(1));
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}・文字 1.35 倍でもはみ出さない（320 幅）', (tester) async {
        await _pumpCalendar(
          tester,
          brightness: brightness,
          textScale: 1.35,
          size: const Size(320, 700),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('詳細シートも文字 1.35 倍でもはみ出さない', (tester) async {
      await _pumpCalendar(tester, textScale: 1.35, size: const Size(390, 1200));

      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('9月9日（水）'), findsOneWidget);
    });
  });
}
