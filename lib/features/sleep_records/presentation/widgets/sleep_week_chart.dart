import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';

/// 1日分の入力エントリ
class DailySleepEntry {
  final String dateLabel; // "4/12"
  final double? hours; // null=データ無し
  final WakeupRating? rating;

  const DailySleepEntry({
    required this.dateLabel,
    this.hours,
    this.rating,
  });
}

/// 直近7日分の睡眠時間折れ線グラフ + 目覚めアイコン併記
class SleepWeekChart extends StatelessWidget {
  final List<DailySleepEntry> entries;
  final double height;
  final bool showRatings;

  const SleepWeekChart({
    super.key,
    required this.entries,
    this.height = 160,
    this.showRatings = true,
  });

  @override
  Widget build(BuildContext context) {
    final chartHeight = height - (showRatings ? 40 : 20);

    // hours 値の min/max（最低 4-10h レンジ）
    const minY = 4.0;
    const maxY = 10.0;

    final colors = AppColorsExtension.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: chartHeight,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: (entries.length - 1).toDouble(),
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: colors.border,
                  strokeWidth: 1,
                ),
                checkToShowHorizontalLine: (value) =>
                    value >= 5 && value <= 9,
              ),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: _buildLineBars(context),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _buildXAxisLabels(context),
      ],
    );
  }

  /// 連続したデータ点をつなぐ LineChartBarData。null日はギャップとして分離
  List<LineChartBarData> _buildLineBars(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    final segments = <List<FlSpot>>[];
    var current = <FlSpot>[];

    for (var i = 0; i < entries.length; i++) {
      final v = entries[i].hours;
      if (v == null) {
        if (current.length > 1) segments.add(current);
        current = [];
      } else {
        current.add(FlSpot(i.toDouble(), v));
      }
    }
    if (current.length > 1) segments.add(current);

    return segments.map((seg) {
      return LineChartBarData(
        spots: seg,
        isCurved: false,
        color: AppColors.primary,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
            radius: 3.5,
            color: colors.surface,
            strokeColor: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withValues(alpha: 0.24),
              AppColors.primary.withValues(alpha: 0),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildXAxisLabels(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Row(
      children: [
        for (var i = 0; i < entries.length; i++)
          Expanded(
            child: Column(
              children: [
                Text(
                  entries[i].dateLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: i == entries.length - 1
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: i == entries.length - 1
                        ? colors.textSecondary
                        : colors.textHint,
                  ),
                ),
                if (showRatings)
                  SizedBox(
                    height: 14,
                    child: entries[i].rating == null
                        ? const SizedBox.shrink()
                        : _ratingIcon(entries[i].rating!),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _ratingIcon(WakeupRating r) {
    return switch (r) {
      WakeupRating.refreshed =>
        const Icon(LucideIcons.smile, size: 12, color: AppColors.success),
      WakeupRating.okay =>
        const Icon(LucideIcons.meh, size: 12, color: AppColors.warning),
      WakeupRating.groggy =>
        const Icon(LucideIcons.frown, size: 12, color: AppColors.error),
    };
  }
}

@Preview(name: 'SleepWeekChart - Full 7days')
Widget previewSleepWeekChartFull() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const SleepWeekChart(
            entries: [
              DailySleepEntry(
                  dateLabel: '4/19',
                  hours: 7.2,
                  rating: WakeupRating.refreshed),
              DailySleepEntry(
                  dateLabel: '4/20', hours: 6.5, rating: WakeupRating.okay),
              DailySleepEntry(
                  dateLabel: '4/21',
                  hours: 8.0,
                  rating: WakeupRating.refreshed),
              DailySleepEntry(
                  dateLabel: '4/22',
                  hours: 7.5,
                  rating: WakeupRating.refreshed),
              DailySleepEntry(
                  dateLabel: '4/23',
                  hours: 7.8,
                  rating: WakeupRating.refreshed),
              DailySleepEntry(
                  dateLabel: '4/24', hours: 6.0, rating: WakeupRating.groggy),
              DailySleepEntry(
                  dateLabel: '4/25',
                  hours: 7.3,
                  rating: WakeupRating.refreshed),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepWeekChart - With Null Gap')
Widget previewSleepWeekChartWithGap() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const SleepWeekChart(
            entries: [
              DailySleepEntry(
                  dateLabel: '4/19',
                  hours: 7.2,
                  rating: WakeupRating.refreshed),
              DailySleepEntry(
                  dateLabel: '4/20', hours: 6.5, rating: WakeupRating.okay),
              DailySleepEntry(
                  dateLabel: '4/21',
                  hours: 8.0,
                  rating: WakeupRating.refreshed),
              DailySleepEntry(dateLabel: '4/22'),
              DailySleepEntry(
                  dateLabel: '4/23',
                  hours: 7.8,
                  rating: WakeupRating.refreshed),
              DailySleepEntry(
                  dateLabel: '4/24', hours: 6.0, rating: WakeupRating.groggy),
              DailySleepEntry(
                  dateLabel: '4/25',
                  hours: 7.3,
                  rating: WakeupRating.refreshed),
            ],
          ),
        ),
      ),
    ),
  );
}
