import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';

/// 睡眠記録履歴リストの1行
class SleepHistoryListItem extends StatelessWidget {
  final SleepRecord record;
  final VoidCallback? onTap;

  const SleepHistoryListItem({
    super.key,
    required this.record,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // 日付エリア
            SizedBox(
              width: 54,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatMonthDay(record.recordedDate),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      letterSpacing: -0.14,
                    ),
                  ),
                  Text(
                    '(${_dayOfWeekJa(record.recordedDate)})',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textHint,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 時間 (or "--")
            Expanded(
              child: Text(
                _formatDuration(record.totalSleepMinutes),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: record.totalSleepMinutes != null
                      ? colors.textPrimary
                      : colors.textHint,
                  letterSpacing: -0.16,
                ),
              ),
            ),
            // 目覚めアイコン
            SizedBox(
              width: 22,
              child: Center(child: _ratingIcon(context, record.wakeupRating)),
            ),
            const SizedBox(width: 12),
            // ソースアイコン
            SizedBox(
              width: 14,
              child: Center(
                child: Icon(
                  record.source == SleepSource.healthkit
                      ? LucideIcons.heartPulse
                      : LucideIcons.edit3,
                  size: 12,
                  color: colors.textHint,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight, size: 14, color: AppColors.slate400),
          ],
        ),
      ),
    );
  }

  Widget _ratingIcon(BuildContext context, WakeupRating? rating) {
    if (rating == null) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.slate200,
            width: 1.5,
            style: BorderStyle.solid, // Flutter は dashed border 直接サポートしない
          ),
        ),
      );
    }
    return switch (rating) {
      WakeupRating.refreshed =>
        const Icon(LucideIcons.smile, size: 18, color: AppColors.success),
      WakeupRating.okay =>
        const Icon(LucideIcons.meh, size: 18, color: AppColors.warning),
      WakeupRating.groggy =>
        const Icon(LucideIcons.frown, size: 18, color: AppColors.error),
    };
  }

  String _formatMonthDay(String yyyyMmDd) {
    // "2026-04-19" → "4/19"
    final parts = yyyyMmDd.split('-');
    if (parts.length != 3) return yyyyMmDd;
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;
    return '$m/$d';
  }

  String _dayOfWeekJa(String yyyyMmDd) {
    final dt = DateTime.tryParse(yyyyMmDd);
    if (dt == null) return '';
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return labels[dt.weekday - 1];
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return '--';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h時間$m分';
  }
}

/// プレビュー用ヘルパー: 静的データで SleepRecord を生成
SleepRecord _mockRecord({
  String date = '2026-04-19',
  int? totalMin = 443,
  WakeupRating? rating = WakeupRating.refreshed,
  SleepSource source = SleepSource.healthkit,
}) {
  final now = DateTime.now();
  return SleepRecord(
    id: '00000000-0000-0000-0000-000000000001',
    clientId: '00000000-0000-0000-0000-000000000002',
    recordedDate: date,
    bedTime: source == SleepSource.healthkit ? now : null,
    wakeTime: source == SleepSource.healthkit ? now : null,
    totalSleepMinutes: totalMin,
    deepMinutes: totalMin != null ? 110 : null,
    lightMinutes: totalMin != null ? 221 : null,
    remMinutes: totalMin != null ? 88 : null,
    awakeMinutes: totalMin != null ? 24 : null,
    wakeupRating: rating,
    source: source,
    createdAt: now,
    updatedAt: now,
  );
}

@Preview(name: 'SleepHistoryListItem - HealthKit')
Widget previewSleepHistoryListItemHealthKit() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: SleepHistoryListItem(record: _mockRecord()),
      ),
    ),
  );
}

@Preview(name: 'SleepHistoryListItem - Manual Only')
Widget previewSleepHistoryListItemManual() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: SleepHistoryListItem(record: _mockRecord(
          totalMin: null,
          rating: WakeupRating.okay,
          source: SleepSource.manual,
        )),
      ),
    ),
  );
}

@Preview(name: 'SleepHistoryListItem - No Rating')
Widget previewSleepHistoryListItemNoRating() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: SleepHistoryListItem(record: _mockRecord(
          rating: null,
        )),
      ),
    ),
  );
}
