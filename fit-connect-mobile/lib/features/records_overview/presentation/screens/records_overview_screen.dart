import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/widgets/overview_summary.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/widgets/period_filter_chips.dart';
import 'package:fit_connect_mobile/features/records_overview/providers/nutrition_trend_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/widgets/weight_format.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 記録画面「サマリ」タブ本体。
///
/// 体重・摂取カロリー・PFC を、期間（今週 / 今月 / 3ヶ月）で切り替えて並べる。
/// カロリーと PFC は食事の写真と内容からの**推定値**なので、「推定」と明記する。
/// 日次の集計は `nutritionTrendProvider` のまま。
class RecordsOverviewScreen extends ConsumerStatefulWidget {
  /// 記録がまだ無いときの「メッセージから記録する」を押したとき（メッセージタブへ移る）。
  /// null なら入口は出さず、文言だけ
  final VoidCallback? onOpenMessages;

  const RecordsOverviewScreen({super.key, this.onOpenMessages});

  @override
  ConsumerState<RecordsOverviewScreen> createState() =>
      _RecordsOverviewScreenState();
}

class _RecordsOverviewScreenState extends ConsumerState<RecordsOverviewScreen> {
  PeriodFilter _period = PeriodFilter.month;

  /// 栄養トレンドは体重と食事の記録（[weightRecordsProvider] / [mealRecordsProvider]）を待つので、
  /// どちらが失敗していても読み直せるよう、依存先も一緒に無効化する
  /// （食事側の失敗がキャッシュされたままだと、トレンドだけ読み直しても同じ失敗が返る）
  void _retry() {
    ref.invalidate(weightRecordsProvider(period: _period));
    ref.invalidate(mealRecordsProvider(period: _period));
    ref.invalidate(nutritionTrendProvider(period: _period));
  }

  @override
  Widget build(BuildContext context) {
    final trendAsync = ref.watch(nutritionTrendProvider(period: _period));
    final recordsAsync = ref.watch(weightRecordsProvider(period: _period));
    final targetWeight =
        ref.watch(currentGoalProvider).valueOrNull?.targetWeight;

    final Widget body;
    if (trendAsync.hasValue) {
      final summary = OverviewSummary.from(
        trendAsync.requireValue,
        today: DateTime.now(),
      );
      final records = recordsAsync.valueOrNull ?? const [];
      body = _OverviewContent(
        summary: summary,
        latestWeight: records.isEmpty ? null : records.first.weight,
        latestWeightAt: records.isEmpty ? null : records.first.recordedAt,
        targetWeight: targetWeight,
        onOpenMessages: widget.onOpenMessages,
      );
    } else if (trendAsync.hasError) {
      body = FcStateMessage.error(
        title: '読み込めませんでした',
        message: '通信の状態を確認して、もう一度お試しください。',
        actionLabel: '再試行',
        onAction: _retry,
      );
    } else {
      body = const _OverviewSkeleton();
    }

    return _OverviewScrollView(
      period: _period,
      onPeriodChanged: (p) => setState(() => _period = p),
      child: body,
    );
  }
}

/// 期間セグメント ＋ 本文を縦に並べるスクロール領域。
///
/// 左右の余白は自分で持つ。下はナビぶん（`MediaQuery.padding.bottom`）を空ける。
class _OverviewScrollView extends StatelessWidget {
  const _OverviewScrollView({
    required this.period,
    required this.onPeriodChanged,
    required this.child,
  });

  final PeriodFilter period;
  final ValueChanged<PeriodFilter> onPeriodChanged;
  final Widget child;

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
        PeriodFilterChips(selected: period, onChanged: onPeriodChanged),
        const SizedBox(height: AppSpacing.cardGap),
        child,
      ],
    );
  }
}

/// サマリの本文（体重 → 摂取カロリー → PFC → 注記）。記録が 1 件もなければ空の状態。
class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.summary,
    required this.latestWeight,
    required this.latestWeightAt,
    required this.targetWeight,
    this.onOpenMessages,
  });

  final OverviewSummary summary;

  /// 記録がまだ無いときの「メッセージから記録する」。null なら出さない
  final VoidCallback? onOpenMessages;

  /// 期間内で最新の体重（kg）と記録日時。無ければ日ごとの最後の値で代える
  final double? latestWeight;
  final DateTime? latestWeightAt;
  final double? targetWeight;

  @override
  Widget build(BuildContext context) {
    if (!summary.hasAnyRecord) {
      return FcStateMessage.empty(
        title: 'まだ記録がありません',
        message: 'この期間の体重・食事の記録はありません。メッセージ画面で記録すると、ここに表示されます。',
        actionLabel: onOpenMessages == null ? null : 'メッセージから記録する',
        actionIcon: LucideIcons.messageCircle,
        onAction: onOpenMessages,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeightCard(
          summary: summary,
          latestWeight: latestWeight,
          latestWeightAt: latestWeightAt,
          targetWeight: targetWeight,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _CalorieCard(summary: summary),
        const SizedBox(height: AppSpacing.cardGap),
        _PfcCard(summary: summary),
        const SizedBox(height: AppSpacing.cardGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            'カロリーとPFCは、食事の写真と内容からの推定値です。',
            style: AppTextStyles.caption(context),
          ),
        ),
      ],
    );
  }
}

