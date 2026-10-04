import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/widgets/weight_format.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 記録画面「体重」タブ本体。
///
/// 現在 / 目標 / 目標まで、開始時・前回からの差、期間の平均・最高・最低・変動幅、推移のグラフ、
/// 最近の記録を並べる。**達成率（％）や進捗バーは出さない**（「目標まで X kg」に置き換え）。
/// 増減の符号で色分けしない。体重の記録はメッセージ（#体重）やヘルスケア連携から入るので、
/// この画面から追加・編集・削除する操作は元から無い。
class WeightRecordScreen extends ConsumerStatefulWidget {
  /// 記録がまだ無いときの「メッセージから記録する」を押したとき（メッセージタブへ移る）。
  /// null なら入口は出さず、文言だけ
  final VoidCallback? onOpenMessages;

  const WeightRecordScreen({super.key, this.onOpenMessages});

  @override
  ConsumerState<WeightRecordScreen> createState() => _WeightRecordScreenState();
}

class _WeightRecordScreenState extends ConsumerState<WeightRecordScreen> {
  PeriodFilter _selectedPeriod = PeriodFilter.week;

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(
      weightRecordsProvider(period: _selectedPeriod),
    );
    final latestAsync = ref.watch(latestWeightRecordProvider);
    final goalAsync = ref.watch(currentGoalProvider);

    return _WeightScrollView(
      period: _selectedPeriod,
      onPeriodChanged: (p) => setState(() => _selectedPeriod = p),
      child: _WeightContent(
        period: _selectedPeriod,
        recordsAsync: recordsAsync,
        latestAsync: latestAsync,
        goalAsync: goalAsync,
        now: DateTime.now(),
        onOpenMessages: widget.onOpenMessages,
        // 失敗したカードだけを読み直す
        onRetryRecords: () =>
            ref.invalidate(weightRecordsProvider(period: _selectedPeriod)),
        onRetryProfile: () {
          ref.invalidate(latestWeightRecordProvider);
          ref.invalidate(currentGoalProvider);
        },
      ),
    );
  }
}

/// 期間セグメント ＋ 本文を縦に並べるスクロール領域。
///
/// 左右の余白は自分で持つ。下はナビぶん（`MediaQuery.padding.bottom`）を空ける。
class _WeightScrollView extends StatelessWidget {
  const _WeightScrollView({
    required this.period,
    required this.onPeriodChanged,
    required this.child,
  });

  final PeriodFilter period;
  final ValueChanged<PeriodFilter> onPeriodChanged;
  final Widget child;

  /// 選べる期間（今日は除く。今週 / 今月 / 3ヶ月 / 全期間）
  static final List<PeriodFilter> periods =
      PeriodFilter.values.where((p) => p != PeriodFilter.today).toList();

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        0,
        horizontal,
        MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: '期間',
          child: FcSegmentedControl<PeriodFilter>(
            items: [
              for (final p in periods)
                FcSegmentedItem<PeriodFilter>(value: p, label: p.label),
            ],
            selected: period,
            onChanged: onPeriodChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        child,
      ],
    );
  }
}

bool _failed(AsyncValue<Object?> value) => value.hasError;

bool _pending(AsyncValue<Object?> value) =>
    !value.hasValue && !value.hasError;

/// 体重タブの本文。記録がまったく無ければ空の状態。
///
/// 読み込みと失敗は**カードごと**に扱う（失敗したカードだけ「読み込めませんでした」と再試行を出し、
/// ほかのカードは出し続ける）:
/// - 上の大きなカード: 最新の体重・目標が必要。読めなければカードごとエラー。
///   期間の記録だけ読めないときは、現在・目標・目標まで・開始時からは出し、前回から・期間の集計は「—」
/// - 「体重の推移」と「最近の記録」: 期間の記録が必要。読めなければ推移のカードがエラー
class _WeightContent extends StatelessWidget {
  const _WeightContent({
    required this.period,
    required this.recordsAsync,
    required this.latestAsync,
    required this.goalAsync,
    required this.now,
    this.onOpenMessages,
    this.onRetryRecords,
    this.onRetryProfile,
  });

