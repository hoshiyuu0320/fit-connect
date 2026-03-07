import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

class WorkoutRepository {
  /// 指定日のアサインメントを取得
  Future<List<WorkoutAssignment>> getAssignmentsByDate(
    String clientId,
    String date,
  ) async {
    final data = await SupabaseService.client
        .from('workout_assignments')
        .select(
          '*, workout_plans(title, description, category, estimated_minutes, plan_type), workout_assignment_exercises(*)',
        )
        .eq('client_id', clientId)
        .eq('assigned_date', date)
        .order('created_at');

    final assignments = data
        .map((json) => WorkoutAssignment.fromJson(json))
        .where((a) => a.planInfo?.planType == 'self_guided')
        .toList();

    // exercises を order_index でソート
    return assignments.map((assignment) {
      final sorted = [...assignment.exercises]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return assignment.copyWith(exercises: sorted);
    }).toList();
  }

  /// 種目の完了状態をトグル
  Future<void> toggleExerciseCompletion(
    String exerciseId,
    bool isCompleted,
  ) async {
    await SupabaseService.client.from('workout_assignment_exercises').update({
      'is_completed': isCompleted,
      'completed_at':
          isCompleted ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', exerciseId);
  }

  /// セット実績を更新（全セットdone時は種目も完了扱い）
  Future<void> updateActualSets(
    String exerciseId,
    List<ActualSet> actualSets,
  ) async {
    final allDone = actualSets.isNotEmpty && actualSets.every((s) => s.done);
    await SupabaseService.client.from('workout_assignment_exercises').update({
      'actual_sets': actualSets.map((s) => s.toJson()).toList(),
      'is_completed': allDone,
      'completed_at': allDone ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', exerciseId);
  }

  /// 期間指定で完了済みアサインメントを取得
  Future<List<WorkoutAssignment>> getCompletedAssignments(
    String clientId,
    PeriodFilter period, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = SupabaseService.client
        .from('workout_assignments')
        .select(
          '*, workout_plans(title, description, category, estimated_minutes, plan_type), workout_assignment_exercises(*)',
        )
        .eq('client_id', clientId)
        .eq('status', 'completed');

    if (startDate != null || endDate != null) {
      // startDate/endDate が指定された場合はそちらを優先
      if (startDate != null) {
        final startDateStr =
            '${startDate.year.toString().padLeft(4, '0')}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
        query = query.gte('assigned_date', startDateStr);
      }
      if (endDate != null) {
        final endDateStr =
            '${endDate.year.toString().padLeft(4, '0')}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
        query = query.lte('assigned_date', endDateStr);
      }
    } else if (period != PeriodFilter.all) {
      final periodStart = period.getStartDate();
      final startDateStr =
          '${periodStart.year.toString().padLeft(4, '0')}-${periodStart.month.toString().padLeft(2, '0')}-${periodStart.day.toString().padLeft(2, '0')}';
      query = query.gte('assigned_date', startDateStr);
    }

    final data = await query.order('finished_at', ascending: false);

    final assignments = data
        .map((json) => WorkoutAssignment.fromJson(json))
        .where((a) => a.planInfo?.planType == 'self_guided')
        .toList();

    // exercises を order_index でソート
    return assignments.map((assignment) {
      final sorted = [...assignment.exercises]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return assignment.copyWith(exercises: sorted);
    }).toList();
  }

  /// アサインメント全体を完了にする
  Future<void> completeAssignment(
    String assignmentId, {
    String? clientFeedback,
    int? calories,
  }) async {
    final updateData = <String, dynamic>{
      'status': 'completed',
      'finished_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (clientFeedback != null && clientFeedback.isNotEmpty) {
      updateData['client_feedback'] = clientFeedback;
    }

    if (calories != null) {
      updateData['calories'] = calories;
    }

    await SupabaseService.client
        .from('workout_assignments')
        .update(updateData)
        .eq('id', assignmentId);
  }

  /// 期限切れの未完了アサインメントを取得
  /// assigned_date < today かつ status = 'pending' かつ self_guided
  Future<List<WorkoutAssignment>> getOverdueAssignments(
    String clientId,
    String todayStr,
  ) async {
    final data = await SupabaseService.client
        .from('workout_assignments')
        .select(
          '*, workout_plans(title, description, category, estimated_minutes, plan_type), workout_assignment_exercises(*)',
        )
        .eq('client_id', clientId)
        .eq('status', 'pending')
        .lt('assigned_date', todayStr)
        .order('assigned_date', ascending: true);

    final assignments = data
        .map((json) => WorkoutAssignment.fromJson(json))
        .where((a) => a.planInfo?.planType == 'self_guided')
        .toList();

    return assignments.map((assignment) {
      final sorted = [...assignment.exercises]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return assignment.copyWith(exercises: sorted);
    }).toList();
  }

  /// アサインメントをスキップする
  Future<void> skipAssignment(String assignmentId) async {
    await SupabaseService.client.from('workout_assignments').update({
      'status': 'skipped',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', assignmentId);
  }

  /// アサインメントの実施日を変更する
  Future<void> rescheduleAssignment(
    String assignmentId,
    String newDateStr,
  ) async {
    await SupabaseService.client.from('workout_assignments').update({
      'assigned_date': newDateStr,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', assignmentId);
  }

  /// 指定週のアサインメントを取得（カレンダー表示用）
  Future<List<WorkoutAssignment>> getWeeklyAssignments(
    String clientId,
    String weekStartStr,
    String weekEndStr,
  ) async {
    final data = await SupabaseService.client
        .from('workout_assignments')
        .select(
          '*, workout_plans(title, description, category, estimated_minutes, plan_type), workout_assignment_exercises(*)',
        )
        .eq('client_id', clientId)
        .gte('assigned_date', weekStartStr)
        .lte('assigned_date', weekEndStr)
        .order('assigned_date', ascending: true);

    final assignments = data
        .map((json) => WorkoutAssignment.fromJson(json))
        .where((a) => a.planInfo?.planType == 'self_guided')
        .toList();

    // exercises を order_index でソート
    return assignments.map((assignment) {
      final sorted = [...assignment.exercises]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return assignment.copyWith(exercises: sorted);
    }).toList();
  }
}
