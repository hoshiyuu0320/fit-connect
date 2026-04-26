// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      senderType: json['sender_type'] as String,
      receiverType: json['receiver_type'] as String,
      content: json['content'] as String?,
      imageUrls: (json['image_urls'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      replyToMessageId: json['reply_to_message_id'] as String?,
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
      readAt: const NullableDateTimeConverter()
          .fromJson(json['read_at'] as String?),
      editedAt: const NullableDateTimeConverter()
          .fromJson(json['edited_at'] as String?),
      isEdited: json['is_edited'] as bool,
      updatedAt:
          const DateTimeConverter().fromJson(json['updated_at'] as String),
    );

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
      'id': instance.id,
      'sender_id': instance.senderId,
      'receiver_id': instance.receiverId,
      'sender_type': instance.senderType,
      'receiver_type': instance.receiverType,
      'content': instance.content,
      'image_urls': instance.imageUrls,
      'tags': instance.tags,
      'reply_to_message_id': instance.replyToMessageId,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
      'read_at': const NullableDateTimeConverter().toJson(instance.readAt),
      'edited_at': const NullableDateTimeConverter().toJson(instance.editedAt),
      'is_edited': instance.isEdited,
      'updated_at': const DateTimeConverter().toJson(instance.updatedAt),
    };