  final PeriodFilter period;

  /// 期間内の記録（新しい順）
  final AsyncValue<List<WeightRecord>> recordsAsync;

  /// いちばん新しい記録（期間に関係なく）
  final AsyncValue<WeightRecord?> latestAsync;
  final AsyncValue<Client?> goalAsync;
  final DateTime now;

  /// 記録がまだ無いときの「メッセージから記録する」。null なら出さない
  final VoidCallback? onOpenMessages;

  /// 期間の記録の「再試行」
  final VoidCallback? onRetryRecords;

  /// 最新の体重・目標の「再試行」
  final VoidCallback? onRetryProfile;

  /// 「9月の記録 7件から計算」の「9月」にあたる言葉
  String get _periodWord {
    switch (period) {
      case PeriodFilter.today:
        return '今日';
      case PeriodFilter.week:
        return '今週';
      case PeriodFilter.month:
        return '${now.month}月';
      case PeriodFilter.threeMonths:
        return '直近3ヶ月';
      case PeriodFilter.all:
        return '全期間';
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordsFailed = _failed(recordsAsync);
    final records = recordsFailed ? null : recordsAsync.valueOrNull;
    final goalFailed = _failed(goalAsync);

    // 最新の体重も期間の記録も読めていて、どちらも無い
    if (!recordsFailed &&
        !_failed(latestAsync) &&
        records != null &&
        latestAsync.hasValue &&
        latestAsync.requireValue == null &&
        records.isEmpty) {
      return FcStateMessage.empty(
        title: 'まだ記録がありません',
        message: '体重を記録すると、ここに推移が表示されます。メッセージ画面で「#体重 62.4kg」のように送ると記録できます。',
        actionLabel: onOpenMessages == null ? null : 'メッセージから記録する',
        actionIcon: LucideIcons.messageCircle,
        onAction: onOpenMessages,
      );
    }

    // 上の大きなカード
    final Widget summary;
    if (_failed(latestAsync) || goalFailed) {
      summary = _CardError(
        message: '現在の体重と目標を読み込めませんでした。通信の状態を確認して、もう一度お試しください。',
        onRetry: onRetryProfile,
      );
    } else if (_pending(latestAsync) ||
        _pending(goalAsync) ||
        _pending(recordsAsync)) {
      summary = const _SummarySkeleton();
    } else {
      summary = _SummaryCard(
        records: records,
        latest: latestAsync.requireValue,
        goal: goalAsync.requireValue,
        periodWord: _periodWord,
      );
    }

    // 体重の推移のカード
    final Widget trend;
    if (recordsFailed) {
      trend = _CardError(
        message: '体重の推移と最近の記録を読み込めませんでした。通信の状態を確認して、もう一度お試しください。',
        onRetry: onRetryRecords,
      );
    } else if (_pending(recordsAsync) || _pending(goalAsync)) {
      trend = const _TrendSkeleton();
    } else {
      trend = _TrendCard(
        records: records!,
        // 目標が読めなかったときは、目標線なしで推移だけ出す
        target: goalFailed ? null : goalAsync.requireValue?.targetWeight,
        periodWord: _periodWord,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summary,
        const SizedBox(height: AppSpacing.cardGap),
        trend,
        if (records != null && records.isNotEmpty) ...[
          const FcSectionTitle('最近の記録'),
          const SizedBox(height: AppSpacing.cardGap),
          _RecentRecords(records: records),
        ],
      ],
    );
  }
}

/// カードひとつぶんの読み込み失敗（失敗した理由の文字は出さない）
class _CardError extends StatelessWidget {
  const _CardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FcStateMessage.error(
      title: '読み込めませんでした',
      message: message,
      actionLabel: onRetry == null ? null : '再試行',
      onAction: onRetry,
    );
  }
}

