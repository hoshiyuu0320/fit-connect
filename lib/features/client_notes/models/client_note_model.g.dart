// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_note_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClientNote _$ClientNoteFromJson(Map<String, dynamic> json) => ClientNote(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      trainerId: json['trainer_id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      fileUrls: (json['file_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      isShared: json['is_shared'] as bool,
      sharedAt: const NullableDateTimeConverter()
          .fromJson(json['shared_at'] as String?),
      sessionNumber: (json['session_number'] as num?)?.toInt(),
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
      updatedAt:
          const DateTimeConverter().fromJson(json['updated_at'] as String),
    );

Map<String, dynamic> _$ClientNoteToJson(ClientNote instance) =>
    <String, dynamic>{
      'id': instance.id,
      'client_id': instance.clientId,
      'trainer_id': instance.trainerId,
      'title': instance.title,
      'content': instance.content,
      'file_urls': instance.fileUrls,
      'is_shared': instance.isShared,
      'shared_at': const NullableDateTimeConverter().toJson(instance.sharedAt),
      'session_number': instance.sessionNumber,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
      'updated_at': const DateTimeConverter().toJson(instance.updatedAt),
    };
