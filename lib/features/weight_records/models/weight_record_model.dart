import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'weight_record_model.g.dart';

@JsonSerializable()
class WeightRecord {
  final String id;
  @JsonKey(name: 'client_id')
  final String clientId;
  final double weight; // kg
  final String? notes;
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

  const WeightRecord({
    required this.id,
    required this.clientId,
    required this.weight,
    this.notes,
    required this.recordedAt,
    required this.source,
    this.messageId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WeightRecord.fromJson(Map<String, dynamic> json) =>
      _$WeightRecordFromJson(json);
  Map<String, dynamic> toJson() => _$WeightRecordToJson(this);

  WeightRecord copyWith({
    String? id,
    String? clientId,
    double? weight,
    String? notes,
    DateTime? recordedAt,
    String? source,
    String? messageId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WeightRecord(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      weight: weight ?? this.weight,
      notes: notes ?? this.notes,
      recordedAt: recordedAt ?? this.recordedAt,
      source: source ?? this.source,
      messageId: messageId ?? this.messageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
