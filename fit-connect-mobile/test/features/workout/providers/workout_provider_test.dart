import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/workout/data/workout_repository.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_screen_state.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';

/// 固定の WorkoutScreenState を返すテスト用Notifier
class _FakeWorkoutScreenNotifier extends WorkoutScreenNotifier {
  _FakeWorkoutScreenNotifier(this._fixedState);

  final WorkoutScreenState _fixedState;

  @override
  Future<WorkoutScreenState> build() async => _fixedState;
}

/// 書き込みの完了タイミングをテストから制御できる WorkoutRepository
class _FakeWorkoutRepository extends WorkoutRepository {
  /// updateActualSets の呼び出しごとの (送信内容, 完了用Completer)
  final writes = <(List<ActualSet>, Completer<void>)>[];

  /// DB上の actual_sets（書き込みが完了した順に反映）
  List<ActualSet>? savedSets;

  int inFlight = 0;
  int maxInFlight = 0;
  bool completeCalled = false;
  bool pendingWritesWhenCompleted = false;

  @override
  Future<void> updateActualSets(
    String exerciseId,
    List<ActualSet> actualSets,
  ) async {
    final completer = Completer<void>();
    writes.add((actualSets, completer));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await completer.future;
      savedSets = actualSets;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<void> completeAssignment(
    String assignmentId, {
    String? clientFeedback,
    int? calories,
  }) async {
    completeCalled = true;
    pendingWritesWhenCompleted = inFlight > 0;
  }

  /// 未完了の書き込みを順に完了させる
  Future<void> completeAllWrites() async {
    while (true) {
      final pending = writes.where((w) => !w.$2.isCompleted).toList();
      if (pending.isEmpty) return;
      pending.first.$2.complete();
      await pumpEventQueue();
    }
  }
}

const _assignmentId = 'assignment-1';
const _exerciseId = 'exercise-1';

WorkoutScreenState _initialState() {
  return const WorkoutScreenState(
    overdueAssignments: [],
    todayAssignments: [
      WorkoutAssignment(
        id: _assignmentId,
        clientId: 'client-1',
        trainerId: 'trainer-1',
        planId: 'plan-1',
        assignedDate: '2026-10-12',
        status: 'pending',
        exercises: [
          WorkoutAssignmentExercise(
            id: _exerciseId,
            assignmentId: _assignmentId,
            exerciseName: 'ベンチプレス',
            targetSets: 3,
            targetReps: 10,
            orderIndex: 0,
            isCompleted: false,
          ),
        ],
      ),
    ],
    upcomingAssignments: [],
    weeklyData: {},
  );
}

List<ActualSet> _sets(List<bool> done) => [
      for (var i = 0; i < done.length; i++)
        ActualSet(setNumber: i + 1, reps: 10, weight: 40, done: done[i]),
    ];

void main() {
  late _FakeWorkoutRepository repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _FakeWorkoutRepository();
    container = ProviderContainer(overrides: [
      workoutRepositoryProvider.overrideWithValue(repo),
      workoutScreenNotifierProvider
          .overrideWith(() => _FakeWorkoutScreenNotifier(_initialState())),
    ]);
    addTearDown(container.dispose);
    // autoDispose のため購読して state を保持する
    container.listen(workoutScreenNotifierProvider, (_, __) {});
    await container.read(workoutScreenNotifierProvider.future);
  });

  WorkoutAssignmentExercise exerciseInState() => container
      .read(workoutScreenNotifierProvider)
      .requireValue
      .todayAssignments
      .single
      .exercises
      .single;

  group('WorkoutScreenNotifier.updateExerciseSets', () {
    test('立て続けに呼んでも書き込みは直列化され、最後の状態がDBに保存される', () async {
      final notifier = container.read(workoutScreenNotifierProvider.notifier);

      final f1 = notifier.updateExerciseSets(
          _assignmentId, _exerciseId, _sets([true, false, false]));
      final f2 = notifier.updateExerciseSets(
          _assignmentId, _exerciseId, _sets([true, true, false]));
      final f3 = notifier.updateExerciseSets(
          _assignmentId, _exerciseId, _sets([true, true, true]));

      // 画面上は最新の状態が即座に反映される
      expect(exerciseInState().actualSets!.map((s) => s.done),
          [true, true, true]);
      expect(exerciseInState().isCompleted, isTrue);

      await repo.completeAllWrites();
      await Future.wait([f1, f2, f3]);

      // 同時に走る書き込みは常に1件まで
      expect(repo.maxInFlight, 1);
      // 1件目の送信中に届いた2件目は最新の3件目にまとめられる
      expect(repo.writes.map((w) => w.$1.map((s) => s.done).toList()), [
        [true, false, false],
        [true, true, true],
      ]);
      expect(repo.savedSets!.map((s) => s.done), [true, true, true]);
      expect(exerciseInState().isCompleted, isTrue);
    });

    test('呼び出し後に元のリストを書き換えても送信内容は変わらない', () async {
      final notifier = container.read(workoutScreenNotifierProvider.notifier);
      final mutable = _sets([true, false, false]);

      final f = notifier.updateExerciseSets(_assignmentId, _exerciseId, mutable);
      mutable[1] = mutable[1].copyWith(done: true);

      await repo.completeAllWrites();
      await f;

      expect(repo.savedSets!.map((s) => s.done), [true, false, false]);
      expect(exerciseInState().actualSets!.map((s) => s.done),
          [true, false, false]);
    });

    test('書き込みに失敗するとDBの状態を再取得して例外を投げる', () async {
      final failingRepo = _FailingWorkoutRepository();
      final c = ProviderContainer(overrides: [
        workoutRepositoryProvider.overrideWithValue(failingRepo),
        workoutScreenNotifierProvider
            .overrideWith(() => _FakeWorkoutScreenNotifier(_initialState())),
      ]);
      addTearDown(c.dispose);
      c.listen(workoutScreenNotifierProvider, (_, __) {});
      await c.read(workoutScreenNotifierProvider.future);

      final future = c
          .read(workoutScreenNotifierProvider.notifier)
          .updateExerciseSets(
              _assignmentId, _exerciseId, _sets([true, true, true]));

      await expectLater(future, throwsException);
      final reloaded = await c.read(workoutScreenNotifierProvider.future);
      expect(reloaded.todayAssignments.single.exercises.single.isCompleted,
          isFalse);
    });
  });

  group('WorkoutScreenNotifier.submitCompletion', () {
    test('送信待ちのセット記録をすべて保存してから完了にする', () async {
      final notifier = container.read(workoutScreenNotifierProvider.notifier);

      notifier.updateExerciseSets(
          _assignmentId, _exerciseId, _sets([true, true, false]));
      notifier.updateExerciseSets(
          _assignmentId, _exerciseId, _sets([true, true, true]));

      final submit = notifier.submitCompletion(_assignmentId);
      await pumpEventQueue();
      expect(repo.completeCalled, isFalse);

      await repo.completeAllWrites();
      await submit;

      expect(repo.completeCalled, isTrue);
      expect(repo.pendingWritesWhenCompleted, isFalse);
      expect(repo.savedSets!.map((s) => s.done), [true, true, true]);
      expect(
        container
            .read(workoutScreenNotifierProvider)
            .requireValue
            .todayAssignments
            .single
            .status,
        'completed',
      );
    });

    test('未完了の種目がある場合は完了にしない', () async {
      final notifier = container.read(workoutScreenNotifierProvider.notifier);

      notifier.updateExerciseSets(
          _assignmentId, _exerciseId, _sets([true, true, true]));
      notifier.updateExerciseSets(
          _assignmentId, _exerciseId, _sets([true, true, false]));

      final submit = expectLater(
          notifier.submitCompletion(_assignmentId), throwsStateError);
      await repo.completeAllWrites();

      await submit;
      expect(repo.completeCalled, isFalse);
    });
  });
}

class _FailingWorkoutRepository extends WorkoutRepository {
  @override
  Future<void> updateActualSets(
    String exerciseId,
    List<ActualSet> actualSets,
  ) async {
    throw Exception('network error');
  }
}
