// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sleep_record_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SleepRecord _$SleepRecordFromJson(Map<String, dynamic> json) => SleepRecord(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      recordedDate: json['recorded_date'] as String,
      bedTime: _$JsonConverterFromJson<String, DateTime>(
          json['bed_time'], const DateTimeConverter().fromJson),
      wakeTime: _$JsonConverterFromJson<String, DateTime>(
          json['wake_time'], const DateTimeConverter().fromJson),
      totalSleepMinutes: (json['total_sleep_minutes'] as num?)?.toInt(),
      deepMinutes: (json['deep_minutes'] as num?)?.toInt(),
      lightMinutes: (json['light_minutes'] as num?)?.toInt(),
      remMinutes: (json['rem_minutes'] as num?)?.toInt(),
      awakeMinutes: (json['awake_minutes'] as num?)?.toInt(),
      wakeupRating:
          $enumDecodeNullable(_$WakeupRatingEnumMap, json['wakeup_rating']),
      source: $enumDecode(_$SleepSourceEnumMap, json['source']),
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
      updatedAt:
          const DateTimeConverter().fromJson(json['updated_at'] as String),
    );

Map<String, dynamic> _$SleepRecordToJson(SleepRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'client_id': instance.clientId,
      'recorded_date': instance.recordedDate,
      'bed_time': _$JsonConverterToJson<String, DateTime>(
          instance.bedTime, const DateTimeConverter().toJson),
      'wake_time': _$JsonConverterToJson<String, DateTime>(
          instance.wakeTime, const DateTimeConverter().toJson),
      'total_sleep_minutes': instance.totalSleepMinutes,
      'deep_minutes': instance.deepMinutes,
      'light_minutes': instance.lightMinutes,
      'rem_minutes': instance.remMinutes,
      'awake_minutes': instance.awakeMinutes,
      'wakeup_rating': _$WakeupRatingEnumMap[instance.wakeupRating],
      'source': _$SleepSourceEnumMap[instance.source]!,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
      'updated_at': const DateTimeConverter().toJson(instance.updatedAt),
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) =>
    json == null ? null : fromJson(json as Json);

const _$WakeupRatingEnumMap = {
  WakeupRating.groggy: 1,
  WakeupRating.okay: 2,
  WakeupRating.refreshed: 3,
};

const _$SleepSourceEnumMap = {
  SleepSource.healthkit: 'healthkit',
  SleepSource.manual: 'manual',
};

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) =>
    value == null ? null : toJson(value);
