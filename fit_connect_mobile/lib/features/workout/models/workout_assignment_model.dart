import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';
import 'workout_assignment_exercise_model.dart';

part 'workout_assignment_model.g.dart';

@JsonSerializable()
class WorkoutPlanInfo {
  final String title;
  final String? description;
  final String category;
  @JsonKey(name: 'estimated_minutes')
  final int? estimatedMinutes;
  @JsonKey(name: 'plan_type')
  final String? planType;

  const WorkoutPlanInfo({
    required this.title,
    this.description,
    required this.category,
    this.estimatedMinutes,
    this.planType,
  });

  factory WorkoutPlanInfo.fromJson(Map<String, dynamic> json) =>
      _$WorkoutPlanInfoFromJson(json);
  Map<String, dynamic> toJson() => _$WorkoutPlanInfoToJson(this);
}

@JsonSerializable()
class WorkoutAssignment {
  final String id;
  @JsonKey(name: 'client_id')
  final String clientId;
  @JsonKey(name: 'trainer_id')
  final String trainerId;
  @JsonKey(name: 'plan_id')
  final String planId;
  @JsonKey(name: 'assigned_date')
  final String assignedDate;
  final String status;
  @NullableDateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @NullableDateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;
  @JsonKey(name: 'trainer_note')
  final String? trainerNote;
  @JsonKey(name: 'client_feedback')
  final String? clientFeedback;
  final int? calories;
  @NullableDateTimeConverter()
  @JsonKey(name: 'started_at')
  final DateTime? startedAt;
  @NullableDateTimeConverter()
  @JsonKey(name: 'finished_at')
  final DateTime? finishedAt;
  @JsonKey(name: 'workout_plans')
  final WorkoutPlanInfo? planInfo;
  @JsonKey(name: 'workout_assignment_exercises')
  final List<WorkoutAssignmentExercise> exercises;

  const WorkoutAssignment({
    required this.id,
    required this.clientId,
    required this.trainerId,
    required this.planId,
    required this.assignedDate,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.trainerNote,
    this.clientFeedback,
    this.calories,
    this.startedAt,
    this.finishedAt,
    this.planInfo,
    this.exercises = const [],
  });

  factory WorkoutAssignment.fromJson(Map<String, dynamic> json) =>
      _$WorkoutAssignmentFromJson(json);
  Map<String, dynamic> toJson() => _$WorkoutAssignmentToJson(this);

  WorkoutAssignment copyWith({
    String? id,
    String? clientId,
    String? trainerId,
    String? planId,
    String? assignedDate,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? trainerNote,
    String? clientFeedback,
    int? calories,
    DateTime? startedAt,
    DateTime? finishedAt,
    WorkoutPlanInfo? planInfo,
    List<WorkoutAssignmentExercise>? exercises,
  }) {
    return WorkoutAssignment(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      trainerId: trainerId ?? this.trainerId,
      planId: planId ?? this.planId,
      assignedDate: assignedDate ?? this.assignedDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trainerNote: trainerNote ?? this.trainerNote,
      clientFeedback: clientFeedback ?? this.clientFeedback,
      calories: calories ?? this.calories,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      planInfo: planInfo ?? this.planInfo,
      exercises: exercises ?? this.exercises,
    );
  }
}
