import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'message_model.g.dart';

@JsonSerializable()
class Message {
  final String id;
  @JsonKey(name: 'sender_id')
  final String senderId;
  @JsonKey(name: 'receiver_id')
  final String receiverId;
  @JsonKey(name: 'sender_type')
  final String senderType; // 'client' | 'trainer'
  @JsonKey(name: 'receiver_type')
  final String receiverType; // 'client' | 'trainer'
  final String? content;
  @JsonKey(name: 'image_urls')
  final List<String>? imageUrls;
  final List<String>? tags;
  @JsonKey(name: 'reply_to_message_id')
  final String? replyToMessageId;
  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @NullableDateTimeConverter()
  @JsonKey(name: 'read_at')
  final DateTime? readAt;
  @NullableDateTimeConverter()
  @JsonKey(name: 'edited_at')
  final DateTime? editedAt;
  @JsonKey(name: 'is_edited')
  final bool isEdited;
  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.senderType,
    required this.receiverType,
    this.content,
    this.imageUrls,
    this.tags,
    this.replyToMessageId,
    required this.createdAt,
    this.readAt,
    this.editedAt,
    required this.isEdited,
    required this.updatedAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
  Map<String, dynamic> toJson() => _$MessageToJson(this);

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? senderType,
    String? receiverType,
    String? content,
    List<String>? imageUrls,
    List<String>? tags,
    String? replyToMessageId,
    DateTime? createdAt,
    DateTime? readAt,
    DateTime? editedAt,
    bool? isEdited,
    DateTime? updatedAt,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      senderType: senderType ?? this.senderType,
      receiverType: receiverType ?? this.receiverType,
      content: content ?? this.content,
      imageUrls: imageUrls ?? this.imageUrls,
      tags: tags ?? this.tags,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      editedAt: editedAt ?? this.editedAt,
      isEdited: isEdited ?? this.isEdited,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
