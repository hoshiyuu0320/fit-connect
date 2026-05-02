// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meal_record_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MealRecord _$MealRecordFromJson(Map<String, dynamic> json) => MealRecord(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      mealType: json['meal_type'] as String,
      notes: json['notes'] as String?,
      images:
          (json['images'] as List<dynamic>?)?.map((e) => e as String).toList(),
      calories: (json['calories'] as num?)?.toDouble(),
      proteinG: (json['protein_g'] as num?)?.toDouble(),
      fatG: (json['fat_g'] as num?)?.toDouble(),
      carbsG: (json['carbs_g'] as num?)?.toDouble(),
      estimatedByAi: json['estimated_by_ai'] as bool? ?? false,
      aiFoods: (json['ai_foods'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList(),
      recordedAt:
          const DateTimeConverter().fromJson(json['recorded_at'] as String),
      source: json['source'] as String,
      messageId: json['message_id'] as String?,
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
      updatedAt:
          const DateTimeConverter().fromJson(json['updated_at'] as String),
    );

Map<String, dynamic> _$MealRecordToJson(MealRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'client_id': instance.clientId,
      'meal_type': instance.mealType,
      'notes': instance.notes,
      'images': instance.images,
      'calories': instance.calories,
      'protein_g': instance.proteinG,
      'fat_g': instance.fatG,
      'carbs_g': instance.carbsG,
      'estimated_by_ai': instance.estimatedByAi,
      'ai_foods': instance.aiFoods,
      'recorded_at': const DateTimeConverter().toJson(instance.recordedAt),
      'source': instance.source,
      'message_id': instance.messageId,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
      'updated_at': const DateTimeConverter().toJson(instance.updatedAt),
    };
