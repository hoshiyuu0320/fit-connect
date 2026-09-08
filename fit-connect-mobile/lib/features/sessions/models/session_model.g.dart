// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SessionModel _$SessionModelFromJson(Map<String, dynamic> json) => SessionModel(
      id: json['id'] as String,
      trainerId: json['trainer_id'] as String,
      clientId: json['client_id'] as String,
      sessionDate:
          const DateTimeConverter().fromJson(json['session_date'] as String),
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      status: json['status'] as String,
      sessionType: json['session_type'] as String?,
      ticketId: json['ticket_id'] as String?,
      recurrenceGroupId: json['recurrence_group_id'] as String?,
      notes: (json['client_notes'] as List<dynamic>?)
              ?.map((e) => ClientNote.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt:
          const DateTimeConverter().fromJson(json['created_at'] as String),
      updatedAt:
          const DateTimeConverter().fromJson(json['updated_at'] as String),
    );

Map<String, dynamic> _$SessionModelToJson(SessionModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainer_id': instance.trainerId,
      'client_id': instance.clientId,
      'session_date': const DateTimeConverter().toJson(instance.sessionDate),
      'duration_minutes': instance.durationMinutes,
      'status': instance.status,
      'session_type': instance.sessionType,
      'ticket_id': instance.ticketId,
      'recurrence_group_id': instance.recurrenceGroupId,
      'client_notes': instance.notes,
      'created_at': const DateTimeConverter().toJson(instance.createdAt),
      'updated_at': const DateTimeConverter().toJson(instance.updatedAt),
    };
