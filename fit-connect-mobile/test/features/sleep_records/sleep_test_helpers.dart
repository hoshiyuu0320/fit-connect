import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';

/// 睡眠画面のテストで共有する部品（ダミーデータ・Riverpod の差し替え）。
/// `*_test.dart` ではないので単体では実行されない。

/// 今日から [daysAgo] 日前の睡眠記録（JST の日付キー。[date] を渡せば固定）。
/// [total] が null なら睡眠時間なし（手動の記録のみ）
SleepRecord sleepRecord(
  int daysAgo, {
  String? date,
  int? total,
  WakeupRating? rating,
  SleepSource? source,
  int deep = 85,
  int light = 255,
  int rem = 110,
  int awake = 20,
}) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - daysAgo);
  final objective = total != null;
  return SleepRecord(
    id: 'sleep-$daysAgo',
    clientId: 'client-1',
    recordedDate: date ?? jstDateKeyDaysAgo(daysAgo),
    bedTime:
        objective ? DateTime(day.year, day.month, day.day - 1, 23, 30) : null,
    wakeTime: objective ? DateTime(day.year, day.month, day.day, 7, 20) : null,
    totalSleepMinutes: total,
    deepMinutes: objective ? deep : null,
    lightMinutes: objective ? light : null,
    remMinutes: objective ? rem : null,
    awakeMinutes: objective ? awake : null,
    wakeupRating: rating,
    source: source ?? (objective ? SleepSource.healthkit : SleepSource.manual),
    createdAt: now,
    updatedAt: now,
  );
}

/// 正本（record-screens.js の SleepTab）に近いサンプル:
/// 昨夜 7時間30分・直近7日のうち 2 日が未取得・履歴に手動の記録のみの日（だるい）。
List<SleepRecord> sampleSleepRecords() => [
      sleepRecord(0, total: 450, rating: WakeupRating.refreshed),
      sleepRecord(1, total: 410, rating: WakeupRating.okay),
      // 2 日前は記録なし（未取得）
      sleepRecord(3, total: 390),
      sleepRecord(4, rating: WakeupRating.groggy), // 手動の記録のみ
      sleepRecord(5, total: 430, rating: WakeupRating.okay),
      sleepRecord(6, total: 410, rating: WakeupRating.refreshed),
    ];

/// `sleepRecordsProvider()` の差し替え。保存（upsertWakeupRating）は呼び出しを記録するだけ
class FakeSleepRecords extends SleepRecords {
  FakeSleepRecords(this._load);

  /// 読み込みのたびに呼ばれる（再取得のたびに新しい Future を返せる）
  final Future<List<SleepRecord>> Function() _load;

  final List<({String recordedDate, WakeupRating rating})> saved = [];

  @override
  Future<List<SleepRecord>> build({int limit = 30}) => _load();

  @override
  Future<void> upsertWakeupRating({
    required String recordedDate,
    required WakeupRating rating,
  }) async {
    saved.add((recordedDate: recordedDate, rating: rating));
  }
}

/// `healthSettingsProvider` の差し替え
class FakeHealthSettings extends HealthSettings {
  FakeHealthSettings(this._state);
  final HealthSettingsState _state;

  @override
  Future<HealthSettingsState> build() async => _state;
}

HealthSettingsState healthSettingsState({
  bool enabled = true,
  bool? sleepEnabled,
  HealthSyncStatus status = HealthSyncStatus.success,
  DateTime? lastSyncAt,
  String? error,
}) {
  return HealthSettingsState(
    isEnabled: enabled,
    isWeightEnabled: enabled,
    isSleepEnabled: sleepEnabled ?? enabled,
    isMorningDialogEnabled: true,
    lastSyncAt: lastSyncAt,
    lastSyncStatus: status,
    lastSyncError:
        error ?? (status == HealthSyncStatus.error ? '睡眠: timeout' : null),
  );
}

/// 画面内の `Text` / `Text.rich` の文字をすべて連結して返す（絵文字・文言の検査用）
String allText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    buffer.write(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    buffer.write('\n');
  }
  return buffer.toString();
}

/// 絵文字（顔文字・記号の絵文字）を含むか
final RegExp emojiPattern = RegExp(
  r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]',
  unicode: true,
);
