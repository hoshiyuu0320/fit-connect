import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/exercise_records/data/exercise_repository.dart';
import 'package:fit_connect_mobile/features/exercise_records/models/exercise_record_model.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';
import 'package:fit_connect_mobile/features/workout/data/workout_repository.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

/// 運動の画面テスト用の偽リポジトリ（Supabase に出ない）。本物と同じ向きで期間を絞る。
class FakeExerciseRepository implements ExerciseRepository {
  FakeExerciseRepository(this.records, {this.failWith});

  final List<ExerciseRecord> records;
  Object? failWith;

  /// 非 null のあいだは一覧の取得が完了しない
  Completer<void>? gate;

  /// 取得に渡された運動の種類（絞り込みを画面側で行っていることの確認用）
  final List<String?> requestedTypes = [];

  @override
  Future<List<ExerciseRecord>> getExerciseRecords({
    required String clientId,
    PeriodFilter? period,
    String? exerciseType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    requestedTypes.add(exerciseType);
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    return records.where((r) {
      if (exerciseType != null && r.exerciseType != exerciseType) return false;
      if (startDate != null || endDate != null) {
        if (startDate != null && r.recordedAt.isBefore(startDate)) {
          return false;
        }
        if (endDate != null && r.recordedAt.isAfter(endDate)) return false;
        return true;
      }
      if (period != null && period != PeriodFilter.all) {
        return !r.recordedAt.isBefore(period.getStartDate());
      }
      return true;
    }).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  }

  @override
  Future<Map<String, int>> getExerciseTypeCounts({
    required String clientId,
    required PeriodFilter period,
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      {};

  @override
  Future<Map<DateTime, List<String>>> getWeeklyExerciseData({
    required String clientId,
    required DateTime startDate,
    required DateTime endDate,
  }) async =>
      {};

  @override
  Future<Map<DateTime, int>> getExerciseRecordCounts({
    required String clientId,
    required DateTime startDate,
    required DateTime endDate,
  }) async =>
      {};

  @override
  Future<double> getTotalCalories({
    required String clientId,
    required PeriodFilter period,
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      0;

  @override
  Future<int> getWeeklyExerciseCount(String clientId) async => 0;

  @override
  Future<ExerciseRecord> createExerciseRecord({
    required String clientId,
    required String exerciseType,
    String? memo,
    List<String>? images,
    int? duration,
    double? distance,
    double? calories,
    DateTime? recordedAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<ExerciseRecord> updateExerciseRecord({
    required String id,
    String? exerciseType,
    String? memo,
    List<String>? images,
    int? duration,
    double? distance,
    double? calories,
    DateTime? recordedAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteExerciseRecord(String id) => throw UnimplementedError();
}

/// 完了したプランの偽リポジトリ
class FakeWorkoutRepository extends WorkoutRepository {
  FakeWorkoutRepository(this.assignments, {this.failWith});

  final List<WorkoutAssignment> assignments;
  Object? failWith;

  @override
  Future<List<WorkoutAssignment>> getCompletedAssignments(
    String clientId,
    PeriodFilter period, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (failWith != null) throw failWith!;
    return assignments.where((a) {
      final day = _assignedDay(a);
      if (startDate != null || endDate != null) {
        if (startDate != null &&
            day.isBefore(
              DateTime(startDate.year, startDate.month, startDate.day),
            )) {
          return false;
        }
        if (endDate != null &&
            day.isAfter(DateTime(endDate.year, endDate.month, endDate.day))) {
          return false;
        }
        return true;
      }
      if (period != PeriodFilter.all) {
        final start = period.getStartDate();
        return !day.isBefore(DateTime(start.year, start.month, start.day));
      }
      return true;
    }).toList();
  }

  static DateTime _assignedDay(WorkoutAssignment a) {
    final parts = a.assignedDate.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }
}

ExerciseRecord testExercise(
  String id,
  String type,
  DateTime recordedAt, {
  String? memo,
  int? duration,
  double? distance,
  double? calories,
  String source = 'message',
}) {
  return ExerciseRecord(
    id: id,
    clientId: 'client-1',
    exerciseType: type,
    memo: memo,
    duration: duration,
    distance: distance,
    calories: calories,
    recordedAt: recordedAt,
    source: source,
    createdAt: recordedAt,
    updatedAt: recordedAt,
  );
}

WorkoutAssignment testAssignment(
  String id,
  DateTime finishedAt, {
  String title = '全身',
  int exerciseCount = 4,
  int? calories,
  String? feedback,
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  return WorkoutAssignment(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    planId: 'plan-$id',
    assignedDate:
        '${finishedAt.year}-${two(finishedAt.month)}-${two(finishedAt.day)}',
    status: 'completed',
    finishedAt: finishedAt,
    calories: calories,
    clientFeedback: feedback,
    planInfo: WorkoutPlanInfo(
      title: title,
      category: '全身',
      planType: 'self_guided',
    ),
    exercises: [
      for (var i = 0; i < exerciseCount; i++)
        WorkoutAssignmentExercise(
          id: '$id-e$i',
          assignmentId: id,
          exerciseName: '種目$i',
          targetSets: 3,
          targetReps: 10,
          orderIndex: i,
          isCompleted: true,
        ),
    ],
  );
}

/// 今週の月曜から [offset] 日後の指定時刻（offset は 0〜6）
DateTime thisWeekAt(int offset, int hour, int minute) {
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day + offset, hour, minute);
}

/// 縦に長い画面（一覧の下の方まで作られるように）で pump する
Future<void> pumpExerciseScreen(
  WidgetTester tester,
  Widget screen, {
  required FakeExerciseRepository exercises,
  required FakeWorkoutRepository workouts,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 2600),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentClientIdProvider.overrideWith((ref) => 'client-1'),
        exerciseRepositoryProvider.overrideWithValue(exercises),
        workoutRepositoryProvider.overrideWithValue(workouts),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
