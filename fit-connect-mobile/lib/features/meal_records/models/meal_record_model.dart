import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';

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
  @JsonKey(name: 'protein_g')
  final double? proteinG;
  @JsonKey(name: 'fat_g')
  final double? fatG;
  @JsonKey(name: 'carbs_g')
  final double? carbsG;
  @JsonKey(name: 'estimated_by_ai')
  final bool estimatedByAi;
  @JsonKey(name: 'ai_foods')
  final List<EstimatedFood>? aiFoods;
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
    this.proteinG,
    this.fatG,
    this.carbsG,
    this.estimatedByAi = false,
    this.aiFoods,
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
    double? proteinG,
    double? fatG,
    double? carbsG,
    bool? estimatedByAi,
    List<EstimatedFood>? aiFoods,
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
      proteinG: proteinG ?? this.proteinG,
      fatG: fatG ?? this.fatG,
      carbsG: carbsG ?? this.carbsG,
      estimatedByAi: estimatedByAi ?? this.estimatedByAi,
      aiFoods: aiFoods ?? this.aiFoods,
      recordedAt: recordedAt ?? this.recordedAt,
      source: source ?? this.source,
      messageId: messageId ?? this.messageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
