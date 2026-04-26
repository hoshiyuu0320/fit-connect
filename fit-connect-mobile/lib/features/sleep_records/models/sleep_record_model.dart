import 'package:json_annotation/json_annotation.dart';
import 'package:fit_connect_mobile/shared/utils/date_time_converter.dart';

part 'sleep_record_model.g.dart';

enum WakeupRating {
  @JsonValue(1)
  groggy, // だるい
  @JsonValue(2)
  okay, // まあまあ
  @JsonValue(3)
  refreshed; // すっきり

  String get labelJa => switch (this) {
        WakeupRating.groggy => 'だるい',
        WakeupRating.okay => 'まあまあ',
        WakeupRating.refreshed => 'すっきり',
      };
}

enum SleepSource {
  @JsonValue('healthkit')
  healthkit,
  @JsonValue('manual')
  manual,
}

enum SleepStage { deep, light, rem, awake }

@JsonSerializable()
class SleepRecord {
  final String id;
  @JsonKey(name: 'client_id')
  final String clientId;
  @JsonKey(name: 'recorded_date')
  final String recordedDate;

  @DateTimeConverter()
  @JsonKey(name: 'bed_time')
  final DateTime? bedTime;

  @DateTimeConverter()
  @JsonKey(name: 'wake_time')
  final DateTime? wakeTime;

  @JsonKey(name: 'total_sleep_minutes')
  final int? totalSleepMinutes;
  @JsonKey(name: 'deep_minutes')
  final int? deepMinutes;
  @JsonKey(name: 'light_minutes')
  final int? lightMinutes;
  @JsonKey(name: 'rem_minutes')
  final int? remMinutes;
  @JsonKey(name: 'awake_minutes')
  final int? awakeMinutes;

  @JsonKey(name: 'wakeup_rating')
  final WakeupRating? wakeupRating;

  final SleepSource source;

  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const SleepRecord({
    required this.id,
    required this.clientId,
    required this.recordedDate,
    this.bedTime,
    this.wakeTime,
    this.totalSleepMinutes,
    this.deepMinutes,
    this.lightMinutes,
    this.remMinutes,
    this.awakeMinutes,
    this.wakeupRating,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SleepRecord.fromJson(Map<String, dynamic> json) =>
      _$SleepRecordFromJson(json);
  Map<String, dynamic> toJson() => _$SleepRecordToJson(this);

  bool get hasObjectiveData => totalSleepMinutes != null;

  Duration? get totalDuration =>
      totalSleepMinutes != null ? Duration(minutes: totalSleepMinutes!) : null;

  Map<SleepStage, int>? get stageBreakdown {
    if (!hasObjectiveData) return null;
    return {
      SleepStage.deep: deepMinutes ?? 0,
      SleepStage.light: lightMinutes ?? 0,
      SleepStage.rem: remMinutes ?? 0,
      SleepStage.awake: awakeMinutes ?? 0,
    };
  }
}
