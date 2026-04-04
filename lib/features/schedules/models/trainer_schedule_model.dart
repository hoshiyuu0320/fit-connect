import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'trainer_schedule_model.g.dart';

@JsonSerializable()
class TrainerSchedule {
  final String id;
  @JsonKey(name: 'trainer_id')
  final String trainerId;
  @JsonKey(name: 'day_of_week')
  final int dayOfWeek; // 0=日, 1=月, ..., 6=土
  @JsonKey(name: 'start_time')
  final String startTime; // "HH:mm:ss" 形式
  @JsonKey(name: 'end_time')
  final String endTime; // "HH:mm:ss" 形式
  @JsonKey(name: 'is_available')
  final bool isAvailable;
  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const TrainerSchedule({
    required this.id,
    required this.trainerId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.isAvailable,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TrainerSchedule.fromJson(Map<String, dynamic> json) =>
      _$TrainerScheduleFromJson(json);
  Map<String, dynamic> toJson() => _$TrainerScheduleToJson(this);

  TrainerSchedule copyWith({
    String? id,
    String? trainerId,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    bool? isAvailable,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TrainerSchedule(
      id: id ?? this.id,
      trainerId: trainerId ?? this.trainerId,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAvailable: isAvailable ?? this.isAvailable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
