// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trainer_schedule_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TrainerSchedule _$TrainerScheduleFromJson(Map<String, dynamic> json) =>
    TrainerSchedule(
      id: json['id'] as String,
      trainerId: json['trainer_id'] as String,
      dayOfWeek: (json['day_of_week'] as num).toInt(),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      isAvailable: json['is_available'] as bool,
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
      updatedAt:
          const DateTimeConverter().fromJson(json['updated_at'] as String),
    );

Map<String, dynamic> _$TrainerScheduleToJson(TrainerSchedule instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainer_id': instance.trainerId,
      'day_of_week': instance.dayOfWeek,
      'start_time': instance.startTime,
      'end_time': instance.endTime,
      'is_available': instance.isAvailable,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
      'updated_at': const DateTimeConverter().toJson(instance.updatedAt),
    };
