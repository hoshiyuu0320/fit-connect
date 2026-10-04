import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/utils/sleep_labels.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 睡眠記録の履歴の1行。[FcRowsCard] の中に並べて使う（行の間の区切り線はカードが引く）。
///
/// 正本 `record-screens.js` の `ListCard` の行:
/// - 左: 日付「9月12日（土）」（16・tabular）の下に caption「目覚め まあまあ」
/// - 右: 睡眠時間「6時間50分」（16 / 500）。**取得できていない（手動の記録のみ）日は「未取得」**
///   （textSecondary）で、caption は「目覚め だるい · 手動の記録のみ」。未取得を 0 と表示しない
/// - 目覚めの評価は絵文字・アイコンではなく言葉（すっきり / まあまあ / だるい / 未記録）
class SleepHistoryListItem extends StatelessWidget {
  final SleepRecord record;
  final VoidCallback? onTap;

  /// 年の付与判定に使う現在時刻（省略時は今）。年が違う記録だけ「2025年12月28日（日）」と年を付ける
  final DateTime? now;

  const SleepHistoryListItem({
    super.key,
    required this.record,
    this.onTap,
    this.now,
  });

  /// 行の補足「目覚め まあまあ」「目覚め だるい · 手動の記録のみ」
  static String captionFor(SleepRecord record) {
    final rating = record.wakeupRating?.labelJa ?? '未記録';
    final manualOnly =
        !record.hasObjectiveData && record.source == SleepSource.manual;
    return manualOnly ? '目覚め $rating · 手動の記録のみ' : '目覚め $rating';
  }

  @override
  Widget build(BuildContext context) {
    final minutes = record.totalSleepMinutes;
    final date = parseSleepDateKey(record.recordedDate);
    final title = date == null
        ? record.recordedDate
        : formatSleepDate(date, now: now ?? DateTime.now());

    return FcListRow(
      density: FcRowDensity.record,
      title: title,
      caption: captionFor(record),
      trailing: minutes == null
          ? const FcRowValue.text('未取得', muted: true)
          : FcRowValue.text(formatSleepDuration(minutes)),
      onTap: onTap,
    );
  }
}

// =====================================
// プレビュー
// =====================================

/// プレビュー用: 静的データで SleepRecord を作る
SleepRecord _mockRecord({
  String date = '2026-09-12',
  int? totalMin = 410,
  WakeupRating? rating = WakeupRating.okay,
  SleepSource source = SleepSource.healthkit,
}) {
  final created = DateTime(2026, 9, 13, 7, 32);
  return SleepRecord(
    id: '00000000-0000-0000-0000-000000000001',
    clientId: '00000000-0000-0000-0000-000000000002',
    recordedDate: date,
    totalSleepMinutes: totalMin,
    wakeupRating: rating,
    source: source,
    createdAt: created,
    updatedAt: created,
  );
}

Widget _previewHistory({required Brightness brightness, double scale = 1}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: FcRowsCard(
            children: [
              SleepHistoryListItem(record: _mockRecord()),
              SleepHistoryListItem(
                record: _mockRecord(
                  date: '2026-09-11',
                  totalMin: 420,
                  rating: WakeupRating.refreshed,
                ),
              ),
              SleepHistoryListItem(
                record: _mockRecord(
                  date: '2026-09-10',
                  totalMin: 390,
                  rating: null,
                ),
              ),
              SleepHistoryListItem(
                record: _mockRecord(
                  date: '2026-09-09',
                  totalMin: null,
                  rating: WakeupRating.groggy,
                  source: SleepSource.manual,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepHistoryListItem - Light')
Widget previewSleepHistoryListItemLight() =>
    _previewHistory(brightness: Brightness.light);

@Preview(name: 'SleepHistoryListItem - Dark')
Widget previewSleepHistoryListItemDark() =>
    _previewHistory(brightness: Brightness.dark);

@Preview(name: 'SleepHistoryListItem - 文字拡大 1.35')
Widget previewSleepHistoryListItemLarge() =>
    _previewHistory(brightness: Brightness.light, scale: 1.35);
