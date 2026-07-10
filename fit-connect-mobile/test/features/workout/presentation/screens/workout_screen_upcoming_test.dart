import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_screen_state.dart';
import 'package:fit_connect_mobile/features/workout/presentation/screens/workout_screen.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/reschedule_date_picker.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';

/// 固定の WorkoutScreenState を返すテスト用Notifier
///
/// WorkoutScreenNotifier.build は Supabase への4クエリを並列実行するため、
/// テストでは build をオーバーライドして固定状態を返す。
class _FakeWorkoutScreenNotifier extends WorkoutScreenNotifier {
  _FakeWorkoutScreenNotifier(this._fixedState);

  final WorkoutScreenState _fixedState;

  @override
  Future<WorkoutScreenState> build() async => _fixedState;
}

/// DateTime を assigned_date 形式（yyyy-MM-dd）に整形するヘルパー
String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 日付チップの期待表示（M/d(E) 形式）を生成するヘルパー
String _dateChipLabel(DateTime d) {
  const labels = ['月', '火', '水', '木', '金', '土', '日'];
  return '${d.month}/${d.day}(${labels[d.weekday - 1]})';
}

/// テスト用の今後の予定アサインメント（未来日・pending）を生成するヘルパー
WorkoutAssignment _makeUpcomingAssignment({
  required int daysAhead,
  required String title,
}) {
  final assignedDate = DateTime.now().add(Duration(days: daysAhead));
  final id = 'upcoming-$daysAhead';
  return WorkoutAssignment(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    planId: 'plan-1',
    assignedDate: _fmtDate(assignedDate),
    status: 'pending',
    planInfo: WorkoutPlanInfo(
      title: title,
      category: 'strength',
      estimatedMinutes: 45,
      planType: 'self_guided',
    ),
    exercises: [
      WorkoutAssignmentExercise(
        id: '$id-ex-1',
        assignmentId: id,
        exerciseName: 'ベンチプレス',
        targetSets: 3,
        targetReps: 10,
        orderIndex: 0,
        isCompleted: false,
      ),
      WorkoutAssignmentExercise(
        id: '$id-ex-2',
        assignmentId: id,
        exerciseName: 'スクワット',
        targetSets: 3,
        targetReps: 12,
        orderIndex: 1,
        isCompleted: false,
      ),
    ],
  );
}

/// 固定状態で WorkoutScreen をポンプするヘルパー
Future<void> _pumpWorkoutScreen(
  WidgetTester tester,
  WorkoutScreenState state,
) async {
  // ListView 内の今後の予定セクションまで表示されるよう縦長ビューポートにする
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workoutScreenNotifierProvider.overrideWith(
          () => _FakeWorkoutScreenNotifier(state),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const WorkoutScreen(),
      ),
    ),
  );
  // AsyncNotifier の Future 解決（ローディング → データ表示）を待つ
  await tester.pumpAndSettle();
}

void main() {
  group('WorkoutScreen 今後の予定セクション', () {
    testWidgets('upcomingAssignments が2件ある場合、ヘッダーと2枚のカードが表示される',
        (WidgetTester tester) async {
      final upcoming1 = _makeUpcomingAssignment(
        daysAhead: 3,
        title: '上半身トレーニング',
      );
      final upcoming2 = _makeUpcomingAssignment(
        daysAhead: 10,
        title: '下半身トレーニング',
      );

      await _pumpWorkoutScreen(
        tester,
        WorkoutScreenState(
          overdueAssignments: const [],
          todayAssignments: const [],
          upcomingAssignments: [upcoming1, upcoming2],
          weeklyData: const {},
        ),
      );

      // ヘッダー（件数付き）
      expect(find.text('今後の予定 (2件)'), findsOneWidget);

      // カードのタイトル
      expect(find.text('上半身トレーニング'), findsOneWidget);
      expect(find.text('下半身トレーニング'), findsOneWidget);

      // M/d(E) 形式の日付チップ
      final date1 = DateTime.now().add(const Duration(days: 3));
      final date2 = DateTime.now().add(const Duration(days: 10));
      expect(find.text(_dateChipLabel(date1)), findsOneWidget);
      expect(find.text(_dateChipLabel(date2)), findsOneWidget);

      // 種目数表示（各カード2種目）
      expect(find.text('2種目'), findsNWidgets(2));
    });

    testWidgets('upcomingAssignments が空の場合、「今後の予定」テキストが表示されない',
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

    testWidgets('各カードに「日付変更」ボタンが表示され、タップで日付ピッカーが開く',
        (WidgetTester tester) async {
      await _pumpWorkoutScreen(
        tester,
        WorkoutScreenState(
          overdueAssignments: const [],
          todayAssignments: const [],
          upcomingAssignments: [
            _makeUpcomingAssignment(daysAhead: 3, title: '上半身トレーニング'),
            _makeUpcomingAssignment(daysAhead: 10, title: '下半身トレーニング'),
          ],
          weeklyData: const {},
        ),
      );

      // 各カードに「日付変更」ボタンがある
      expect(find.text('日付変更'), findsNWidgets(2));

      // タップで RescheduleDatePicker ダイアログが開く
      await tester.tap(find.text('日付変更').first);
      await tester.pumpAndSettle();
      expect(find.byType(RescheduleDatePicker), findsOneWidget);
      expect(find.text('日付を変更'), findsOneWidget);

      // キャンセルで閉じる
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(find.byType(RescheduleDatePicker), findsNothing);
    });

    testWidgets('today も overdue も空で upcoming のみの場合、全空ヒントが表示されない',
        (WidgetTester tester) async {
      await _pumpWorkoutScreen(
        tester,
        WorkoutScreenState(
          overdueAssignments: const [],
          todayAssignments: const [],
          upcomingAssignments: [
            _makeUpcomingAssignment(daysAhead: 3, title: '上半身トレーニング'),
          ],
          weeklyData: const {},
        ),
      );

      // 全空状態のヒント（_EmptyState）は表示されない
      expect(find.textContaining('トレーナーがプランを設定すると'), findsNothing);

      // 代わりに「今日のプランはありません」ヒント + 今後の予定セクションが表示される
      expect(find.text('今日のプランはありません'), findsOneWidget);
      expect(find.text('今後の予定 (1件)'), findsOneWidget);
    });
  });
}