/// 数値を横に並べる格子（正本の `grid-template-columns: repeat(auto-fit, minmax(Npx, 1fr))`）。
///
/// 収まる列数だけ等幅で並べ、足りなければ次の行へ積み直す。
/// 文字拡大のときは最小幅も拡大に合わせて広げる（収まらない文字を縮めず、行を増やして逃がす）。
class _AutoFitGrid extends StatelessWidget {
  const _AutoFitGrid({
    required this.minItemWidth,
    required this.gap,
    required this.children,
  });

  final double minItemWidth;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
        final minWidth = minItemWidth * scale;
        final fit = ((constraints.maxWidth + gap) / (minWidth + gap)).floor();
        final columns = math.max(1, math.min(children.length, fit));

        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final slice = children.skip(start).take(columns).toList();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(
                    child: c < slice.length ? slice[c] : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// 平均・最高・最低・変動幅の 1 つ（ラベル caption ＋ 値 17 / 500 ＋ 単位 caption）
class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;

  /// kg の値（小数 1 桁）。null は「—」（記録がない）
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final valueStyle = AppTextStyles.exerciseName(context).copyWith(
      fontFeatures: AppTextStyles.tabularFigures,
      color: value == null ? colors.textSecondary : colors.textPrimary,
    );
    final unitStyle = AppTextStyles.caption(context);

    return Semantics(
      container: true,
      label: '$label ${value == null ? '記録なし' : '$value kg'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.caption(context)),
          Text.rich(
            TextSpan(
              style: valueStyle,
              children: [
                TextSpan(text: value ?? '—'),
                if (value != null) ...[
                  const WidgetSpan(child: SizedBox(width: 2)),
                  TextSpan(text: 'kg', style: unitStyle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 上の大きなカード（現在 / 目標 / 目標まで → 開始時・前回から → 平均・最高・最低・変動幅）
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.records,
    required this.latest,
    required this.goal,
    required this.periodWord,
  });

  /// 期間内の記録（新しい順）。**null は読み込めなかった**（空リストの「記録なし」とは別）
  final List<WeightRecord>? records;
  final WeightRecord? latest;
  final Client? goal;
  final String periodWord;

  @override
  Widget build(BuildContext context) {
    final records = this.records;
    final current = latest?.weight;
    final target = goal?.targetWeight;

    // 開始時の体重: 目標に設定された開始時の体重。無ければ期間内の最古の記録（現行どおり）
    final oldest = (records == null || records.isEmpty) ? null : records.last.weight;
    final initial = goal?.initialWeight ?? oldest;
    final fromStart =
        (current != null && initial != null) ? current - initial : null;
    final fromPrevious = (records != null && records.length >= 2)
        ? records[0].weight - records[1].weight
        : null;

    // 目標まで（減量・増量の両方）。届いた・超えたときは静かに文言だけで伝える（色や演出は付けない）
    String remainingLabel = '目標まで';
    String remainingValue = '—';
    String? remainingUnit;
    String? remainingCaption;
    if (current != null && target != null) {
      final isLossGoal = (initial ?? current) > target;
      final reached = isLossGoal ? current <= target : current >= target;
      final diff = (current - target).abs();
      remainingValue = formatKg(diff);
      remainingUnit = 'kg';
      if (reached) {
        remainingCaption = '目標に届きました';
        if (diff != 0) remainingLabel = '目標との差';
      }
    }

    // 期間の平均・最高・最低・変動幅（記録から計算。weightStatsProvider と同じ集計）
    String? average;
    String? highest;
    String? lowest;
    String? spread;
    if (records != null && records.isNotEmpty) {
      final weights = records.map((r) => r.weight).toList();
      final sum = weights.reduce((a, b) => a + b);
      final maxWeight = weights.reduce(math.max);
      final minWeight = weights.reduce(math.min);
      average = formatKg(sum / weights.length);
      highest = formatKg(maxWeight);
      lowest = formatKg(minWeight);
      spread = formatKg(maxWeight - minWeight);
    }

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AutoFitGrid(
            minItemWidth: 88,
            gap: AppSpacing.md,
            children: [
              FcStat(
                label: '現在',
                value: current == null ? '—' : formatKg(current),
                unit: current == null ? null : 'kg',
              ),
              FcStat(
                label: '目標',
                value: target == null ? '未設定' : formatKg(target),
                unit: target == null ? null : 'kg',
              ),
              FcStat(
                label: remainingLabel,
                value: remainingValue,
                unit: remainingUnit,
                caption: remainingCaption,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: FcSeparator(),
          ),
          _AutoFitGrid(
            minItemWidth: 120,
            gap: AppSpacing.md,
            children: [
              FcStat(
                label: '開始時から',
                value: fromStart == null ? '—' : formatSignedKg(fromStart),
                unit: fromStart == null ? null : 'kg',
                size: FcNumSize.compact,
              ),
              FcStat(
                label: '前回から',
                value: fromPrevious == null ? '—' : formatSignedKg(fromPrevious),
                unit: fromPrevious == null ? null : 'kg',
                size: FcNumSize.compact,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.md),
            child: FcSeparator(),
          ),
          _AutoFitGrid(
            minItemWidth: 64,
            gap: AppSpacing.sm,
            children: [
              _MiniStat(label: '平均', value: average),
              _MiniStat(label: '最高', value: highest),
              _MiniStat(label: '最低', value: lowest),
              _MiniStat(label: '変動幅', value: spread),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              records == null
                  ? 'この期間の記録を読み込めませんでした'
                  : records.isEmpty
                      ? 'この期間の記録はありません'
                      : '$periodWordの記録 ${records.length}件から計算',
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「体重の推移」のカード（折れ線グラフ。目標があれば破線とラベル）
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.records,
    required this.target,
    required this.periodWord,
  });

  final List<WeightRecord> records;
  final double? target;
  final String periodWord;

  @override
  Widget build(BuildContext context) {
    // 古い順に並べる
    final chronological = records.reversed.toList();
    final labels = chartLabelIndices(chronological.length);
    final points = [
      for (var i = 0; i < chronological.length; i++)
        FcChartPoint(
          chronological[i].weight,
          label: labels.contains(i)
              ? formatMonthDay(chronological[i].recordedAt)
              : null,
        ),
    ];

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              '体重の推移',
              style: AppTextStyles.body(context)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (points.isEmpty)
            Text(
              'この期間の体重の記録はありません。',
              style: AppTextStyles.supplement(context),
            )
          else
            FcLineChart(
              data: points,
              goal: target,
              goalLabel: target == null ? null : '目標 ${formatKg(target!)} kg',
              height: 170,
              semanticLabel:
                  '$periodWordの体重の推移、${formatKg(chronological.first.weight)} kgから${formatKg(chronological.last.weight)} kg',
            ),
        ],
      ),
    );
  }
}

/// 最近の記録（最大 10 件）。行 = 日時 ＋ 記録の出どころ / 右に値
class _RecentRecords extends StatelessWidget {
  const _RecentRecords({required this.records});

  final List<WeightRecord> records;

  static String? _sourceLabel(String source) {
    switch (source) {
      case 'message':
        return 'メッセージから';
      case 'healthkit':
        return 'ヘルスケアから';
      case 'manual':
        return '手入力';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FcRowsCard(
      children: [
        for (final record in records.take(10))
          FcListRow(
            density: FcRowDensity.record,
            title: formatJpDateTime(record.recordedAt),
            caption: [
              _sourceLabel(record.source),
              if (record.notes != null && record.notes!.isNotEmpty) record.notes,
            ].whereType<String>().join(' · ').nullIfEmpty,
            trailing: FcRowValue.text('${formatKg(record.weight)} kg'),
          ),
      ],
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// 読み込み中の上の大きなカード（配置を保つ）
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '読み込み中',
      child: const FcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _StatSkeleton()),
                SizedBox(width: AppSpacing.md),
                Expanded(child: _StatSkeleton()),
                SizedBox(width: AppSpacing.md),
                Expanded(child: _StatSkeleton()),
              ],
            ),
            SizedBox(height: AppSpacing.xxl),
            FcSkeleton.line(width: 180),
            SizedBox(height: AppSpacing.md),
            FcSkeleton.line(width: 220),
          ],
        ),
      ),
    );
  }
}

/// 読み込み中の「体重の推移」カード（配置を保つ）
class _TrendSkeleton extends StatelessWidget {
  const _TrendSkeleton();

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
            FcSkeleton(height: 170, radius: AppRadius.input),
          ],
        ),
      ),
    );
  }
}

