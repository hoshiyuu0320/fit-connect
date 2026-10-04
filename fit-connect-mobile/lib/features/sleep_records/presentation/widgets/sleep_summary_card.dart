import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/utils/sleep_labels.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_stage_bar.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 正本 `SleepTab` のカード内の間隔 14（就寝/起床の囲みの上・区切り線の上）。間隔スケール（4/8/12/16…）に無い値
const double _gap = 14;

/// 「昨夜の睡眠」カード。正本 `record-screens.js` の `SleepTab` 先頭のカード。
///
/// - 見出し: moon「昨夜の睡眠」＋ 右に連携元のピル「HealthKit」（muted・heart-pulse）
/// - 大きな時間「7時間30分」（34）
/// - 就寝 / 起床（2列の囲み）→ 睡眠ステージ（深い / レム / 浅い / 覚醒。accent の濃淡）
/// - 区切り線 → 「目覚め」＋ 評価の言葉のピル（絵文字・アイコンは使わない）＋ 右に「編集」
///
/// HealthKit の値が無く手動の記録（目覚めの評価）だけの日は、時間を「未取得」と出し
/// （0 と表示しない）、詳細データの取得を促す囲みを出す。
class SleepSummaryCard extends StatelessWidget {
  final SleepRecord record;

  /// 目覚めの評価の記録・編集（「編集」を押したとき）
  final VoidCallback onEditWakeup;

  const SleepSummaryCard({
    super.key,
    required this.record,
    required this.onEditWakeup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final minutes = record.totalSleepMinutes;
    final hasObjective = minutes != null;
    final stageTotal = (record.deepMinutes ?? 0) +
        (record.lightMinutes ?? 0) +
        (record.remMinutes ?? 0) +
        (record.awakeMinutes ?? 0);

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FcCardHead(
            icon: LucideIcons.moon,
            label: '昨夜の睡眠',
            trailing: hasObjective
                ? const FcPill(
                    'HealthKit',
                    tone: FcPillTone.muted,
                    icon: LucideIcons.heartPulse,
                  )
                : const FcPill(
                    '手動の記録',
                    tone: FcPillTone.muted,
                    icon: LucideIcons.pencil,
                  ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: hasObjective
                ? FcNum.parts(
                    parts: sleepDurationParts(minutes),
                    size: FcNumSize.review,
                  )
                : FcNum(
                    value: '未取得',
                    size: FcNumSize.review,
                    color: colors.textSecondary,
                  ),
          ),
          const SizedBox(height: _gap),
          if (hasObjective) ...[
            FcInfoBox(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: _ClockColumn(label: '就寝', time: record.bedTime)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: _ClockColumn(label: '起床', time: record.wakeTime)),
                ],
              ),
            ),
            if (stageTotal > 0) ...[
              // 正本の StageBar は上に 16
              const SizedBox(height: AppSpacing.lg),
              SleepStageBar(
                deepMinutes: record.deepMinutes ?? 0,
                lightMinutes: record.lightMinutes ?? 0,
                remMinutes: record.remMinutes ?? 0,
                awakeMinutes: record.awakeMinutes ?? 0,
              ),
            ],
          ] else
            FcInfoBox(
              child: Text(
                '詳細データを取得するにはヘルスケア連携を有効にしてください',
                style: AppTextStyles.supplement(context),
              ),
            ),
          const SizedBox(height: _gap),
          const FcSeparator(),
          const SizedBox(height: AppSpacing.xs),
          _WakeupRow(rating: record.wakeupRating, onEdit: onEditWakeup),
        ],
      ),
    );
  }
}

/// 就寝 / 起床の 1 列（caption + 17 / 500 の時刻）。時刻が無ければ「未取得」
class _ClockColumn extends StatelessWidget {
  final String label;
  final DateTime? time;

