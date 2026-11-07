import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';

/// リマインダーの時刻（日本時間の時・分。5分刻み）。保存形式は 'HH:mm'（例 '07:30'）
class ReminderTime {
  const ReminderTime({required this.hour, required this.minute})
      : assert(hour >= 0 && hour <= 23, 'hour は 0〜23'),
        assert(
          minute >= 0 && minute <= 55 && minute % minuteStep == 0,
          'minute は 0〜55 の5分刻み',
        );

  /// [kind] の既定の時刻
  factory ReminderTime.defaultFor(ReminderKind kind) =>
      ReminderTime(hour: kind.defaultHour, minute: kind.defaultMinute);

  final int hour;
  final int minute;

  /// 時刻の刻み（分）
  static const int minuteStep = 5;

  static final _pattern = RegExp(r'^(\d{2}):(\d{2})$');

  /// 'HH:mm' を読む。形式が違う・範囲外（0〜23時、0〜55分の5分刻みでない）なら null
  static ReminderTime? tryParse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 55 || minute % minuteStep != 0) return null;
    return ReminderTime(hour: hour, minute: minute);
  }

  /// 'HH:mm'（例 '07:30'）
  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => format();
}

/// 1項目の設定（オン・オフと時刻）
class ReminderSetting {
  const ReminderSetting({required this.enabled, required this.time});

  /// [kind] の既定（オフ・既定の時刻）
  factory ReminderSetting.defaultFor(ReminderKind kind) =>
      ReminderSetting(enabled: false, time: ReminderTime.defaultFor(kind));

  final bool enabled;
  final ReminderTime time;

  ReminderSetting copyWith({bool? enabled, ReminderTime? time}) =>
      ReminderSetting(
        enabled: enabled ?? this.enabled,
        time: time ?? this.time,
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderSetting &&
      other.enabled == enabled &&
      other.time == time;

  @override
  int get hashCode => Object.hash(enabled, time);

  @override
  String toString() => 'ReminderSetting(enabled: $enabled, time: $time)';
}

/// 記録のリマインダーの設定（5項目すべてを持つ）。
///
/// 端末の SharedPreferences にアカウントごとに保存する（RecordReminderSettingsStorage）。
/// JSON は `{"version":1,"items":{"weight":{"enabled":true,"time":"07:30"}, ...}}`。
class RecordReminderSettings {
  /// [items] に無い項目は既定で埋める（常に5項目すべてを持つ）
  RecordReminderSettings._(Map<ReminderKind, ReminderSetting> items)
      : items = Map.unmodifiable({
          for (final kind in ReminderKind.values)
            kind: items[kind] ?? ReminderSetting.defaultFor(kind),
        });

  /// すべてオフ・既定の時刻
  factory RecordReminderSettings.defaults() =>
      RecordReminderSettings._(const {});

  /// 保存した JSON から読む。壊れた値は既定に戻す（例外は投げない）。
  ///
  /// - 全体が Map でない・version が [jsonVersion] でない・items が Map でない → すべて既定
  /// - 項目が無い・Map でない → その項目だけ既定（オフ・既定の時刻）
  /// - enabled が bool でない → オフ。time が 'HH:mm' の5分刻みでない → その項目の既定の時刻
  /// - 知らない項目のキーは無視する
  factory RecordReminderSettings.fromJson(Object? json) {
    if (json is! Map || json['version'] != jsonVersion) {
      return RecordReminderSettings.defaults();
    }
    final items = json['items'];
    if (items is! Map) return RecordReminderSettings.defaults();
    return RecordReminderSettings._({
      for (final kind in ReminderKind.values)
        kind: _settingFromJson(kind, items[kind.key]),
    });
  }

  /// JSON の形式の版
  static const int jsonVersion = 1;

  /// 項目ごとの設定（ReminderKind の並び。変更不可）
  final Map<ReminderKind, ReminderSetting> items;

  Map<String, Object?> toJson() => {
        'version': jsonVersion,
        'items': {
          for (final kind in ReminderKind.values)
            kind.key: {
              'enabled': settingOf(kind).enabled,
              'time': settingOf(kind).time.format(),
            },
        },
      };

  /// [kind] の設定
  ReminderSetting settingOf(ReminderKind kind) => items[kind]!;

  /// [kind] だけを [setting] に替えた設定
  RecordReminderSettings withSetting(
    ReminderKind kind,
    ReminderSetting setting,
  ) =>
      RecordReminderSettings._({...items, kind: setting});

  /// オンの項目が1つでもあるか
  bool get anyEnabled => items.values.any((setting) => setting.enabled);

  /// オンの項目（ReminderKind の並び）
  List<ReminderKind> get enabledKinds => [
        for (final kind in ReminderKind.values)
          if (settingOf(kind).enabled) kind,
      ];

  static ReminderSetting _settingFromJson(ReminderKind kind, Object? json) {
    final fallback = ReminderSetting.defaultFor(kind);
    if (json is! Map) return fallback;
    final enabled = json['enabled'];
    final time = json['time'];
    return ReminderSetting(
      enabled: enabled is bool ? enabled : fallback.enabled,
      time: (time is String ? ReminderTime.tryParse(time) : null) ??
          fallback.time,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecordReminderSettings &&
      ReminderKind.values.every((kind) => other.items[kind] == items[kind]);

  @override
  int get hashCode =>
      Object.hashAll(ReminderKind.values.map((kind) => items[kind]));

  @override
  String toString() => 'RecordReminderSettings(${toJson()})';
}
