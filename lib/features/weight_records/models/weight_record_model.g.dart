// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weight_record_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WeightRecord _$WeightRecordFromJson(Map<String, dynamic> json) => WeightRecord(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      weight: (json['weight'] as num).toDouble(),
      notes: json['notes'] as String?,
      recordedAt:
          const DateTimeConverter().fromJson(json['recorded_at'] as String),
      source: json['source'] as String,
      messageId: json['message_id'] as String?,
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
      updatedAt:
          const DateTimeConverter().fromJson(json['updated_at'] as String),
    );

Map<String, dynamic> _$WeightRecordToJson(WeightRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'client_id': instance.clientId,
      'weight': instance.weight,
      'notes': instance.notes,
      'recorded_at': const DateTimeConverter().toJson(instance.recordedAt),
      'source': instance.source,
      'message_id': instance.messageId,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
      'updated_at': const DateTimeConverter().toJson(instance.updatedAt),
    };