class _StatSkeleton extends StatelessWidget {
  const _StatSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FcSkeleton(width: 40, height: 12),
        SizedBox(height: AppSpacing.sm),
        FcSkeleton(width: 64, height: 26, radius: 8),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Previews
// ---------------------------------------------------------------------------

/// 正本 `record-screens.js` のサンプル（9/13 時点・今月）
List<WeightRecord> _sampleRecords() {
  const rows = <(int, int, int, double, String)>[
    (13, 7, 30, 62.4, 'message'),
    (11, 7, 25, 62.3, 'message'),
    (9, 7, 40, 62.2, 'message'),
    (7, 7, 35, 62.1, 'message'),
    (5, 7, 30, 61.7, 'healthkit'),
    (3, 7, 20, 61.8, 'message'),
    (1, 7, 15, 61.6, 'message'),
  ];
  return [
    for (final (day, hour, minute, weight, source) in rows)
      WeightRecord(
        id: 'sample-$day',
        clientId: 'client-1',
        weight: weight,
        recordedAt: DateTime(2026, 9, day, hour, minute),
        source: source,
        createdAt: DateTime(2026, 9, day, hour, minute),
        updatedAt: DateTime(2026, 9, day, hour, minute),
      ),
  ];
}

Client _sampleGoal() => Client(
      clientId: 'client-1',
      name: '佐藤',
      trainerId: 'trainer-1',
      initialWeight: 61.0,
      targetWeight: 65.0,
      createdAt: DateTime(2026, 8, 1),
    );

class _PreviewWeight extends StatelessWidget {
  const _PreviewWeight({
    this.empty = false,
    this.loading = false,
    this.recordsFailed = false,
  });

