import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

class WeightRecordScreen extends ConsumerStatefulWidget {
  const WeightRecordScreen({super.key});

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
    final latestWeightAsync = ref.watch(latestWeightRecordProvider);
    final goalAsync = ref.watch(currentGoalProvider);
    final achievementRateAsync = ref.watch(achievementRateProvider);
    final weightStatsAsync = ref.watch(
      weightStatsProvider(period: _selectedPeriod),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Period Filter
        _buildPeriodFilter(),
        const SizedBox(height: 16),

        // Stats Card
        _buildStatsCard(latestWeightAsync, goalAsync, achievementRateAsync,
            recordsAsync, weightStatsAsync),
        const SizedBox(height: 24),

        // Chart
        _buildChartCard(recordsAsync, goalAsync),
        const SizedBox(height: 24),

        // Records List
        _buildRecordsList(recordsAsync),
      ],
    );
  }

  Widget _buildPeriodFilter() {
    final colors = AppColors.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: PeriodFilter.values
            .where((p) => p != PeriodFilter.today)
            .map((period) {
          final isSelected = period == _selectedPeriod;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(period.label),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedPeriod = period),
              selectedColor: AppColors.primary100,
              checkmarkColor: AppColors.primary600,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary600 : colors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatsCard(
    AsyncValue<WeightRecord?> latestWeightAsync,
    AsyncValue<Client?> goalAsync,
    AsyncValue<double> achievementRateAsync,
    AsyncValue<List<WeightRecord>> recordsAsync,
    AsyncValue<Map<String, double>> weightStatsAsync,
  ) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: latestWeightAsync.when(
        data: (latestWeight) {
          return goalAsync.when(
            data: (goal) {
              final currentWeight = latestWeight?.weight ?? 0.0;
              final targetWeight = goal?.targetWeight ?? 0.0;
              // initial_weightがNULLの場合、記録の最古データをフォールバックに使用
              final oldestRecordWeight =
                  recordsAsync.valueOrNull?.lastOrNull?.weight;
              final initialWeight =
                  goal?.initialWeight ?? oldestRecordWeight ?? currentWeight;
              final vsStart = initialWeight - currentWeight;

              // 減量 or 増量の判定
              final isWeightLossGoal = initialWeight > targetWeight;

              // 残り/超過の計算（減量・増量両対応）
              final difference = (currentWeight - targetWeight).abs();
              final bool isExceeded;
              if (isWeightLossGoal) {
                // 減量: current < target なら超過達成
                isExceeded = currentWeight < targetWeight;
              } else {
                // 増量: current > target なら超過達成
                isExceeded = currentWeight > targetWeight;
              }
              final bool isExactlyAchieved = currentWeight == targetWeight;

              // ラベル決定: 残り / 達成 / 超過
              final String statusLabel;
              if (isExactlyAchieved) {
                statusLabel = '達成';
              } else if (isExceeded) {
                statusLabel = '超過';
              } else {
                statusLabel = '残り';
              }

              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTopStat(
                        '現在',
                        currentWeight.toStringAsFixed(1),
                        'kg',
                      ),
                      Container(width: 1, height: 40, color: colors.border),
                      _buildTopStat(
                        '目標',
                        targetWeight.toStringAsFixed(1),
                        'kg',
                        isAccent: true,
                      ),
                      Container(width: 1, height: 40, color: colors.border),
                      _buildTopStat(
                        statusLabel,
                        difference.toStringAsFixed(1),
                        'kg',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Achievement Rate Progress
                  achievementRateAsync.when(
                    data: (rate) => _buildProgressBar(rate),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildComparisonBox(
                          '開始時比',
                          '${vsStart >= 0 ? "-" : "+"}${vsStart.abs().toStringAsFixed(1)}kg',
                          isPositive: vsStart >= 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildPreviousComparisonBox(recordsAsync),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPeriodStats(weightStatsAsync),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('エラー: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }

  Widget _buildProgressBar(double rate) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '達成率',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
            Text(
              '${rate.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: AppColors.primary600,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: rate / 100,
            backgroundColor: colors.border,
            valueColor: AlwaysStoppedAnimation<Color>(
              rate >= 100 ? AppColors.success : AppColors.primary600,
            ),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(AsyncValue<List<WeightRecord>> recordsAsync,
      AsyncValue<Client?> goalAsync) {
    final colors = AppColors.of(context);
    return Container(
      height: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: recordsAsync.when(
        data: (records) {
          if (records.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.scale, size: 48, color: colors.textHint),
                  const SizedBox(height: 12),
                  Text(
                    '体重記録がありません',
                    style: TextStyle(color: colors.textHint),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '体重を記録しましょう',
                    style: TextStyle(color: colors.textHint, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          // Reverse to show oldest first in chart
          final chartRecords = records.reversed.toList();
          final targetWeight = goalAsync.valueOrNull?.targetWeight;

          // Calculate min/max for Y axis
          final weights = chartRecords.map<double>((r) => r.weight).toList();
          if (targetWeight != null) weights.add(targetWeight);
          final minWeight = weights.reduce((a, b) => a < b ? a : b) - 2;
          final maxWeight = weights.reduce((a, b) => a > b ? a : b) + 2;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '体重推移',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 2,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: colors.border,
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toStringAsFixed(0),
                              style: TextStyle(
                                color: colors.textHint,
                                fontSize: 10,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: (chartRecords.length / 5).ceilToDouble(),
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= chartRecords.length) {
                              return const SizedBox.shrink();
                            }
                            final date = chartRecords[index].recordedAt;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('M/d').format(date),
                                style: TextStyle(
                                  color: colors.textHint,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    minY: minWeight,
                    maxY: maxWeight,
                    lineBarsData: [
                      // Weight line
                      LineChartBarData(
                        spots:
                            chartRecords.asMap().entries.map<FlSpot>((entry) {
                          return FlSpot(
                            entry.key.toDouble(),
                            entry.value.weight,
                          );
                        }).toList(),
                        isCurved: true,
                        color: AppColors.primary600,
                        barWidth: 3,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) {
                            return FlDotCirclePainter(
                              radius: 4,
                              color: Colors.white,
                              strokeWidth: 2,
                              strokeColor: AppColors.primary600,
                            );
                          },
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppColors.primary100.withAlpha(100),
                        ),
                      ),
                      // Target line (if exists)
                      if (targetWeight != null)
                        LineChartBarData(
                          spots: [
                            FlSpot(0, targetWeight),
                            FlSpot(
                              (chartRecords.length - 1).toDouble(),
                              targetWeight,
                            ),
                          ],
                          isCurved: false,
                          color: AppColors.success,
                          barWidth: 2,
                          dashArray: [5, 5],
                          dotData: const FlDotData(show: false),
                        ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map<LineTooltipItem?>((spot) {
                            if (spot.barIndex == 1)
                              return null; // Skip target line
                            final record = chartRecords[spot.x.toInt()];
                            return LineTooltipItem(
                              '${record.weight.toStringAsFixed(1)} kg\n${DateFormat('M/d').format(record.recordedAt)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }

  Widget _buildRecordsList(AsyncValue<List<WeightRecord>> recordsAsync) {
    final colors = AppColors.of(context);
    return recordsAsync.when(
      data: (records) {
        if (records.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近の記録',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...records.take(10).map((record) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.scale,
                          size: 20,
                          color: AppColors.primary600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${record.weight.toStringAsFixed(1)} kg',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: colors.textPrimary,
                              ),
                            ),
                            if (record.notes != null &&
                                record.notes!.isNotEmpty)
                              Text(
                                record.notes!,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        DateFormat('M/d HH:mm').format(record.recordedAt),
                        style: TextStyle(
                          color: colors.textHint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('エラー: $e')),
    );
  }

  Widget _buildTopStat(String label, String value, String unit,
      {bool isAccent = false}) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: colors.textHint,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: isAccent ? AppColors.primary600 : colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: unit,
                style: TextStyle(
                  color: colors.textHint,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviousComparisonBox(
      AsyncValue<List<WeightRecord>> recordsAsync) {
    return recordsAsync.when(
      data: (records) {
        if (records.length < 2) {
          return _buildComparisonBox('前回比', '--', isPositive: true);
        }
        final diff = records[0].weight - records[1].weight;
        final isPositive = diff <= 0;
        return _buildComparisonBox(
          '前回比',
          '${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(1)}kg',
          isPositive: isPositive,
        );
      },
      loading: () => _buildComparisonBox('前回比', '...', isPositive: true),
      error: (_, __) => _buildComparisonBox('前回比', '--', isPositive: true),
    );
  }

  Widget _buildPeriodStats(AsyncValue<Map<String, double>> statsAsync) {
    final colors = AppColors.of(context);
    return statsAsync.when(
      data: (stats) {
        final average = stats['average'] ?? 0.0;
        final min = stats['min'] ?? 0.0;
        final max = stats['max'] ?? 0.0;
        final range = max - min;

        if (average == 0.0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceDim,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '期間統計',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child:
                        _buildMiniStat('平均', '${average.toStringAsFixed(1)}kg'),
                  ),
                  Expanded(
                    child: _buildMiniStat('最高', '${max.toStringAsFixed(1)}kg'),
                  ),
                  Expanded(
                    child: _buildMiniStat('最低', '${min.toStringAsFixed(1)}kg'),
                  ),
                  Expanded(
                    child:
                        _buildMiniStat('変動幅', '${range.toStringAsFixed(1)}kg'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textHint,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonBox(String label, String value,
      {bool isPositive = true}) {
    final color = isPositive ? AppColors.emerald600 : AppColors.rose800;
    final bgColor = isPositive ? AppColors.emerald50 : AppColors.rose100;
    final icon = isPositive ? LucideIcons.arrowDown : LucideIcons.arrowUp;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withAlpha(180),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'WeightRecordScreen - Static Preview with Chart')
Widget previewWeightRecordScreenWithChart() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PreviewWeightRecordScreen(),
          ],
        ),
      ),
    ),
  );
}

class _PreviewWeightRecordScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Mock data
    final now = DateTime.now();
    final mockRecords = List.generate(
      10,
      (index) => WeightRecord(
        id: 'record_$index',
        clientId: 'client_1',
        weight: 70.0 - (index * 0.5), // Declining weight trend
        notes: index % 3 == 0 ? 'Feeling good!' : null,
        recordedAt: now.subtract(Duration(days: index * 3)),
        source: 'manual',
        messageId: null,
        createdAt: now.subtract(Duration(days: index * 3)),
        updatedAt: now.subtract(Duration(days: index * 3)),
      ),
    ).reversed.toList();

    final targetWeight = 65.0;
    final currentWeight = mockRecords.last.weight;
    final initialWeight = mockRecords.first.weight;
    final vsStart = initialWeight - currentWeight;
    final achievementRate =
        ((initialWeight - currentWeight) / (initialWeight - targetWeight) * 100)
            .clamp(0, 100);

    // 減量 or 増量の判定
    final isWeightLossGoal = initialWeight > targetWeight;

    // 残り/超過の計算（減量・増量両対応）
    final difference = (currentWeight - targetWeight).abs();
    final bool isExceeded;
    if (isWeightLossGoal) {
      isExceeded = currentWeight < targetWeight;
    } else {
      isExceeded = currentWeight > targetWeight;
    }
    final bool isExactlyAchieved = currentWeight == targetWeight;

    // ラベル決定
    final String statusLabel;
    if (isExactlyAchieved) {
      statusLabel = '達成';
    } else if (isExceeded) {
      statusLabel = '超過';
    } else {
      statusLabel = '残り';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period Filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: PeriodFilter.values.map((period) {
              final isSelected = period == PeriodFilter.month;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(period.label),
                  selected: isSelected,
                  onSelected: (_) {}, // Preview: no-op
                  selectedColor: AppColors.primary100,
                  checkmarkColor: AppColors.primary600,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.primary600
                        : colors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Stats Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTopStat(
                      context, '現在', currentWeight.toStringAsFixed(1), 'kg'),
                  Container(width: 1, height: 40, color: colors.border),
                  _buildTopStat(
                      context, '目標', targetWeight.toStringAsFixed(1), 'kg',
                      isAccent: true),
                  Container(width: 1, height: 40, color: colors.border),
                  _buildTopStat(
                    context,
                    statusLabel,
                    difference.toStringAsFixed(1),
                    'kg',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Achievement Rate Progress
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '達成率',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                      Text(
                        '${achievementRate.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: AppColors.primary600,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: achievementRate / 100,
                      backgroundColor: colors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary600),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildComparisonBox(
                      '開始時比',
                      '${vsStart >= 0 ? "-" : "+"}${vsStart.abs().toStringAsFixed(1)}kg',
                      isPositive: vsStart >= 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildComparisonBox(
                      '前回比',
                      '-0.5kg',
                      isPositive: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '期間統計',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _buildMiniStat(context, '平均', '67.3kg')),
                        Expanded(
                            child: _buildMiniStat(context, '最高', '70.0kg')),
                        Expanded(
                            child: _buildMiniStat(context, '最低', '65.5kg')),
                        Expanded(
                            child: _buildMiniStat(context, '変動幅', '4.5kg')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Chart
        Container(
          height: 280,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.border),
          ),
          child: _buildChart(context, mockRecords, targetWeight),
        ),
        const SizedBox(height: 24),

        // Records List
        Text(
          '最近の記録',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...mockRecords.reversed.take(5).map((record) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      LucideIcons.scale,
                      size: 20,
                      color: AppColors.primary600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${record.weight.toStringAsFixed(1)} kg',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (record.notes != null && record.notes!.isNotEmpty)
                          Text(
                            record.notes!,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('M/d HH:mm').format(record.recordedAt),
                    style: TextStyle(
                      color: colors.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildChart(
      BuildContext context, List<WeightRecord> records, double targetWeight) {
    final colors = AppColors.of(context);
    final weights = records.map<double>((r) => r.weight).toList();
    weights.add(targetWeight);
    final minWeight = weights.reduce((a, b) => a < b ? a : b) - 2;
    final maxWeight = weights.reduce((a, b) => a > b ? a : b) + 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '体重推移',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 2,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: colors.border,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toStringAsFixed(0),
                        style: TextStyle(
                          color: colors.textHint,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: (records.length / 5).ceilToDouble(),
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= records.length) {
                        return const SizedBox.shrink();
                      }
                      final date = records[index].recordedAt;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          DateFormat('M/d').format(date),
                          style: TextStyle(
                            color: colors.textHint,
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: minWeight,
              maxY: maxWeight,
              lineBarsData: [
                // Weight line
                LineChartBarData(
                  spots: records.asMap().entries.map<FlSpot>((entry) {
                    return FlSpot(
                      entry.key.toDouble(),
                      entry.value.weight,
                    );
                  }).toList(),
                  isCurved: true,
                  color: AppColors.primary600,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: Colors.white,
                        strokeWidth: 2,
                        strokeColor: AppColors.primary600,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.primary100.withAlpha(100),
                  ),
                ),
                // Target line
                LineChartBarData(
                  spots: [
                    FlSpot(0, targetWeight),
                    FlSpot((records.length - 1).toDouble(), targetWeight),
                  ],
                  isCurved: false,
                  color: AppColors.success,
                  barWidth: 2,
                  dashArray: [5, 5],
                  dotData: const FlDotData(show: false),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map<LineTooltipItem?>((spot) {
                      if (spot.barIndex == 1) return null; // Skip target line
                      final record = records[spot.x.toInt()];
                      return LineTooltipItem(
                        '${record.weight.toStringAsFixed(1)} kg\n${DateFormat('M/d').format(record.recordedAt)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopStat(
      BuildContext context, String label, String value, String unit,
      {bool isAccent = false}) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: colors.textHint,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: isAccent ? AppColors.primary600 : colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: unit,
                style: TextStyle(
                  color: colors.textHint,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(BuildContext context, String label, String value) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textHint,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonBox(String label, String value,
      {bool isPositive = true}) {
    final color = isPositive ? AppColors.emerald600 : AppColors.rose800;
    final bgColor = isPositive ? AppColors.emerald50 : AppColors.rose100;
    final icon = isPositive ? LucideIcons.arrowDown : LucideIcons.arrowUp;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withAlpha(180),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
