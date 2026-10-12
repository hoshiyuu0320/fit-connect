import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 睡眠ステージの内訳（帯 + 凡例）。基盤の [FcSleepStageBar] に分（深い・レム・浅い・覚醒）を渡す薄い包み。
///
/// 正本 `record-screens.js` の `StageBar`: 色はカテゴリ色ではなく accent の濃淡
/// （深い 100% / レム 60% / 浅い 30%）と、覚醒だけ separator。並びは 深い → レム → 浅い → 覚醒。
/// 4 つとも 0 分（データなし）のときは何も出さない。上の余白（正本は 16）は含まない。
class SleepStageBar extends StatelessWidget {
  final int deepMinutes;
  final int lightMinutes;
  final int remMinutes;
  final int awakeMinutes;

  const SleepStageBar({
    super.key,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final total = deepMinutes + lightMinutes + remMinutes + awakeMinutes;
    if (total == 0) return const SizedBox.shrink();

    return FcSleepStageBar(
      stages: [
        FcSleepStage(label: '深い', minutes: deepMinutes, percent: 100),
        FcSleepStage(label: 'レム', minutes: remMinutes, percent: 60),
        FcSleepStage(label: '浅い', minutes: lightMinutes, percent: 30),
        FcSleepStage(label: '覚醒', minutes: awakeMinutes, percent: 0),
      ],
    );
  }
}

// =====================================
// プレビュー
// =====================================

Widget _previewStageBar({required Brightness brightness, double scale = 1}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: FcCard(
            child: const SleepStageBar(
              deepMinutes: 85,
              lightMinutes: 255,
              remMinutes: 110,
              awakeMinutes: 20,
            ),
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepStageBar - Light')
Widget previewSleepStageBarLight() =>
    _previewStageBar(brightness: Brightness.light);

@Preview(name: 'SleepStageBar - Dark')
Widget previewSleepStageBarDark() =>
    _previewStageBar(brightness: Brightness.dark);

@Preview(name: 'SleepStageBar - 文字拡大 1.35')
Widget previewSleepStageBarLarge() =>
    _previewStageBar(brightness: Brightness.light, scale: 1.35);

@Preview(name: 'SleepStageBar - 深い睡眠のみ')
Widget previewSleepStageBarAllDeep() {
  return FcPreviewApp(
    brightness: Brightness.light,
    home: const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
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
