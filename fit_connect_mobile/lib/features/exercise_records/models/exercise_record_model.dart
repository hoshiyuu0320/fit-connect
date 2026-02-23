import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'exercise_record_model.g.dart';

@JsonSerializable()
class ExerciseRecord {
  final String id;
  @JsonKey(name: 'client_id')
  final String clientId;
  @JsonKey(name: 'exercise_type')
  final String
      exerciseType; // 'strength_training' | 'cardio' | 'walking' | 'running' | 'cycling' | 'swimming' | 'yoga' | 'pilates' | 'other'
  final String? memo;
  final List<String>? images;
  final int? duration; // minutes
  final double? distance; // km
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

  const ExerciseRecord({
    required this.id,
    required this.clientId,
    required this.exerciseType,
    this.memo,
    this.images,
    this.duration,
    this.distance,
    this.calories,
    required this.recordedAt,
    required this.source,
    this.messageId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExerciseRecord.fromJson(Map<String, dynamic> json) =>
      _$ExerciseRecordFromJson(json);
  Map<String, dynamic> toJson() => _$ExerciseRecordToJson(this);

  ExerciseRecord copyWith({
    String? id,
    String? clientId,
    String? exerciseType,
    String? memo,
    List<String>? images,
    int? duration,
    double? distance,
    double? calories,
    DateTime? recordedAt,
    String? source,
    String? messageId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExerciseRecord(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      exerciseType: exerciseType ?? this.exerciseType,
      memo: memo ?? this.memo,
      images: images ?? this.images,
      duration: duration ?? this.duration,
      distance: distance ?? this.distance,
      calories: calories ?? this.calories,
      recordedAt: recordedAt ?? this.recordedAt,
      source: source ?? this.source,
      messageId: messageId ?? this.messageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