  const _ClockColumn({required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = time == null ? '未取得' : formatSleepClock(time!.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption(context)),
        Text(
          text,
          style: AppTextStyles.exerciseName(context).copyWith(
            fontFeatures: AppTextStyles.tabularFigures,
            color: time == null ? colors.textSecondary : colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// 「目覚め」＋ 評価の言葉のピル ＋ 右に「編集」。評価が無ければピルは「未記録」、操作は「記録」
class _WakeupRow extends StatelessWidget {
  final WakeupRating? rating;
  final VoidCallback onEdit;

  const _WakeupRow({required this.rating, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final recorded = rating != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('目覚め', style: AppTextStyles.supplement(context)),
              recorded
                  ? FcPill(rating!.labelJa)
                  : const FcPill('未記録', tone: FcPillTone.muted),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FcButton.back(
          label: recorded ? '編集' : '記録',
          icon: LucideIcons.pencil,
          semanticLabel: recorded ? '目覚めを編集' : '目覚めを記録',
          onPressed: onEdit,
        ),
      ],
    );
  }
}

/// 今日の記録がまだ無いときの「昨夜の睡眠」カード（目覚めを記録する入口つき）
class SleepSummaryEmptyCard extends StatelessWidget {
  final VoidCallback onRecordWakeup;

  const SleepSummaryEmptyCard({super.key, required this.onRecordWakeup});

  @override
  Widget build(BuildContext context) {
    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FcCardHead(icon: LucideIcons.moon, label: '昨夜の睡眠'),
          Text('今日の記録はまだありません', style: AppTextStyles.body(context)),
          const SizedBox(height: _gap),
          FcButton.pill(label: '目覚めを記録', onPressed: onRecordWakeup),
        ],
      ),
    );
  }
}

/// 読み込み中の「昨夜の睡眠」カード（配置を保つスケルトン）
class SleepSummaryLoadingCard extends StatelessWidget {
  const SleepSummaryLoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '読み込み中',
      child: const FcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcSkeleton.line(width: 96),
            SizedBox(height: AppSpacing.md),
            FcSkeleton(width: 168, height: 34, radius: 8),
            SizedBox(height: _gap),
            FcSkeleton(height: 58, radius: AppRadius.input),
            SizedBox(height: AppSpacing.lg),
            FcSkeleton(height: 10, radius: 5),
            SizedBox(height: AppSpacing.md),
            FcSkeleton.line(width: 220),
          ],
        ),
      ),
    );
  }
}

// =====================================
// プレビュー
// =====================================

SleepRecord _record({
  int? total = 450,
  WakeupRating? rating = WakeupRating.refreshed,
  SleepSource source = SleepSource.healthkit,
}) {
  final synced = DateTime(2026, 9, 13, 7, 32);
  return SleepRecord(
    id: 'preview',
    clientId: 'preview-client',
    recordedDate: '2026-09-13',
    bedTime: total == null ? null : DateTime(2026, 9, 12, 23, 30),
    wakeTime: total == null ? null : DateTime(2026, 9, 13, 7, 20),
    totalSleepMinutes: total,
    deepMinutes: total == null ? null : 85,
    lightMinutes: total == null ? null : 255,
    remMinutes: total == null ? null : 110,
    awakeMinutes: total == null ? null : 20,
    wakeupRating: rating,
    source: source,
    createdAt: synced,
    updatedAt: synced,
  );
}

Widget _previewCard({
  required Brightness brightness,
  required Widget card,
  double scale = 1,
}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: card,
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepSummaryCard - HealthKit（ライト）')
Widget previewSleepSummaryCardLight() => _previewCard(
      brightness: Brightness.light,
      card: SleepSummaryCard(record: _record(), onEditWakeup: () {}),
    );

@Preview(name: 'SleepSummaryCard - HealthKit（ダーク）')
Widget previewSleepSummaryCardDark() => _previewCard(
      brightness: Brightness.dark,
      card: SleepSummaryCard(record: _record(), onEditWakeup: () {}),
    );

@Preview(name: 'SleepSummaryCard - 文字拡大 1.35')
Widget previewSleepSummaryCardLarge() => _previewCard(
      brightness: Brightness.light,
      scale: 1.35,
      card: SleepSummaryCard(
        record: _record(rating: WakeupRating.okay),
        onEditWakeup: () {},
      ),
    );

@Preview(name: 'SleepSummaryCard - 手動の記録のみ')
Widget previewSleepSummaryCardManualOnly() => _previewCard(
      brightness: Brightness.light,
      card: SleepSummaryCard(
        record: _record(
          total: null,
          rating: WakeupRating.groggy,
          source: SleepSource.manual,
        ),
        onEditWakeup: () {},
      ),
    );

@Preview(name: 'SleepSummaryCard - 目覚め未記録')
Widget previewSleepSummaryCardNoRating() => _previewCard(
      brightness: Brightness.light,
      card:
          SleepSummaryCard(record: _record(rating: null), onEditWakeup: () {}),
    );

@Preview(name: 'SleepSummaryEmptyCard - 今日の記録なし')
Widget previewSleepSummaryEmptyCard() => _previewCard(
      brightness: Brightness.light,
      card: SleepSummaryEmptyCard(onRecordWakeup: () {}),
    );

@Preview(name: 'SleepSummaryLoadingCard - 読込中')
Widget previewSleepSummaryLoadingCard() => _previewCard(
      brightness: Brightness.light,
      card: const SleepSummaryLoadingCard(),
    );
