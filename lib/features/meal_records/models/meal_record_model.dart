import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'meal_record_model.g.dart';

@JsonSerializable()
class MealRecord {
  final String id;
  @JsonKey(name: 'client_id')
  final String clientId;
  @JsonKey(name: 'meal_type')
  final String mealType; // 'breakfast' | 'lunch' | 'dinner' | 'snack'
  final String? notes;
  final List<String>? images;
  final double? calories;
  @DateTimeConverter()
  @JsonKey(name: 'recorded_at')
  final DateTime recordedAt;
  final String source; // 'message' | 'manual'
  @JsonKey(name: 'message_id')
  final String? messageId;
  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const MealRecord({
    required this.id,
    required this.clientId,
    required this.mealType,
    this.notes,
    this.images,
    this.calories,
    required this.recordedAt,
    required this.source,
    this.messageId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MealRecord.fromJson(Map<String, dynamic> json) =>
      _$MealRecordFromJson(json);
  Map<String, dynamic> toJson() => _$MealRecordToJson(this);

  MealRecord copyWith({
    String? id,
    String? clientId,
    String? mealType,
    String? notes,
    List<String>? images,
    double? calories,
    DateTime? recordedAt,
    String? source,
    String? messageId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MealRecord(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      mealType: mealType ?? this.mealType,
      notes: notes ?? this.notes,
      images: images ?? this.images,
      calories: calories ?? this.calories,
      recordedAt: recordedAt ?? this.recordedAt,
      source: source ?? this.source,
      messageId: messageId ?? this.messageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
