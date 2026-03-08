// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trainer_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Trainer _$TrainerFromJson(Map<String, dynamic> json) => Trainer(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.parse(json['last_seen_at'] as String),
    );

Map<String, dynamic> _$TrainerToJson(Trainer instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'email': instance.email,
      'profile_image_url': instance.profileImageUrl,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
      'is_online': instance.isOnline,
      'last_seen_at': instance.lastSeenAt?.toIso8601String(),
    };
