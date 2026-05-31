import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/widgets/nutrition_trend_chart.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/widgets/period_filter_chips.dart';
import 'package:fit_connect_mobile/features/records_overview/providers/nutrition_trend_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

/// 記録画面「サマリ」タブ本体。
///
/// 体重 + 摂取カロリー + PFC の日次トレンドを期間フィルタで切り替え表示する。
class RecordsOverviewScreen extends ConsumerStatefulWidget {
  const RecordsOverviewScreen({super.key});

  @override
  ConsumerState<RecordsOverviewScreen> createState() =>
      _RecordsOverviewScreenState();
}

class _RecordsOverviewScreenState extends ConsumerState<RecordsOverviewScreen> {
  PeriodFilter _period = PeriodFilter.month;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    final trendAsync = ref.watch(nutritionTrendProvider(period: _period));
    final targetWeight = ref.watch(currentGoalProvider).valueOrNull?.targetWeight;

    return Scaffold(
      backgroundColor: colors.surfaceDim,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(colors: colors),
              const SizedBox(height: 16),
              PeriodFilterChips(
                selected: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
              const SizedBox(height: 16),
              _ChartCard(
                child: trendAsync.when(
                  loading: () => const _ChartSkeleton(),
                  error: (e, _) => _ChartError(message: e.toString()),
                  data: (data) {
                    final hasAny = data.any((d) => d.hasAnyRecord);
                    if (!hasAny) {
                      return const NutritionTrendChart(data: []);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _AxisTitles(),
                        NutritionTrendChart(
                            data: data, targetWeight: targetWeight),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const _Legend(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AppColorsExtension colors;
  const _Header({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '栄養トレンド',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '体重・摂取カロリー・PFC',
          style: TextStyle(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final Widget child;
  const _ChartCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.slate400,
          ),
        ),
      ),
    );
  }
}

class _ChartError extends StatelessWidget {
  final String message;
  const _ChartError({required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '読み込みに失敗しました\n$message',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _AxisTitles extends StatelessWidget {
  const _AxisTitles();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左: 摂取 kcal（slate）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 11,
                decoration: BoxDecoration(
                  color: AppColors.slate400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '摂取 kcal',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate500,
                ),
              ),
            ],
          ),
          // 右: 体重 kg（青）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '体重 kg',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 3,
                height: 11,
                decoration: BoxDecoration(
                  color: AppColors.primary600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: const [
        _LegendItem(color: AppColors.pfcProtein, label: 'タンパク質'),
        _LegendItem(color: AppColors.pfcFat, label: '脂質'),
        _LegendItem(color: AppColors.pfcCarbs, label: '炭水化物'),
        _LegendItem(color: AppColors.primary600, label: '体重', isLine: true),
        _LegendItem(color: AppColors.success, label: '目標', isLine: true),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool isLine;

  const _LegendItem({
    required this.color,
    required this.label,
    this.isLine = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: isLine ? 3 : 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(isLine ? 1.5 : 3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.slate600,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Previews
// ---------------------------------------------------------------------------

/// Riverpod を使うため、静的プレビュー用にコンテンツを再構成したヘルパー。
class _PreviewRecordsOverviewContent extends StatelessWidget {
  final List<DailyNutritionStat> data;
  final double? targetWeight;
  const _PreviewRecordsOverviewContent({required this.data, this.targetWeight});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Scaffold(
      backgroundColor: colors.surfaceDim,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(colors: colors),
              const SizedBox(height: 16),
              PeriodFilterChips(
                selected: PeriodFilter.month,
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),
              _ChartCard(
                child: data.isEmpty
                    ? NutritionTrendChart(
                        data: data, targetWeight: targetWeight)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _AxisTitles(),
                          NutritionTrendChart(
                              data: data, targetWeight: targetWeight),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              const _Legend(),
            ],
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'RecordsOverviewScreen - With Data')
Widget previewRecordsOverviewScreenWithData() {
  final today = DateTime.now();
  final base = DateTime(today.year, today.month, today.day);
  final sample = [
    for (var i = 13; i >= 0; i--)
      DailyNutritionStat(
        date: base.subtract(Duration(days: i)),
        weight: i.isEven ? 65.0 + (i / 8) : null,
        calories: i == 5 ? 0 : (1700 + (i * 30)).toDouble(),
        protein: i == 5 ? 0 : (100 + (i * 2)).toDouble(),
        fat: i == 5 ? 0 : (50 + i).toDouble(),
        carbs: i == 5 ? 0 : (180 + (i * 3)).toDouble(),
      ),
  ];
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _PreviewRecordsOverviewContent(data: sample, targetWeight: 64.0),
  );
}

@Preview(name: 'RecordsOverviewScreen - Empty')
Widget previewRecordsOverviewScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewRecordsOverviewContent(data: []),
  );
}
