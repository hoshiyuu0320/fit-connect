import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_screen_state.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';

/// 呼ばれた操作の記録
class WorkoutCalls {
  final List<({String assignmentId, String exerciseId, List<ActualSet> sets})>
      updatedSets = [];
  final List<String> skipped = [];
  final List<String> doneToday = [];
  final List<({String assignmentId, DateTime date})> rescheduled = [];
  final List<({String assignmentId, String? feedback, int? calories})>
      submitted = [];
}

/// 固定の [WorkoutScreenState] を返すテスト用 Notifier（Supabase に出ない）。
/// 画面から呼ばれる操作は [calls] に記録し、必要な分だけ state も更新する。
class FakeWorkoutScreenNotifier extends WorkoutScreenNotifier {
  FakeWorkoutScreenNotifier(
    this._fixedState, {
    WorkoutCalls? calls,
    this.completer,
    this.error,
    this.submitError,
  }) : calls = calls ?? WorkoutCalls();

  final WorkoutScreenState _fixedState;
  final WorkoutCalls calls;

  /// 渡すと、その Future が完了するまで読込中のままにする
  final Completer<WorkoutScreenState>? completer;

  /// 渡すと、読み込みがこの例外で失敗する
  final Object? error;

  /// 渡すと、完了報告の記録がこの例外で失敗する
  final Object? submitError;

  @override
  Future<WorkoutScreenState> build() async {
    if (completer != null) return completer!.future;
    if (error != null) throw error!;
    return _fixedState;
  }

  @override
  Future<void> updateExerciseSets(
    String assignmentId,
    String exerciseId,
    List<ActualSet> actualSets,
  ) async {
    calls.updatedSets.add((
      assignmentId: assignmentId,
      exerciseId: exerciseId,
      sets: List.of(actualSets),
    ));
  }

  @override
  Future<void> skip(String assignmentId) async {
    calls.skipped.add(assignmentId);
  }

  @override
  Future<void> doToday(String assignmentId) async {
    calls.doneToday.add(assignmentId);
  }

  @override
  Future<void> reschedule(String assignmentId, DateTime newDate) async {
    calls.rescheduled.add((assignmentId: assignmentId, date: newDate));
  }

  @override
  Future<void> submitCompletion(
    String assignmentId, {
    String? clientFeedback,
    int? calories,
  }) async {
    if (submitError != null) throw submitError!;
    calls.submitted.add((
      assignmentId: assignmentId,
      feedback: clientFeedback,
      calories: calories,
    ));
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(WorkoutScreenState(
      overdueAssignments: current.overdueAssignments,
      todayAssignments: [
        for (final a in current.todayAssignments)
          a.id == assignmentId
              ? a.copyWith(status: 'completed', calories: calories)
              : a,
      ],
      upcomingAssignments: current.upcomingAssignments,
      weeklyData: current.weeklyData,
    ));
  }
}

String fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 今日から [offset] 日ずらした日付（日付だけ）
DateTime dayFromToday(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset);
}

WorkoutAssignmentExercise makeExercise({
  required String id,
  required String assignmentId,
  required String name,
  int sets = 3,
  int reps = 10,
  double? weight,
  String? memo,
  bool done = false,
  List<ActualSet>? actual,
}) {
  return WorkoutAssignmentExercise(
    id: id,
    assignmentId: assignmentId,
    exerciseName: name,
    targetSets: sets,
    targetReps: reps,
    targetWeight: weight,
    orderIndex: 0,
    isCompleted: done,
    memo: memo,
    actualSets: actual,
  );
}

/// 今日のプラン「上半身」（3 種目）。[doneCount] 個目までを完了にする
WorkoutAssignment makeTodayPlan({int doneCount = 1, String status = 'pending'}) {
  const id = 'today';
  final names = ['ダンベルプレス', 'ラットプルダウン', 'シーテッドロー'];
  final weights = [12.0, 30.0, 25.0];
  return WorkoutAssignment(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    planId: 'plan-today',
    assignedDate: fmtDate(dayFromToday(0)),
    status: status,
    planInfo: const WorkoutPlanInfo(
      title: '上半身',
      description: '肩の動きを確認しながら、ひとつずつ丁寧に。',
      category: '筋トレ',
      planType: 'self_guided',
    ),
    exercises: [
      for (var i = 0; i < 3; i++)
        makeExercise(
          id: 'ex-$i',
          assignmentId: id,
          name: names[i],
          reps: i == 0 ? 10 : 12,
          weight: weights[i],
          memo: i == 1 ? '肘を後ろに引く意識で、反動を使わずに。' : null,
          done: i < doneCount,
          actual: i < doneCount
              ? [
                  for (var s = 1; s <= 3; s++)
                    ActualSet(
                      setNumber: s,
                      reps: i == 0 ? 10 : 12,
                      weight: weights[i],
                      done: true,
                    ),
                ]
              : null,
        ),
    ],
  );
}

/// 日付が過ぎたプラン「下半身」（4 種目・2 日前）
WorkoutAssignment makeOverduePlan({int daysAgo = 2}) {
  const id = 'overdue';
  return WorkoutAssignment(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    planId: 'plan-overdue',
    assignedDate: fmtDate(dayFromToday(-daysAgo)),
    status: 'pending',
    planInfo: const WorkoutPlanInfo(
      title: '下半身',
      category: '筋トレ',
      planType: 'self_guided',
    ),
    exercises: [
      for (var i = 0; i < 4; i++)
        makeExercise(id: 'od-$i', assignmentId: id, name: '種目${i + 1}'),
    ],
  );
}

/// 今後の予定（未来日・pending・4 種目）
WorkoutAssignment makeUpcomingPlan({
  required int daysAhead,
  required String title,
}) {
  final id = 'upcoming-$daysAhead';
  return WorkoutAssignment(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    planId: 'plan-$id',
    assignedDate: fmtDate(dayFromToday(daysAhead)),
    status: 'pending',
    planInfo: WorkoutPlanInfo(
      title: title,
      category: '筋トレ',
      planType: 'self_guided',
    ),
    exercises: [
      for (var i = 0; i < 4; i++)
        makeExercise(id: '$id-$i', assignmentId: id, name: '種目${i + 1}'),
    ],
  );
}

/// 画面サイズ（既定は iPhone 想定 390 × 844）で、テーマ・文字拡大・Riverpod を設定して pump する
Future<void> pumpWorkout(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  List<Override> overrides = const [],
  bool settle = true,

  /// 下部ナビ（FcBottomNavLayout）が足す `MediaQuery.padding.bottom` を再現する（0 なら足さない）
  double bottomPadding = 0,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Supabase に出ないよう、ログイン情報まわりは固定する
        trainerProfileProvider.overrideWith(
          (ref) async => const Trainer(id: 'trainer-1', name: '田中'),
        ),
        currentClientIdProvider.overrideWithValue(null),
        currentTrainerIdProvider.overrideWithValue(null),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: bottomPadding > 0
                ? EdgeInsets.only(bottom: bottomPadding)
                : null,
          ),
          child: c!,
        ),
        home: child,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
