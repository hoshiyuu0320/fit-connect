// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_assignment_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkoutPlanInfo _$WorkoutPlanInfoFromJson(Map<String, dynamic> json) =>
    WorkoutPlanInfo(
      title: json['title'] as String,
      description: json['description'] as String?,
      category: json['category'] as String,
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
      planType: json['plan_type'] as String?,
    );

Map<String, dynamic> _$WorkoutPlanInfoToJson(WorkoutPlanInfo instance) =>
    <String, dynamic>{
      'title': instance.title,
      'description': instance.description,
      'category': instance.category,
      'estimated_minutes': instance.estimatedMinutes,
      'plan_type': instance.planType,
    };

WorkoutAssignment _$WorkoutAssignmentFromJson(Map<String, dynamic> json) =>
    WorkoutAssignment(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      trainerId: json['trainer_id'] as String,
      planId: json['plan_id'] as String,
      assignedDate: json['assigned_date'] as String,
      status: json['status'] as String,
      createdAt: const NullableDateTimeConverter()
          .fromJson(json['created_at'] as String?),
      updatedAt: const NullableDateTimeConverter()
          .fromJson(json['updated_at'] as String?),
      trainerNote: json['trainer_note'] as String?,
      clientFeedback: json['client_feedback'] as String?,
      startedAt: const NullableDateTimeConverter()
          .fromJson(json['started_at'] as String?),
      finishedAt: const NullableDateTimeConverter()
          .fromJson(json['finished_at'] as String?),
      planInfo: json['workout_plans'] == null
          ? null
          : WorkoutPlanInfo.fromJson(
              json['workout_plans'] as Map<String, dynamic>),
      exercises: (json['workout_assignment_exercises'] as List<dynamic>?)
              ?.map((e) =>
                  WorkoutAssignmentExercise.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$WorkoutAssignmentToJson(WorkoutAssignment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'client_id': instance.clientId,
      'trainer_id': instance.trainerId,
      'plan_id': instance.planId,
      'assigned_date': instance.assignedDate,
      'status': instance.status,
      'created_at':
          const NullableDateTimeConverter().toJson(instance.createdAt),
      'updated_at':
          const NullableDateTimeConverter().toJson(instance.updatedAt),
      'trainer_note': instance.trainerNote,
      'client_feedback': instance.clientFeedback,
      'started_at':
          const NullableDateTimeConverter().toJson(instance.startedAt),
      'finished_at':
          const NullableDateTimeConverter().toJson(instance.finishedAt),
      'workout_plans': instance.planInfo,
      'workout_assignment_exercises': instance.exercises,
    };
