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
/// - 初期ロード: 期限切れ・今日・週間・今後の予定の4クエリを並列取得して WorkoutScreenState を返す
/// - [toggleExercise]: 種目の完了状態をDB更新 + ローカルstateの楽観的更新
/// - [updateExerciseSets]: セット記録を楽観的にローカルstate更新し、種目ごとに直列化してDB更新
/// - [submitCompletion]: 送信待ちのセット記録を保存後、アサインメントをDB上で完了にしてローカルstateを更新
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
        upcomingAssignments: [],
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
      repo.getUpcomingAssignments(clientId),
    ]);

    final overdueAssignments = results[0];
    final todayAssignments = results[1];
    final weeklyAssignments = results[2];
    final upcomingAssignments = results[3];

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
      upcomingAssignments: upcomingAssignments,
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
      upcomingAssignments: currentState.upcomingAssignments,
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

  /// 種目ごとの未送信のセット記録（最新の要求のみ保持）
  final Map<String, List<ActualSet>> _pendingSets = {};

  /// 種目ごとの実行中のセット記録書き込み
  final Map<String, Future<void>> _setsWrites = {};

  /// セット記録を更新（楽観的ローカルstate更新 + DB更新）
  ///
  /// 連続で呼ばれても書き込みは種目ごとに直列化し、送信待ちの間に届いた
  /// 要求は最新のものだけを送る。返り値の Future は、この呼び出し以降の
  /// 最新のセット記録がDBに保存された時点で完了する。
  /// 書き込みに失敗した場合はDBの状態を再取得してから例外を投げ直す。
  Future<void> updateExerciseSets(
    String assignmentId,
    String exerciseId,
    List<ActualSet> actualSets,
  ) {
    final currentState = state.valueOrNull;
    if (currentState == null) return Future.value();

    // 呼び出し元の可変リストを共有しないよう複製する
    final snapshot = List<ActualSet>.unmodifiable(actualSets);

    // 全セットdone判定
    final allDone = snapshot.isNotEmpty && snapshot.every((s) => s.done);

    _updateAssignment(assignmentId, (a) {
      return a.copyWith(
        exercises: a.exercises.map((e) {
          if (e.id != exerciseId) return e;
          return e.copyWith(
            actualSets: snapshot,
            isCompleted: allDone,
            completedAt: allDone ? (e.completedAt ?? DateTime.now()) : null,
          );
        }).toList(),
      );
    });

    _pendingSets[exerciseId] = snapshot;
    return _setsWrites[exerciseId] ??= _drainSetsWrites(exerciseId);
  }

  /// 送信待ちのセット記録がなくなるまで、最新の要求を1件ずつDBへ書き込む
  Future<void> _drainSetsWrites(String exerciseId) async {
    final repo = ref.read(workoutRepositoryProvider);
    try {
      while (true) {
        final sets = _pendingSets.remove(exerciseId);
        if (sets == null) break;
        await repo.updateActualSets(exerciseId, sets);
      }
    } catch (_) {
      _pendingSets.remove(exerciseId);
      // 楽観的に更新したローカルstateがDBとずれるため再取得する
      ref.invalidateSelf();
      rethrow;
    } finally {
      _setsWrites.remove(exerciseId);
    }
  }

  /// アサインメントを完了報告する（DB更新 + ローカルstate更新）
  ///
  /// メッセージ送信は呼び出し元（UI）で行う。
  Future<void> submitCompletion(
    String assignmentId, {
    String? clientFeedback,
    int? calories,
  }) async {
    // 送信待ちのセット記録をすべて保存してから完了にする
    await Future.wait(_setsWrites.values.toList());

    final assignment = state.valueOrNull?.allActionable
        .where((a) => a.id == assignmentId)
        .firstOrNull;
    if (assignment != null &&
        !assignment.exercises.every((e) => e.isCompleted)) {
      throw StateError('未完了の種目があるため完了報告できません');
    }

    final repo = ref.read(workoutRepositoryProvider);
    await repo.completeAssignment(
      assignmentId,
      clientFeedback: clientFeedback,
      calories: calories,
    );

    _updateAssignment(assignmentId, (a) {
      return a.copyWith(
        status: 'completed',
        finishedAt: DateTime.now(),
        calories: calories,
      );
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
      upcomingAssignments: currentState.upcomingAssignments,
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
  DateTime? startDate,
  DateTime? endDate,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return [];

  final repo = ref.watch(workoutRepositoryProvider);
  return repo.getCompletedAssignments(clientId, period, startDate: startDate, endDate: endDate);
}
