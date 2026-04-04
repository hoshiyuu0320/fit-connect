import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'client_note_model.g.dart';

@JsonSerializable()
class ClientNote {
  final String id;

  @JsonKey(name: 'client_id')
  final String clientId;

  @JsonKey(name: 'trainer_id')
  final String trainerId;

  final String title;
  final String content;

  @JsonKey(name: 'file_urls')
  final List<String> fileUrls;

  @JsonKey(name: 'is_shared')
  final bool isShared;

  @NullableDateTimeConverter()
  @JsonKey(name: 'shared_at')
  final DateTime? sharedAt;

  @JsonKey(name: 'session_number')
  final int? sessionNumber;

  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const ClientNote({
    required this.id,
    required this.clientId,
    required this.trainerId,
    required this.title,
    required this.content,
    this.fileUrls = const [],
    required this.isShared,
    this.sharedAt,
    this.sessionNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClientNote.fromJson(Map<String, dynamic> json) =>
      _$ClientNoteFromJson(json);
  Map<String, dynamic> toJson() => _$ClientNoteToJson(this);
}
