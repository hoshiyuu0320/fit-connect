import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_screen_state.dart';
import 'package:fit_connect_mobile/features/workout/presentation/screens/workout_screen.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/reschedule_date_picker.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_format.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';

import '../workout_test_helpers.dart';

/// 固定状態で WorkoutScreen をポンプする
Future<WorkoutCalls> _pumpWorkoutScreen(
  WidgetTester tester,
  WorkoutScreenState state,
) async {
  final calls = WorkoutCalls();
  await pumpWorkout(
    tester,
    const WorkoutScreen(),
    // ListView 内の今後の予定セクションまで表示されるよう縦長のビューポートにする
    size: const Size(390, 1800),
    overrides: [
      workoutScreenNotifierProvider.overrideWith(
        () => FakeWorkoutScreenNotifier(state, calls: calls),
      ),
    ],
  );
  return calls;
}

void main() {
  group('WorkoutScreen 今後の予定セクション', () {
    testWidgets('upcomingAssignments が2件ある場合、ヘッダーと2行が表示される',
        (WidgetTester tester) async {
      await _pumpWorkoutScreen(
        tester,
        WorkoutScreenState(
          overdueAssignments: const [],
          todayAssignments: const [],
          upcomingAssignments: [
            makeUpcomingPlan(daysAhead: 3, title: '上半身トレーニング'),
            makeUpcomingPlan(daysAhead: 10, title: '下半身トレーニング'),
          ],
          weeklyData: const {},
        ),
      );

      // 見出し（件数つき・全角かっこ）
      expect(find.text('今後の予定（2件）'), findsOneWidget);

      // 行のタイトル
      expect(find.text('上半身トレーニング'), findsOneWidget);
      expect(find.text('下半身トレーニング'), findsOneWidget);

      // 日付は「9/16（水）」の形
      expect(
        find.text(formatWorkoutShortDate(dayFromToday(3))),
        findsOneWidget,
      );
      expect(
        find.text(formatWorkoutShortDate(dayFromToday(10))),
        findsOneWidget,
      );

      // 種目数（各行 4 種目）
      expect(find.text('4種目'), findsNWidgets(2));
    });

    testWidgets('upcomingAssignments が空の場合、「今後の予定」が表示されない',
        (WidgetTester tester) async {
      await _pumpWorkoutScreen(
        tester,
        const WorkoutScreenState(
          overdueAssignments: [],
          todayAssignments: [],
          upcomingAssignments: [],
          weeklyData: {},
        ),
      );

      expect(find.textContaining('今後の予定'), findsNothing);
    });

    testWidgets('各行に「日付を変更」が表示され、押すと日付ピッカーが開く',
        (WidgetTester tester) async {
      final calls = await _pumpWorkoutScreen(
        tester,
        WorkoutScreenState(
          overdueAssignments: const [],
          todayAssignments: const [],
          upcomingAssignments: [
            makeUpcomingPlan(daysAhead: 3, title: '上半身トレーニング'),
            makeUpcomingPlan(daysAhead: 10, title: '下半身トレーニング'),
          ],
          weeklyData: const {},
        ),
      );

      // 各行に「日付を変更」がある
      expect(find.text('日付を変更'), findsNWidgets(2));

      // 押すと RescheduleDatePicker ダイアログが開く（ダイアログの見出しも「日付を変更」）
      await tester.tap(find.text('日付を変更').first);
      await tester.pumpAndSettle();
      expect(find.byType(RescheduleDatePicker), findsOneWidget);
      expect(find.text('日付を変更'), findsNWidgets(3));

      // キャンセルで閉じる（変更は起きない）
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(find.byType(RescheduleDatePicker), findsNothing);
      expect(calls.rescheduled, isEmpty);
    });

    testWidgets('日付ピッカーで「変更する」を押すと、その行のプランの日付変更が呼ばれる',
        (WidgetTester tester) async {
      final calls = await _pumpWorkoutScreen(
        tester,
        WorkoutScreenState(
          overdueAssignments: const [],
          todayAssignments: const [],
          upcomingAssignments: [
            makeUpcomingPlan(daysAhead: 3, title: '上半身トレーニング'),
          ],
          weeklyData: const {},
        ),
      );

      await tester.tap(find.text('日付を変更').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('変更する'));
      await tester.pumpAndSettle();

      expect(calls.rescheduled, hasLength(1));
      expect(calls.rescheduled.single.assignmentId, 'upcoming-3');
      // 日付ピッカーは明日が初期値（時刻は気にしない）
      final picked = calls.rescheduled.single.date;
      expect(
        DateTime(picked.year, picked.month, picked.day),
        dayFromToday(1),
      );
    });

    testWidgets('today も overdue も空で upcoming のみの場合も「今日のプランはありません」を示す',
        (WidgetTester tester) async {
      await _pumpWorkoutScreen(
        tester,
        WorkoutScreenState(
          overdueAssignments: const [],
          todayAssignments: const [],
          upcomingAssignments: [
            makeUpcomingPlan(daysAhead: 3, title: '上半身トレーニング'),
          ],
          weeklyData: const {},
        ),
      );

      // 今日のプランが無い日は、今後の予定があっても同じメッセージ
      expect(find.text('今日のプランはありません'), findsOneWidget);
      expect(
        find.text('田中トレーナーがプランを設定すると、ここに表示されます。'),
        findsOneWidget,
      );
      expect(find.text('今後の予定（1件）'), findsOneWidget);
    });
  });
}
