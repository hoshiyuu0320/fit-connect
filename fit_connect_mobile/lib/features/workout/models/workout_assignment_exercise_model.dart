import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';
import 'actual_set_model.dart';

part 'workout_assignment_exercise_model.g.dart';

@JsonSerializable()
class WorkoutAssignmentExercise {
  final String id;
  @JsonKey(name: 'assignment_id')
  final String assignmentId;
  @JsonKey(name: 'exercise_name')
  final String exerciseName;
  @JsonKey(name: 'target_sets')
  final int targetSets;
  @JsonKey(name: 'target_reps')
  final int targetReps;
  @JsonKey(name: 'target_weight')
  final double? targetWeight;
  @JsonKey(name: 'order_index')
  final int orderIndex;
  @JsonKey(
      name: 'actual_sets',
      fromJson: _actualSetsFromJson,
      toJson: _actualSetsToJson)
  final List<ActualSet>? actualSets;
  @JsonKey(name: 'is_completed')
  final bool isCompleted;
  @NullableDateTimeConverter()
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;
  final String? memo;
  @JsonKey(name: 'linked_exercise_id')
  final String? linkedExerciseId;
  @NullableDateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  const WorkoutAssignmentExercise({
    required this.id,
    required this.assignmentId,
    required this.exerciseName,
    required this.targetSets,
    required this.targetReps,
    this.targetWeight,
    required this.orderIndex,
    this.actualSets,
    required this.isCompleted,
    this.completedAt,
    this.memo,
    this.linkedExerciseId,
    this.createdAt,
  });

  factory WorkoutAssignmentExercise.fromJson(Map<String, dynamic> json) =>
      _$WorkoutAssignmentExerciseFromJson(json);
  Map<String, dynamic> toJson() => _$WorkoutAssignmentExerciseToJson(this);

  WorkoutAssignmentExercise copyWith({
    String? id,
    String? assignmentId,
    String? exerciseName,
    int? targetSets,
    int? targetReps,
    double? targetWeight,
    int? orderIndex,
    List<ActualSet>? actualSets,
    bool? isCompleted,
    DateTime? completedAt,
    String? memo,
    String? linkedExerciseId,
    DateTime? createdAt,
  }) {
    return WorkoutAssignmentExercise(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      exerciseName: exerciseName ?? this.exerciseName,
      targetSets: targetSets ?? this.targetSets,
      targetReps: targetReps ?? this.targetReps,
      targetWeight: targetWeight ?? this.targetWeight,
      orderIndex: orderIndex ?? this.orderIndex,
      actualSets: actualSets ?? this.actualSets,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      memo: memo ?? this.memo,
      linkedExerciseId: linkedExerciseId ?? this.linkedExerciseId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

List<ActualSet>? _actualSetsFromJson(dynamic json) {
  if (json == null) return null;
  return (json as List<dynamic>)
      .map((e) => ActualSet.fromJson(e as Map<String, dynamic>))
      .toList();
}

List<Map<String, dynamic>>? _actualSetsToJson(List<ActualSet>? sets) {
  return sets?.map((e) => e.toJson()).toList();
}
