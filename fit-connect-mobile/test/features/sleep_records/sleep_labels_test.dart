import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/utils/sleep_labels.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_history_list_item.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_sync_status.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_week_chart.dart';

import 'sleep_test_helpers.dart';

/// 睡眠画面の表示文字の整形（正本 record-screens.js の書式）と、直近7日の集計の純粋なテスト。
void main() {
  group('日付・時刻・時間の書式', () {
    test('日付は「9月13日（日）」（全角の括弧・空白なし）、年は違うときだけ付く', () {
      final sunday = DateTime(2026, 9, 13);
      expect(formatSleepDate(sunday), '9月13日（日）');
      expect(formatSleepDate(sunday, now: DateTime(2026, 10, 4)), '9月13日（日）');
      expect(
        formatSleepDate(DateTime(2025, 12, 28), now: DateTime(2026, 1, 3)),
        '2025年12月28日（日）',
      );
    });

    test('時刻は時を 0 埋めしない「7:32」「23:30」', () {
      expect(formatSleepClock(DateTime(2026, 9, 13, 7, 32)), '7:32');
      expect(formatSleepClock(DateTime(2026, 9, 12, 23, 30)), '23:30');
      expect(formatSleepClock(DateTime(2026, 9, 13, 7, 5)), '7:05');
      expect(
        formatSleepDateTime(DateTime(2026, 9, 13, 7, 32)),
        '9月13日（日）7:32',
      );
    });

    test('睡眠時間は「6時間50分」（60分未満は「45分」）、グラフの値は「6:50」', () {
      expect(formatSleepDuration(410), '6時間50分');
      expect(formatSleepDuration(420), '7時間00分');
      expect(formatSleepDuration(45), '45分');
      expect(formatSleepHm(410), '6:50');
      expect(formatSleepHm(420), '7:00');
      expect(formatSleepHm(540), '9:00');
    });

    test('大きな数値は「7 時間 30 分」の組、60分未満は分だけ', () {
      final parts = sleepDurationParts(450);
      expect(parts.map((p) => '${p.value}${p.unit}').join(), '7時間30分');
      expect(
        sleepDurationParts(425).map((p) => '${p.value}${p.unit}').join(),
        '7時間05分',
      );
      expect(
        sleepDurationParts(45).map((p) => '${p.value}${p.unit}').join(),
        '45分',
      );
    });

    test('日付キーの解析', () {
      expect(parseSleepDateKey('2026-09-13'), DateTime(2026, 9, 13));
      expect(parseSleepDateKey('2026/09/13'), isNull);
      expect(parseSleepDateKey('abc'), isNull);
      expect(sleepWeekdayLabel(DateTime(2026, 9, 7)), '月');
      expect(sleepWeekdayLabel(DateTime(2026, 9, 13)), '日');
    });
  });

  group('直近7日の集計', () {
    const entries = [
      DailySleepEntry(dateKey: '2026-09-07', minutes: 410),
      DailySleepEntry(dateKey: '2026-09-08', minutes: 430),
      DailySleepEntry(dateKey: '2026-09-09'),
      DailySleepEntry(dateKey: '2026-09-10', minutes: 390),
      DailySleepEntry(dateKey: '2026-09-11', minutes: 420),
      DailySleepEntry(dateKey: '2026-09-12', minutes: 410),
      DailySleepEntry(dateKey: '2026-09-13', minutes: 450),
    ];

    test('正本のサンプル: 6日分の平均 6時間58分・9/9 は未取得', () {
      final summary = SleepWeekSummary.from(entries);
      expect(summary.recordedDays, 6);
      expect(summary.averageMinutes, 418);
      expect(formatSleepDuration(summary.averageMinutes!), '6時間58分');
      expect(summary.missingLabels, ['9/9']);
      expect(summary.caption, 'HealthKit · 6日分の平均（9/9は未取得）');
    });

    test('未取得が複数なら「、」でつなぐ。すべて取得できていれば括弧を付けない', () {
      final summary = SleepWeekSummary.from(const [
        DailySleepEntry(dateKey: '2026-09-09'),
        DailySleepEntry(dateKey: '2026-09-10'),
        DailySleepEntry(dateKey: '2026-09-11', minutes: 420),
      ]);
      expect(summary.caption, 'HealthKit · 1日分の平均（9/9、9/10は未取得）');

      final full = SleepWeekSummary.from(const [
        DailySleepEntry(dateKey: '2026-09-10', minutes: 400),
        DailySleepEntry(dateKey: '2026-09-11', minutes: 420),
      ]);
      expect(full.caption, 'HealthKit · 2日分の平均');
      expect(full.averageMinutes, 410);
    });

    test('未取得が 4 日以上なら日付ではなく日数で出す', () {
      final summary = SleepWeekSummary.from(const [
        DailySleepEntry(dateKey: '2026-09-09'),
        DailySleepEntry(dateKey: '2026-09-10'),
        DailySleepEntry(dateKey: '2026-09-11'),
        DailySleepEntry(dateKey: '2026-09-12'),
        DailySleepEntry(dateKey: '2026-09-13', minutes: 420),
      ]);
      expect(summary.caption, 'HealthKit · 1日分の平均（4日は未取得）');
    });

    test('1日も取得できていなければ平均を出さない（0 にしない）', () {
      final summary = SleepWeekSummary.from(const [
        DailySleepEntry(dateKey: '2026-09-12'),
        DailySleepEntry(dateKey: '2026-09-13'),
      ]);
      expect(summary.averageMinutes, isNull);
      expect(summary.recordedDays, 0);
      expect(summary.caption, 'HealthKit の記録はまだありません');
    });

    test('睡眠レコードから 7 日分（古い日 → 今日）を作り、無い日・時間の無い日は null', () {
      final built = SleepWeekChart.entriesFrom(sampleSleepRecords());
      expect(built.length, 7);
      // 今日が最後
      expect(built.last.minutes, 450);
      // 2 日前は記録なし、4 日前は手動の記録のみ（睡眠時間なし）
      expect(built[4].minutes, isNull); // 2 日前
      expect(built[2].minutes, isNull); // 4 日前
      expect(built.where((e) => e.minutes != null).length, 5);
    });
  });

  group('履歴の補足と同期の文言', () {
    test('履歴の補足は「目覚め まあまあ」。手動の記録のみは末尾に付く', () {
      expect(
        SleepHistoryListItem.captionFor(
          sleepRecord(1, total: 410, rating: WakeupRating.okay),
        ),
        '目覚め まあまあ',
      );
      expect(
        SleepHistoryListItem.captionFor(sleepRecord(2, total: 400)),
        '目覚め 未記録',
      );
      expect(
        SleepHistoryListItem.captionFor(
          sleepRecord(3, rating: WakeupRating.groggy),
        ),
        '目覚め だるい · 手動の記録のみ',
      );
    });

    test('同期できなかったときの文言（日時が分からなければ日時の文を省く）', () {
      final at = DateTime(2026, 9, 13, 7, 32);
      expect(
        SleepSyncStatus.failureMessage(at, now: DateTime(2026, 9, 13)),
        'HealthKitと同期できませんでした。9月13日（日）7:32 に取得した値を表示しています。',
      );
      expect(
        SleepSyncStatus.failureMessage(null),
        'HealthKitと同期できませんでした。',
      );
    });
  });
}
