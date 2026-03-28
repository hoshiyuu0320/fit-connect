import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'client_model.g.dart';

@JsonSerializable()
class Client {
  @JsonKey(name: 'client_id')
  final String clientId;
  final String name;
  final String? email;
  @JsonKey(name: 'trainer_id')
  final String trainerId;
  final String? gender; // 'male' | 'female' | 'other'
  final int? age;
  final double? height; // cm
  @JsonKey(name: 'initial_weight')
  final double? initialWeight; // kg
  @JsonKey(name: 'target_weight')
  final double? targetWeight; // kg
  @NullableDateTimeConverter()
  @JsonKey(name: 'goal_deadline')
  final DateTime? goalDeadline;
  @JsonKey(name: 'goal_description')
  final String? goalDescription;
  @NullableDateTimeConverter()
  @JsonKey(name: 'goal_set_at')
  final DateTime? goalSetAt;
  @NullableDateTimeConverter()
  @JsonKey(name: 'goal_achieved_at')
  final DateTime? goalAchievedAt;
  @JsonKey(name: 'profile_image_url')
  final String? profileImageUrl;
  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  const Client({
    required this.clientId,
    required this.name,
    this.email,
    required this.trainerId,
    this.gender,
    this.age,
    this.height,
    this.initialWeight,
    this.targetWeight,
    this.goalDeadline,
    this.goalDescription,
    this.goalSetAt,
    this.goalAchievedAt,
    this.profileImageUrl,
    required this.createdAt,
  });

  factory Client.fromJson(Map<String, dynamic> json) => _$ClientFromJson(json);
  Map<String, dynamic> toJson() => _$ClientToJson(this);

  Client copyWith({
    String? clientId,
    String? name,
    String? email,
    String? trainerId,
    String? gender,
    int? age,
    double? height,
    double? initialWeight,
    double? targetWeight,
    DateTime? goalDeadline,
    String? goalDescription,
    DateTime? goalSetAt,
    DateTime? goalAchievedAt,
    String? profileImageUrl,
    DateTime? createdAt,
  }) {
    return Client(
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      email: email ?? this.email,
      trainerId: trainerId ?? this.trainerId,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      height: height ?? this.height,
      initialWeight: initialWeight ?? this.initialWeight,
      targetWeight: targetWeight ?? this.targetWeight,
      goalDeadline: goalDeadline ?? this.goalDeadline,
      goalDescription: goalDescription ?? this.goalDescription,
      goalSetAt: goalSetAt ?? this.goalSetAt,
      goalAchievedAt: goalAchievedAt ?? this.goalAchievedAt,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