  final bool empty;
  final bool loading;

  /// 期間の記録だけ読み込めなかった（ほかのカードは出し続ける）
  final bool recordsFailed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final records = empty ? <WeightRecord>[] : _sampleRecords();
    final AsyncValue<List<WeightRecord>> recordsAsync = loading
        ? const AsyncValue.loading()
        : recordsFailed
            ? AsyncValue.error(Exception('preview'), StackTrace.empty)
            : AsyncValue.data(records);
    final AsyncValue<WeightRecord?> latestAsync = loading
        ? const AsyncValue.loading()
        : AsyncValue.data(records.isEmpty ? null : records.first);
    final AsyncValue<Client?> goalAsync = loading
        ? const AsyncValue.loading()
        : AsyncValue.data(empty ? null : _sampleGoal());

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: _WeightScrollView(
          period: PeriodFilter.month,
          onPeriodChanged: (_) {},
          child: _WeightContent(
            period: PeriodFilter.month,
            recordsAsync: recordsAsync,
            latestAsync: latestAsync,
            goalAsync: goalAsync,
            now: DateTime(2026, 9, 13),
            onOpenMessages: empty ? () {} : null,
            onRetryRecords: () {},
            onRetryProfile: () {},
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'WeightRecordScreen - 通常')
Widget previewWeightRecordScreenNormal() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewWeight(),
  );
}

@Preview(name: 'WeightRecordScreen - 記録なし')
Widget previewWeightRecordScreenEmpty() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewWeight(empty: true),
  );
}

@Preview(name: 'WeightRecordScreen - 読込中')
Widget previewWeightRecordScreenLoading() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewWeight(loading: true),
  );
}

@Preview(name: 'WeightRecordScreen - 推移だけ読み込めない')
Widget previewWeightRecordScreenRecordsFailed() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewWeight(recordsFailed: true),
  );
}

@Preview(name: 'WeightRecordScreen - ダーク・文字特大')
Widget previewWeightRecordScreenDarkLarge() {
  return const FcPreviewApp(
    brightness: Brightness.dark,
    textScale: 1.35,
    home: _PreviewWeight(),
  );
}
