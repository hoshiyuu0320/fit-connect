import 'package:json_annotation/json_annotation.dart';

part 'trainer_model.g.dart';

@JsonSerializable()
class Trainer {
  final String id;
  final String name;
  final String? email;
  @JsonKey(name: 'profile_image_url')
  final String? profileImageUrl;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;
  @JsonKey(name: 'is_online', defaultValue: false)
  final bool isOnline;
  @JsonKey(name: 'last_seen_at')
  final DateTime? lastSeenAt;

  const Trainer({
    required this.id,
    required this.name,
    this.email,
    this.profileImageUrl,
    this.createdAt,
    this.updatedAt,
    this.isOnline = false,
    this.lastSeenAt,
  });

  factory Trainer.fromJson(Map<String, dynamic> json) =>
      _$TrainerFromJson(json);
  Map<String, dynamic> toJson() => _$TrainerToJson(this);
}
