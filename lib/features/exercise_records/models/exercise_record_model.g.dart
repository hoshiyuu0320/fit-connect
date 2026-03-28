// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise_record_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExerciseRecord _$ExerciseRecordFromJson(Map<String, dynamic> json) =>
    ExerciseRecord(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      exerciseType: json['exercise_type'] as String,
      memo: json['memo'] as String?,
      images:
          (json['images'] as List<dynamic>?)?.map((e) => e as String).toList(),
      duration: (json['duration'] as num?)?.toInt(),
      distance: (json['distance'] as num?)?.toDouble(),
      calories: (json['calories'] as num?)?.toDouble(),
      recordedAt:
          const DateTimeConverter().fromJson(json['recorded_at'] as String),
      source: json['source'] as String,
      messageId: json['message_id'] as String?,
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
      updatedAt:
          const DateTimeConverter().fromJson(json['updated_at'] as String),
    );

Map<String, dynamic> _$ExerciseRecordToJson(ExerciseRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'client_id': instance.clientId,
      'exercise_type': instance.exerciseType,
      'memo': instance.memo,
      'images': instance.images,
      'duration': instance.duration,
      'distance': instance.distance,
      'calories': instance.calories,
      'recorded_at': const DateTimeConverter().toJson(instance.recordedAt),
      'source': instance.source,
      'message_id': instance.messageId,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
      'updated_at': const DateTimeConverter().toJson(instance.updatedAt),
    };
