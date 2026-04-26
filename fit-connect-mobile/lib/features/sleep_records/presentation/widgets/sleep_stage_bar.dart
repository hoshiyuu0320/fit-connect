import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

/// 睡眠ステージの水平スタックバー（案A）+ 凡例（4項目グリッド）
class SleepStageBar extends StatelessWidget {
  final int deepMinutes;
  final int lightMinutes;
  final int remMinutes;
  final int awakeMinutes;
  final double height;

  const SleepStageBar({
    super.key,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    this.height = 28,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    final total = deepMinutes + lightMinutes + remMinutes + awakeMinutes;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                if (deepMinutes > 0)
                  Expanded(
                    flex: deepMinutes,
                    child: Container(color: colors.sleepStageDeep),
                  ),
                if (lightMinutes > 0)
                  Expanded(
                    flex: lightMinutes,
                    child: Container(color: colors.sleepStageLight),
                  ),
                if (remMinutes > 0)
                  Expanded(
                    flex: remMinutes,
                    child: Container(color: colors.sleepStageRem),
                  ),
                if (awakeMinutes > 0)
                  Expanded(
                    flex: awakeMinutes,
                    child: Container(color: colors.sleepStageAwake),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _legend(context, total),
      ],
    );
  }

  Widget _legend(BuildContext context, int total) {
    final colors = AppColorsExtension.of(context);
    final items = <_LegendItem>[
      _LegendItem('深い', colors.sleepStageDeep, deepMinutes),
      _LegendItem('浅い', colors.sleepStageLight, lightMinutes),
      _LegendItem('REM', colors.sleepStageRem, remMinutes),
      _LegendItem('覚醒', colors.sleepStageAwake, awakeMinutes),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 6,
      mainAxisSpacing: 6,
      crossAxisSpacing: 12,
      children: items.map((it) => _legendRow(context, it, total)).toList(),
    );
  }

  Widget _legendRow(BuildContext context, _LegendItem it, int total) {
    final colors = AppColorsExtension.of(context);
    final pct = ((it.minutes / total) * 100).round();
    final h = it.minutes ~/ 60;
    final m = it.minutes % 60;
    final timeLabel = h > 0 ? '${h}h${m}m' : '${m}m';
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: it.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          it.label,
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$pct%',
          style: TextStyle(
            fontSize: 12,
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '($timeLabel)',
          style: TextStyle(fontSize: 11, color: colors.textHint),
        ),
      ],
    );
  }
}

class _LegendItem {
  final String label;
  final Color color;
  final int minutes;
  const _LegendItem(this.label, this.color, this.minutes);
}

@Preview(name: 'SleepStageBar - Normal')
Widget previewSleepStageBarNormal() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SleepStageBar(
            deepMinutes: 110,
            lightMinutes: 221,
            remMinutes: 88,
            awakeMinutes: 22,
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepStageBar - All Deep')
Widget previewSleepStageBarAllDeep() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SleepStageBar(
            deepMinutes: 420,
            lightMinutes: 0,
            remMinutes: 0,
            awakeMinutes: 0,
          ),
        ),
      ),
    ),
  );
}
