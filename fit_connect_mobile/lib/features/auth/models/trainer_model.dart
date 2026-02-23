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

  const Trainer({
    required this.id,
    required this.name,
    this.email,
    this.profileImageUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory Trainer.fromJson(Map<String, dynamic> json) =>
      _$TrainerFromJson(json);
  Map<String, dynamic> toJson() => _$TrainerToJson(this);
}
