import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/utils/sleep_labels.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 1日分の睡眠時間（直近7日のグラフ用）
class DailySleepEntry {
  /// JST の日付キー（`yyyy-MM-dd`）
  final String dateKey;

  /// 睡眠時間（分）。**null = 未取得**（0 分とは区別する。手動の記録のみの日も null）
  final int? minutes;

  const DailySleepEntry({required this.dateKey, this.minutes});
}

/// 直近7日の集計（平均・取得できなかった日）。表示用の純粋な計算
class SleepWeekSummary {
  /// 取得できた日の平均（分・四捨五入）。1日も無ければ null
  final int? averageMinutes;

  /// 取得できた日数
  final int recordedDays;

  /// 取得できなかった日の「M/D」ラベル（古い日から）
  final List<String> missingLabels;

  const SleepWeekSummary({
    required this.averageMinutes,
    required this.recordedDays,
    required this.missingLabels,
  });

  factory SleepWeekSummary.from(List<DailySleepEntry> entries) {
    var total = 0;
    var count = 0;
    final missing = <String>[];
    for (final e in entries) {
      final m = e.minutes;
      if (m == null) {
        missing.add(_shortDate(e.dateKey));
      } else {
        total += m;
        count++;
      }
    }
    return SleepWeekSummary(
      averageMinutes: count == 0 ? null : (total / count).round(),
      recordedDays: count,
      missingLabels: missing,
    );
  }

  /// 日付を並べて出す未取得の日数の上限
  static const int _maxListedMissing = 3;

  /// 「HealthKit · 6日分の平均（9/9は未取得）」。未取得が 4 日以上なら「（5日は未取得）」。
  /// 1日も無ければ「HealthKit の記録はまだありません」
  String get caption {
    if (recordedDays == 0) return 'HealthKit の記録はまだありません';
    final base = 'HealthKit · $recordedDays日分の平均';
    if (missingLabels.isEmpty) return base;
    // 日付を並べるのは 3 日まで（それ以上は長くなるので日数だけ）
    final missing = missingLabels.length <= _maxListedMissing
        ? missingLabels.join('、')
        : '${missingLabels.length}日';
    return '$base（$missingは未取得）';
  }

  /// 「9/9」形式（月・日とも 0 埋めなし）
  static String _shortDate(String dateKey) {
    final d = parseSleepDateKey(dateKey);
    return d == null ? dateKey : '${d.month}/${d.day}';
  }
}

/// 直近7日の睡眠時間（棒グラフ + 補足）。カードの中に置く。
///
/// 正本 `record-screens.js` の `SleepTab`: 最大 540 分・高さ 96・棒の上に「6:50」形式の値・
/// 最後の日（今日）を accent・曜日ラベル・取得できなかった日は「未取得」。
/// 下に caption「HealthKit · 6日分の平均（9/9は未取得）」。
class SleepWeekChart extends StatelessWidget {
  final List<DailySleepEntry> entries;

  const SleepWeekChart({super.key, required this.entries});

  /// 棒が最大の高さになる睡眠時間（分）。正本は 540（9時間）
  static const double referenceMaxMinutes = 540;

  /// 睡眠レコードから、今日までの直近 [days] 日（古い日 → 今日）の入力を作る。
  /// 記録が無い日・睡眠時間が無い日（手動の記録のみ）は `minutes: null`（未取得）
  static List<DailySleepEntry> entriesFrom(
    List<SleepRecord> records, {
    int days = 7,
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();
    final byDate = {for (final r in records) r.recordedDate: r};
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final key = jstDateKey(base.subtract(Duration(days: i)));
          return DailySleepEntry(
            dateKey: key,
            minutes: byDate[key]?.totalSleepMinutes,
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final summary = SleepWeekSummary.from(entries);
    final tallest = entries
        .map((e) => e.minutes ?? 0)
        .fold<int>(0, (a, b) => math.max(a, b));
    final max = math.max(referenceMaxMinutes, tallest.toDouble());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FcBars(
          max: max,
          height: 96,
          semanticLabel: '直近7日間の睡眠時間',
          items: [
            for (var i = 0; i < entries.length; i++)
              _barItem(entries[i], highlighted: i == entries.length - 1),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(summary.caption, style: AppTextStyles.caption(context)),
      ],
    );
  }

  FcBarItem _barItem(DailySleepEntry entry, {required bool highlighted}) {
    final date = parseSleepDateKey(entry.dateKey);
    final minutes = entry.minutes;
    return FcBarItem(
      value: minutes?.toDouble(),
      text: minutes == null ? '' : formatSleepHm(minutes),
      highlighted: highlighted,
      label: date == null ? '' : sleepWeekdayLabel(date),
    );
  }
}

// =====================================
// プレビュー
// =====================================

/// 正本のサンプル（9/7〜9/13・9/9 は未取得）
const List<DailySleepEntry> _sampleEntries = [
  DailySleepEntry(dateKey: '2026-09-07', minutes: 410),
  DailySleepEntry(dateKey: '2026-09-08', minutes: 430),
  DailySleepEntry(dateKey: '2026-09-09'),
  DailySleepEntry(dateKey: '2026-09-10', minutes: 390),
  DailySleepEntry(dateKey: '2026-09-11', minutes: 420),
  DailySleepEntry(dateKey: '2026-09-12', minutes: 410),
  DailySleepEntry(dateKey: '2026-09-13', minutes: 450),
];

Widget _previewWeekChart({
  required Brightness brightness,
  double scale = 1,
  List<DailySleepEntry> entries = _sampleEntries,
}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: FcCard(child: SleepWeekChart(entries: entries)),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepWeekChart - Light')
Widget previewSleepWeekChartLight() =>
    _previewWeekChart(brightness: Brightness.light);

@Preview(name: 'SleepWeekChart - Dark')
Widget previewSleepWeekChartDark() =>
    _previewWeekChart(brightness: Brightness.dark);

@Preview(name: 'SleepWeekChart - 文字拡大 1.35')
Widget previewSleepWeekChartLarge() =>
    _previewWeekChart(brightness: Brightness.light, scale: 1.35);

@Preview(name: 'SleepWeekChart - 1日も取得できていない')
Widget previewSleepWeekChartEmpty() => _previewWeekChart(
      brightness: Brightness.light,
      entries: const [
        DailySleepEntry(dateKey: '2026-09-07'),
        DailySleepEntry(dateKey: '2026-09-08'),
        DailySleepEntry(dateKey: '2026-09-09'),
        DailySleepEntry(dateKey: '2026-09-10'),
        DailySleepEntry(dateKey: '2026-09-11'),
        DailySleepEntry(dateKey: '2026-09-12'),
        DailySleepEntry(dateKey: '2026-09-13'),
      ],
    );
