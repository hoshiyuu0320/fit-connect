// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_assignment_exercise_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkoutAssignmentExercise _$WorkoutAssignmentExerciseFromJson(
        Map<String, dynamic> json) =>
    WorkoutAssignmentExercise(
      id: json['id'] as String,
      assignmentId: json['assignment_id'] as String,
      exerciseName: json['exercise_name'] as String,
      targetSets: (json['target_sets'] as num).toInt(),
      targetReps: (json['target_reps'] as num).toInt(),
      targetWeight: (json['target_weight'] as num?)?.toDouble(),
      orderIndex: (json['order_index'] as num).toInt(),
      actualSets: _actualSetsFromJson(json['actual_sets']),
      isCompleted: json['is_completed'] as bool,
      completedAt: const NullableDateTimeConverter()
          .fromJson(json['completed_at'] as String?),
      memo: json['memo'] as String?,
      linkedExerciseId: json['linked_exercise_id'] as String?,
      createdAt: const NullableDateTimeConverter()
          .fromJson(json['created_at'] as String?),
    );

Map<String, dynamic> _$WorkoutAssignmentExerciseToJson(
        WorkoutAssignmentExercise instance) =>
    <String, dynamic>{
      'id': instance.id,
      'assignment_id': instance.assignmentId,
      'exercise_name': instance.exerciseName,
      'target_sets': instance.targetSets,
      'target_reps': instance.targetReps,
      'target_weight': instance.targetWeight,
      'order_index': instance.orderIndex,
      'actual_sets': _actualSetsToJson(instance.actualSets),
      'is_completed': instance.isCompleted,
      'completed_at':
          const NullableDateTimeConverter().toJson(instance.completedAt),
      'memo': instance.memo,
      'linked_exercise_id': instance.linkedExerciseId,
      'created_at':
          const NullableDateTimeConverter().toJson(instance.createdAt),
    };