/// 数値の下の補足（正本 `rdText.meta`: 13・textSecondary・上 4）
class _Meta extends StatelessWidget {
  const _Meta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(text, style: AppTextStyles.supplement(context)),
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({
    required this.summary,
    required this.latestWeight,
    required this.latestWeightAt,
    required this.targetWeight,
  });

  final OverviewSummary summary;
  final double? latestWeight;
  final DateTime? latestWeightAt;
  final double? targetWeight;

  @override
  Widget build(BuildContext context) {
    final days = summary.weightDays;
    final range = formatJpRange(summary.start, summary.end);

    if (days.isEmpty) {
      return FcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcCardHead(
              icon: LucideIcons.scale,
              label: '体重',
              note: range,
            ),
            Text(
              'この期間の体重の記録はありません。',
              style: AppTextStyles.supplement(context),
            ),
          ],
        ),
      );
    }

    final current = latestWeight ?? days.last.weight!;
    // 時刻のある記録は日時、日ごとの値で代えたときは日付だけ
    final recordedAt = latestWeightAt;
    final metaParts = [
      recordedAt == null
          ? formatJpDate(days.last.date)
          : formatJpDateTime(recordedAt),
      if (targetWeight != null) '目標 ${formatKg(targetWeight!)} kg',
    ];

    final labels = chartLabelIndices(days.length);
    final points = [
      for (var i = 0; i < days.length; i++)
        FcChartPoint(
          days[i].weight!,
          label: labels.contains(i) ? formatMonthDay(days[i].date) : null,
        ),
    ];

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FcCardHead(icon: LucideIcons.scale, label: '体重', note: range),
          FcNum(value: formatKg(current), unit: 'kg'),
          _Meta(metaParts.join(' · ')),
          const SizedBox(height: 14),
          FcLineChart(
            data: points,
            goal: targetWeight,
            goalLabel:
                targetWeight == null ? null : '目標 ${formatKg(targetWeight!)} kg',
            height: 150,
            semanticLabel:
                '$rangeの体重の推移、${formatKg(days.first.weight!)} kgから${formatKg(days.last.weight!)} kg',
          ),
        ],
      ),
    );
  }
}

class _CalorieCard extends StatelessWidget {
  const _CalorieCard({required this.summary});

  final OverviewSummary summary;

  static final NumberFormat _kcal = NumberFormat('#,##0');

  static String _monthDay(DateTime d) => '${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    final average = summary.averageCalories;

    if (average == null) {
      return FcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FcCardHead(
              icon: LucideIcons.utensils,
              label: '摂取カロリー',
              note: '推定',
            ),
            Text(
              'この期間の食事の記録はありません。',
              style: AppTextStyles.supplement(context),
            ),
          ],
        ),
      );
    }

    final range = summary.averageStart == summary.averageEnd
        ? _monthDay(summary.averageStart)
        : '${_monthDay(summary.averageStart)}〜${_monthDay(summary.averageEnd)}';

    final maxValue = summary.bars
        .map((b) => b.calories ?? 0)
        .fold<double>(0, (a, b) => math.max(a, b));
    // 棒の上限は最大値に少し余裕を足した 100 の倍数（正本は 2400 kcal）
    final barMax = math.max(1000, (maxValue * 1.1 / 100).ceil() * 100).toDouble();

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FcCardHead(
            icon: LucideIcons.utensils,
            label: '摂取カロリー',
            note: '推定',
          ),
          FcNum(value: _kcal.format(average.round()), unit: 'kcal'),
          _Meta('1日平均 · $rangeのうち記録した${summary.calorieDayCount}日'),
          const SizedBox(height: AppSpacing.lg),
          FcBars(
            max: barMax,
            height: 84,
            showValues: false,
            // 1 週間ごとの棒は本数が多くなるので間を詰める
            gap: summary.weeklyBars ? 2 : 4,
            semanticLabel: summary.weeklyBars
                ? '1週間ごとの摂取カロリー（1日平均）'
                : '1日ごとの摂取カロリー',
            items: [
              for (final bar in summary.bars)
                FcBarItem(
                  value: bar.calories,
                  text: bar.calories == null
                      ? ''
                      : '${_kcal.format(bar.calories!.round())} kcal',
                  highlighted: bar.highlighted,
                  label: bar.label,
                ),
            ],
          ),
          if (summary.weeklyBars) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '棒は1週間ごとの、記録した日の1日平均です。',
              style: AppTextStyles.caption(context),
            ),
          ],
        ],
      ),
    );
  }
}

/// PFC バランス（1 日平均）。アイコンのない見出し（正本 `CardHead` の icon 省略）
class _PfcCard extends StatelessWidget {
  const _PfcCard({required this.summary});

