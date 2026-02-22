import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';

/// ワークアウト画面の表示データ
class WorkoutScreenState {
  /// 期限切れの未完了アサインメント（assigned_date < today, status = 'pending'）
  final List<WorkoutAssignment> overdueAssignments;

  /// 今日のアサインメント（assigned_date = today）
  final List<WorkoutAssignment> todayAssignments;

  /// 週間カレンダー用データ（日付 → アサインメントリスト）
  final Map<DateTime, List<WorkoutAssignment>> weeklyData;

  const WorkoutScreenState({
    required this.overdueAssignments,
    required this.todayAssignments,
    required this.weeklyData,
  });

  /// 全アサインメント（overdue + today）
  List<WorkoutAssignment> get allActionable =>
      [...overdueAssignments, ...todayAssignments];

  /// 空判定
  bool get isEmpty =>
      overdueAssignments.isEmpty && todayAssignments.isEmpty;
}
