import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';

/// 記録のリマインダーの設定を端末（SharedPreferences）にアカウントごとに保存する。
///
/// サーバーには保存しない（別の端末では設定し直し。トレーナーからは見えない）。
/// キーを auth のユーザー ID ごとに分けるので、別のアカウントでログインしても前の人の設定は読まない。
class RecordReminderSettingsStorage {
  /// [preferences] はテストで差し替えるためのもの（省略時は SharedPreferences.getInstance）
  RecordReminderSettingsStorage({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  /// 保存キー（`record_reminder_settings:<auth のユーザー ID>`）
  static String keyFor(String userId) => 'record_reminder_settings:$userId';

  /// [userId] の設定を読む。保存していない・読めない値なら既定（すべてオフ）。例外は投げない
  Future<RecordReminderSettings> load(String userId) async {
    final prefs = await _preferences();
    // getString は文字列以外の値で例外になるので、型を見てから読む
    final raw = prefs.get(keyFor(userId));
    if (raw is! String) return RecordReminderSettings.defaults();
    try {
      return RecordReminderSettings.fromJson(jsonDecode(raw));
    } on FormatException {
      return RecordReminderSettings.defaults();
    }
  }

  /// [userId] の設定を保存する
  Future<void> save(String userId, RecordReminderSettings settings) async {
    final prefs = await _preferences();
    await prefs.setString(keyFor(userId), jsonEncode(settings.toJson()));
  }
}
