// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Client _$ClientFromJson(Map<String, dynamic> json) => Client(
      clientId: json['client_id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      trainerId: json['trainer_id'] as String,
      gender: json['gender'] as String?,
      age: (json['age'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toDouble(),
      initialWeight: (json['initial_weight'] as num?)?.toDouble(),
      targetWeight: (json['target_weight'] as num?)?.toDouble(),
      goalDeadline: const NullableDateTimeConverter()
          .fromJson(json['goal_deadline'] as String?),
      goalDescription: json['goal_description'] as String?,
      goalSetAt: const NullableDateTimeConverter()
          .fromJson(json['goal_set_at'] as String?),
      goalAchievedAt: const NullableDateTimeConverter()
          .fromJson(json['goal_achieved_at'] as String?),
      profileImageUrl: json['profile_image_url'] as String?,
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
    );

Map<String, dynamic> _$ClientToJson(Client instance) => <String, dynamic>{
      'client_id': instance.clientId,
      'name': instance.name,
      'email': instance.email,
      'trainer_id': instance.trainerId,
      'gender': instance.gender,
      'age': instance.age,
      'height': instance.height,
      'initial_weight': instance.initialWeight,
      'target_weight': instance.targetWeight,
      'goal_deadline':
          const NullableDateTimeConverter().toJson(instance.goalDeadline),
      'goal_description': instance.goalDescription,
      'goal_set_at':
          const NullableDateTimeConverter().toJson(instance.goalSetAt),
      'goal_achieved_at':
          const NullableDateTimeConverter().toJson(instance.goalAchievedAt),
      'profile_image_url': instance.profileImageUrl,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
    };
