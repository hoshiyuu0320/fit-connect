import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/workout/data/workout_repository.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_screen_state.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

part 'workout_provider.g.dart';

/// WorkoutRepository を提供するProvider
@riverpod
WorkoutRepository workoutRepository(WorkoutRepositoryRef ref) {
  return WorkoutRepository();
}

/// ワークアウト画面の状態を管理するNotifier
///
/// - 初期ロード: 期限切れ・今日・週間の3クエリを並列取得して WorkoutScreenState を返す
/// - [toggleExercise]: 種目の完了状態をDB更新 + ローカルstateの楽観的更新
/// - [updateExerciseSets]: セット記録をDB更新 + 楽観的ローカルstate更新
/// - [submitCompletion]: アサインメントをDB上で完了にしてローカルstateを更新
/// - [doToday]: 期限切れアサインメントを今日のリストに移動
/// - [skip]: 期限切れアサインメントをスキップ
/// - [reschedule]: 期限切れアサインメントの日付を変更
@riverpod
class WorkoutScreenNotifier extends _$WorkoutScreenNotifier {
  @override
  Future<WorkoutScreenState> build() async {
    final clientId = ref.watch(currentClientIdProvider);
    if (clientId == null) {
      return const WorkoutScreenState(
        overdueAssignments: [],
        todayAssignments: [],
        weeklyData: {},
      );
    }

    final repo = ref.watch(workoutRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // 今週の範囲計算（月曜始まり）
    final daysFromMonday = (today.weekday - 1) % 7;
    final weekStart = today.subtract(Duration(days: daysFromMonday));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekStartStr =
        '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
    final weekEndStr =
        '${weekEnd.year}-${weekEnd.month.toString().padLeft(2, '0')}-${weekEnd.day.toString().padLeft(2, '0')}';

    // 並列取得
    final results = await Future.wait([
      repo.getOverdueAssignments(clientId, todayStr),
      repo.getAssignmentsByDate(clientId, todayStr),
      repo.getWeeklyAssignments(clientId, weekStartStr, weekEndStr),
    ]);

    final overdueAssignments = results[0];
    final todayAssignments = results[1];
    final weeklyAssignments = results[2];

    // 週間データをMap化
    final weeklyData = <DateTime, List<WorkoutAssignment>>{};
    for (final a in weeklyAssignments) {
      final parts = a.assignedDate.split('-');
      final date = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      weeklyData.putIfAbsent(date, () => []).add(a);
    }

    return WorkoutScreenState(
      overdueAssignments: overdueAssignments,
      todayAssignments: todayAssignments,
      weeklyData: weeklyData,
    );
  }

  /// 内部ヘルパー: assignmentId で overdue/today 両リストを横断更新
  void _updateAssignment(
    String assignmentId,
    WorkoutAssignment Function(WorkoutAssignment) updater,
  ) {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncData(WorkoutScreenState(
      overdueAssignments: currentState.overdueAssignments.map((a) {
        return a.id == assignmentId ? updater(a) : a;
      }).toList(),
      todayAssignments: currentState.todayAssignments.map((a) {
        return a.id == assignmentId ? updater(a) : a;
      }).toList(),
      weeklyData: currentState.weeklyData,
    ));
  }

  /// 種目の完了状態をトグル（DB更新 + ローカルstateの楽観的更新）
  Future<void> toggleExercise(
    String assignmentId,
    String exerciseId,
  ) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // 対象の種目を探して現在の完了状態を取得
    final allAssignments = currentState.allActionable;
    final assignment = allAssignments.firstWhere((a) => a.id == assignmentId);
    final exercise = assignment.exercises.firstWhere((e) => e.id == exerciseId);
    final newIsCompleted = !exercise.isCompleted;

    // DB更新
    final repo = ref.read(workoutRepositoryProvider);
    await repo.toggleExerciseCompletion(exerciseId, newIsCompleted);

    _updateAssignment(assignmentId, (a) {
      return a.copyWith(
        exercises: a.exercises.map((e) {
          if (e.id != exerciseId) return e;
          return e.copyWith(
            isCompleted: newIsCompleted,
            completedAt: newIsCompleted ? DateTime.now() : null,
          );
        }).toList(),
      );
    });
  }

  /// セット記録を更新（DB更新 + 楽観的ローカルstate更新）
  Future<void> updateExerciseSets(
    String assignmentId,
    String exerciseId,
    List<ActualSet> actualSets,
  ) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // DB更新
    final repo = ref.read(workoutRepositoryProvider);
    await repo.updateActualSets(exerciseId, actualSets);

    // 全セットdone判定
    final allDone = actualSets.isNotEmpty && actualSets.every((s) => s.done);

    _updateAssignment(assignmentId, (a) {
      return a.copyWith(
        exercises: a.exercises.map((e) {
          if (e.id != exerciseId) return e;
          return e.copyWith(
            actualSets: actualSets,
            isCompleted: allDone,
            completedAt: allDone ? DateTime.now() : null,
          );
        }).toList(),
      );
    });
  }

  /// アサインメントを完了報告する（DB更新 + ローカルstate更新）
  ///
  /// メッセージ送信は呼び出し元（UI）で行う。
  Future<void> submitCompletion(
    String assignmentId, {
    String? clientFeedback,
  }) async {
    final repo = ref.read(workoutRepositoryProvider);
    await repo.completeAssignment(assignmentId, clientFeedback: clientFeedback);

    _updateAssignment(assignmentId, (a) {
      return a.copyWith(status: 'completed', finishedAt: DateTime.now());
    });
  }

  /// 未完了アサインメントを「今日やる」に変更（DB更新後にデータを再取得して画面全体を更新）
  Future<void> doToday(String assignmentId) async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final repo = ref.read(workoutRepositoryProvider);
    await repo.rescheduleAssignment(assignmentId, todayStr);

    // 週間カレンダー等を含めて画面全体を再描画するためinvalidate
    ref.invalidateSelf();
  }

  /// 未完了アサインメントをスキップ（overdueリストから除去）
  Future<void> skip(String assignmentId) async {
    final repo = ref.read(workoutRepositoryProvider);
    await repo.skipAssignment(assignmentId);

    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncData(WorkoutScreenState(
      overdueAssignments: currentState.overdueAssignments
          .where((a) => a.id != assignmentId)
          .toList(),
      todayAssignments: currentState.todayAssignments,
      weeklyData: currentState.weeklyData,
    ));
  }

  /// 未完了アサインメントの日付を変更（DB更新後にデータを再取得して画面全体を更新）
  Future<void> reschedule(String assignmentId, DateTime newDate) async {
    final newDateStr =
        '${newDate.year}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}';

    final repo = ref.read(workoutRepositoryProvider);
    await repo.rescheduleAssignment(assignmentId, newDateStr);

    // 週間カレンダー等を含めて画面全体を再描画するためinvalidate
    ref.invalidateSelf();
  }
}

/// 完了済みワークアウトアサインメントを取得するProvider
@riverpod
Future<List<WorkoutAssignment>> completedWorkoutAssignments(
  CompletedWorkoutAssignmentsRef ref, {
  PeriodFilter period = PeriodFilter.week,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return [];

  final repo = ref.watch(workoutRepositoryProvider);
  return repo.getCompletedAssignments(clientId, period);
}