  final OverviewSummary summary;

  static String? _grams(double? value) =>
      value == null ? null : '${value.round()} g';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final headStyle = AppTextStyles.label(context)
        .copyWith(color: colors.accent, height: 1.5);

    return FcCard(
      // 正本: 上 16・下 2（行の縦余白 14 が見出しとの間・下の余白になる）
      paddingOverride: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        AppSpacing.lg,
        AppSpacing.cardPadding,
        2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('PFCバランス（1日平均）', style: headStyle),
                ),
              ),
              const SizedBox(width: 6),
              Text('推定', style: AppTextStyles.supplement(context)),
            ],
          ),
          FcStatList(
            items: [
              FcStatItem(
                label: 'たんぱく質',
                description: summary.pfcDayCount == 0
                    ? null
                    : '記録した${summary.pfcDayCount}日の平均',
                value: _grams(summary.averageProtein),
              ),
              FcStatItem(label: '脂質', value: _grams(summary.averageFat)),
              FcStatItem(label: '炭水化物', value: _grams(summary.averageCarbs)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 読み込み中（配置を保つ）
class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '読み込み中',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 体重
          FcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FcSkeleton.line(width: 96),
                SizedBox(height: AppSpacing.md),
                FcSkeleton(width: 132, height: 36, radius: 8),
                SizedBox(height: AppSpacing.sm),
                FcSkeleton.line(width: 200),
                SizedBox(height: 14),
                FcSkeleton(height: 150, radius: AppRadius.input),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.cardGap),
          // 摂取カロリー
          FcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FcSkeleton.line(width: 96),
                SizedBox(height: AppSpacing.md),
                FcSkeleton(width: 132, height: 36, radius: 8),
                SizedBox(height: AppSpacing.sm),
                FcSkeleton.line(width: 220),
                SizedBox(height: AppSpacing.lg),
                FcSkeleton(height: 84, radius: AppRadius.input),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.cardGap),
          // PFC
          FcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FcSkeleton.line(width: 160),
                SizedBox(height: AppSpacing.lg),
                FcSkeleton.line(),
                SizedBox(height: AppSpacing.xl),
                FcSkeleton.line(),
                SizedBox(height: AppSpacing.xl),
                FcSkeleton.line(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Previews
// ---------------------------------------------------------------------------

/// 正本 `record-screens.js` のサンプル（9/13 時点の今月）
OverviewSummary _sampleSummary() {
  const weights = <double?>[
    61.6, 61.8, null, 61.7, null, 62.1, null, 62.2, null, null, 62.3, null, 62.4
  ];
  const kcals = <double>[
    1920, 2050, 0, 2010, 1990, 0, 2100, 1950, 1870, 1980, 2040, 1960, 1160
  ];
  final days = [
    for (var i = 0; i < 13; i++)
      DailyNutritionStat(
        date: DateTime(2026, 9, i + 1),
        weight: weights[i],
        calories: kcals[i],
        protein: kcals[i] == 0 ? 0 : 95,
        fat: kcals[i] == 0 ? 0 : 64,
        carbs: kcals[i] == 0 ? 0 : 250,
      ),
  ];
  return OverviewSummary.from(days, today: DateTime(2026, 9, 13));
}

class _PreviewOverview extends StatelessWidget {
  const _PreviewOverview({this.empty = false, this.loading = false});

  final bool empty;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final Widget body;
    if (loading) {
      body = const _OverviewSkeleton();
    } else if (empty) {
      body = _OverviewContent(
        summary: OverviewSummary.from(
          [for (var i = 0; i < 13; i++) DailyNutritionStat(date: DateTime(2026, 9, i + 1))],
          today: DateTime(2026, 9, 13),
        ),
        latestWeight: null,
        latestWeightAt: null,
        targetWeight: null,
        onOpenMessages: () {},
      );
    } else {
      body = _OverviewContent(
        summary: _sampleSummary(),
        latestWeight: 62.4,
        latestWeightAt: DateTime(2026, 9, 13, 7, 30),
        targetWeight: 65,
      );
    }
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: _OverviewScrollView(
          period: PeriodFilter.month,
          onPeriodChanged: (_) {},
          child: body,
        ),
      ),
    );
  }
}

@Preview(name: 'RecordsOverviewScreen - 通常')
Widget previewRecordsOverviewScreenNormal() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewOverview(),
  );
}

@Preview(name: 'RecordsOverviewScreen - 記録なし')
Widget previewRecordsOverviewScreenEmpty() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewOverview(empty: true),
  );
}

@Preview(name: 'RecordsOverviewScreen - 読込中')
Widget previewRecordsOverviewScreenLoading() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewOverview(loading: true),
  );
}

@Preview(name: 'RecordsOverviewScreen - ダーク・文字特大')
Widget previewRecordsOverviewScreenDarkLarge() {
  return const FcPreviewApp(
    brightness: Brightness.dark,
    textScale: 1.35,
    home: _PreviewOverview(),
  );
}
