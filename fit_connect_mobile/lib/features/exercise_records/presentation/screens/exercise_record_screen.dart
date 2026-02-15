import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/exercise_records/models/exercise_record_model.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_week_calendar.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_month_calendar.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

class ExerciseRecordScreen extends ConsumerStatefulWidget {
  const ExerciseRecordScreen({super.key});

  @override
  ConsumerState<ExerciseRecordScreen> createState() =>
      _ExerciseRecordScreenState();
}

class _ExerciseRecordScreenState extends ConsumerState<ExerciseRecordScreen> {
  PeriodFilter _selectedPeriod = PeriodFilter.week;
  String? _selectedType; // null = all, 'strength_training', 'cardio'

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(
      exerciseRecordsProvider(
        period: _selectedPeriod,
        exerciseType: _selectedType,
      ),
    );
    final typeCountsAsync = ref.watch(
      exerciseTypeCountsProvider(period: _selectedPeriod),
    );
    final caloriesAsync = ref.watch(
      exerciseTotalCaloriesProvider(period: _selectedPeriod),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Period Filter
        _buildPeriodFilter(),
        const SizedBox(height: 16),

        // Exercise Type Filter
        _buildTypeFilter(),
        const SizedBox(height: 24),

        // Summary Card
        _buildSummaryCard(recordsAsync, typeCountsAsync, caloriesAsync),
        const SizedBox(height: 16),

        // Calendar - show week calendar for week, month calendar for month
        if (_selectedPeriod == PeriodFilter.week) ...[
          const ExerciseWeekCalendar(),
          const SizedBox(height: 16),
        ],
        if (_selectedPeriod == PeriodFilter.month) ...[
          const ExerciseMonthCalendar(),
          const SizedBox(height: 16),
        ],

        // Exercise Records List
        _buildRecordsList(recordsAsync),
      ],
    );
  }

  Widget _buildPeriodFilter() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Row(
        children: PeriodFilter.values.map((period) {
          final isActive = period == _selectedPeriod;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriod = period),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.indigo600 : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.indigo600.withAlpha(77),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    period.shortLabel,
                    style: TextStyle(
                      color: isActive ? Colors.white : AppColors.slate400,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTypeFilter() {
    final types = [
      (null, 'すべて', LucideIcons.layoutGrid),
      ('strength_training', '筋トレ', LucideIcons.dumbbell),
      ('cardio', '有酸素', LucideIcons.heart),
    ];

    return Row(
      children: types.map((type) {
        final isActive = _selectedType == type.$1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: type.$1 == null ? 0 : 8,
            ),
            child: GestureDetector(
              onTap: () => setState(() => _selectedType = type.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.indigo50 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive ? AppColors.indigo100 : AppColors.slate200,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      type.$3,
                      size: 16,
                      color:
                          isActive ? AppColors.indigo600 : AppColors.slate400,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type.$2,
                      style: TextStyle(
                        color:
                            isActive ? AppColors.indigo600 : AppColors.slate500,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryCard(
    AsyncValue<List<ExerciseRecord>> recordsAsync,
    AsyncValue<Map<String, int>> typeCountsAsync,
    AsyncValue<double> caloriesAsync,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.indigo50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.indigo100),
      ),
      child: typeCountsAsync.when(
        data: (typeCounts) {
          final total = typeCounts.values.fold<int>(0, (sum, v) => sum + v);
          final strength = typeCounts['strength_training'] ?? 0;
          final cardio = typeCounts['cardio'] ?? 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedPeriod == PeriodFilter.week
                    ? "📊 今週のサマリー"
                    : "📊 ${_selectedPeriod.label}のサマリー",
                style: const TextStyle(
                  color: AppColors.slate800,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child:
                          _buildSummaryStat('合計', total.toString(), '📊')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _buildSummaryStat(
                          '筋トレ', strength.toString(), '🏋️')),
                  const SizedBox(width: 8),
                  Expanded(
                      child:
                          _buildSummaryStat('有酸素', cardio.toString(), '🏃')),
                ],
              ),
              const SizedBox(height: 12),
              // Calories Row
              caloriesAsync.when(
                data: (calories) => _buildCaloriesRow(calories),
                loading: () => _buildCaloriesRow(null),
                error: (_, __) => _buildCaloriesRow(null),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildCaloriesRow(double? calories) {
    String displayValue;
    if (calories == null) {
      displayValue = '-- kcal';
    } else if (calories == 0) {
      displayValue = '-- kcal';
    } else {
      final formatter = NumberFormat('#,###');
      displayValue = '${formatter.format(calories.round())} kcal';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(153),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          const Text(
            '🔥',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          const Text(
            '消費カロリー',
            style: TextStyle(
              color: AppColors.slate600,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            displayValue,
            style: const TextStyle(
              color: AppColors.indigo600,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, String icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(153),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate500,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.slate800,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList(AsyncValue<List<ExerciseRecord>> recordsAsync) {
    return recordsAsync.when(
      data: (records) {
        if (records.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.dumbbell,
                      size: 48, color: AppColors.slate300),
                  const SizedBox(height: 12),
                  const Text(
                    '運動記録がありません',
                    style: TextStyle(color: AppColors.slate400),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '運動を記録しましょう！',
                    style: TextStyle(color: AppColors.slate300, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        // Group records by date
        final groupedRecords = _groupRecordsByDate(records);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: groupedRecords.entries.map((entry) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Header
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    _formatDateHeader(entry.key),
                    style: const TextStyle(
                      color: AppColors.slate800,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.slate100),
                const SizedBox(height: 16),
                // Exercise Cards
                ...entry.value.map((record) => _buildExerciseCard(record)),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Map<DateTime, List<ExerciseRecord>> _groupRecordsByDate(
      List<ExerciseRecord> records) {
    final Map<DateTime, List<ExerciseRecord>> grouped = {};
    for (final record in records) {
      final date = DateTime(
        record.recordedAt.year,
        record.recordedAt.month,
        record.recordedAt.day,
      );
      grouped.putIfAbsent(date, () => []);
      grouped[date]!.add(record);
    }
    return grouped;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return '今日';
    } else if (date == yesterday) {
      return '昨日';
    } else {
      return '${date.month}/${date.day}（${_weekdayLabel(date.weekday)}）';
    }
  }

  String _weekdayLabel(int weekday) {
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return labels[weekday - 1];
  }

  Widget _buildExerciseCard(ExerciseRecord record) {
    final isStrength = record.exerciseType == 'strength_training';
    final color = isStrength ? AppColors.purple500 : AppColors.orange500;
    final bg = isStrength ? AppColors.purple50 : AppColors.orange50;
    final icon = isStrength ? '🏋️' : '🏃';
    final typeLabel = _getExerciseTypeLabel(record.exerciseType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          color: color,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(LucideIcons.clock,
                        size: 12, color: AppColors.slate400),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(record.recordedAt),
                      style: const TextStyle(
                          color: AppColors.slate400, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  record.memo ?? typeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate800,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (record.duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${record.duration}分',
                    style: const TextStyle(
                        color: AppColors.slate500, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getExerciseTypeLabel(String type) {
    switch (type) {
      case 'strength_training':
        return '筋トレ';
      case 'cardio':
        return '有酸素運動';
      case 'walking':
        return 'ウォーキング';
      case 'running':
        return 'ランニング';
      case 'cycling':
        return 'サイクリング';
      case 'swimming':
        return '水泳';
      case 'yoga':
        return 'ヨガ';
      case 'pilates':
        return 'ピラティス';
      default:
        return 'その他';
    }
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'ExerciseRecordScreen - Static Preview')
Widget previewExerciseRecordScreenStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period Filter Preview
            _PreviewPeriodFilter(),
            const SizedBox(height: 16),

            // Type Filter Preview
            _PreviewTypeFilter(),
            const SizedBox(height: 24),

            // Summary Card Preview
            _PreviewSummaryCard(),
            const SizedBox(height: 16),

            // Week Calendar Preview
            _PreviewWeekCalendar(),
            const SizedBox(height: 16),

            // Records List Preview
            _PreviewRecordsList(),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'ExerciseRecordScreen - Empty State')
Widget previewExerciseRecordScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period Filter Preview
            _PreviewPeriodFilter(),
            const SizedBox(height: 16),

            // Type Filter Preview
            _PreviewTypeFilter(),
            const SizedBox(height: 24),

            // Empty Summary Card
            _PreviewSummaryCardEmpty(),
            const SizedBox(height: 24),

            // Empty State
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.dumbbell,
                        size: 48, color: AppColors.slate300),
                    const SizedBox(height: 12),
                    const Text(
                      '運動記録がありません',
                      style: TextStyle(color: AppColors.slate400),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Preview helper widgets
class _PreviewPeriodFilter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Row(
        children:
            ['今日', '週', '月', '3ヶ月', '全期間'].asMap().entries.map((e) {
          final isActive = e.key == 1; // Week is active
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? AppColors.indigo600 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  e.value,
                  style: TextStyle(
                    color: isActive ? Colors.white : AppColors.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PreviewTypeFilter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final types = [
      ('すべて', LucideIcons.layoutGrid, true),
      ('筋トレ', LucideIcons.dumbbell, false),
      ('有酸素', LucideIcons.heart, false),
    ];

    return Row(
      children: types.asMap().entries.map((entry) {
        final type = entry.value;
        final isActive = type.$3;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: entry.key == 0 ? 0 : 8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isActive ? AppColors.indigo50 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? AppColors.indigo100 : AppColors.slate200,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type.$2,
                    size: 16,
                    color: isActive ? AppColors.indigo600 : AppColors.slate400,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    type.$1,
                    style: TextStyle(
                      color:
                          isActive ? AppColors.indigo600 : AppColors.slate500,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PreviewSummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.indigo50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.indigo100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "📊 今週のサマリー",
            style: TextStyle(
              color: AppColors.slate800,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStat('合計', '5', '📊')),
              const SizedBox(width: 8),
              Expanded(child: _buildStat('筋トレ', '3', '🏋️')),
              const SizedBox(width: 8),
              Expanded(child: _buildStat('有酸素', '2', '🏃')),
            ],
          ),
          const SizedBox(height: 12),
          // Calories Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(153),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white),
            ),
            child: const Row(
              children: [
                Text(
                  '🔥',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(width: 8),
                Text(
                  '消費カロリー',
                  style: TextStyle(
                    color: AppColors.slate600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Spacer(),
                Text(
                  '1,150 kcal',
                  style: TextStyle(
                    color: AppColors.indigo600,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, String icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(153),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate500,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.slate800,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSummaryCardEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.indigo50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.indigo100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "📊 今週のサマリー",
            style: TextStyle(
              color: AppColors.slate800,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _PreviewSummaryCard()._buildStat('合計', '0', '📊')),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      _PreviewSummaryCard()._buildStat('筋トレ', '0', '🏋️')),
              const SizedBox(width: 8),
              Expanded(
                  child: _PreviewSummaryCard()._buildStat('有酸素', '0', '🏃')),
            ],
          ),
          const SizedBox(height: 12),
          // Calories Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(153),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white),
            ),
            child: const Row(
              children: [
                Text(
                  '🔥',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(width: 8),
                Text(
                  '消費カロリー',
                  style: TextStyle(
                    color: AppColors.slate600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Spacer(),
                Text(
                  '-- kcal',
                  style: TextStyle(
                    color: AppColors.indigo600,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRecordsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '今日',
          style: TextStyle(
            color: AppColors.slate800,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Divider(height: 24, color: AppColors.slate100),
        ..._mockExerciseRecords.map((record) => _buildExerciseCard(record)),
      ],
    );
  }

  Widget _buildExerciseCard(ExerciseRecord record) {
    final isStrength = record.exerciseType == 'strength_training';
    final color = isStrength ? AppColors.purple500 : AppColors.orange500;
    final bg = isStrength ? AppColors.purple50 : AppColors.orange50;
    final icon = isStrength ? '🏋️' : '🏃';
    final typeLabel = isStrength ? '筋トレ' : '有酸素運動';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          color: color,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(LucideIcons.clock,
                        size: 12, color: AppColors.slate400),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(record.recordedAt),
                      style: const TextStyle(
                          color: AppColors.slate400, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  record.memo ?? typeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate800,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (record.duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${record.duration}分',
                    style: const TextStyle(
                        color: AppColors.slate500, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewWeekCalendar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysFromMonday = (today.weekday - 1) % 7;
    final startOfWeek = today.subtract(Duration(days: daysFromMonday));

    // Mock data
    final mockExerciseData = <DateTime, List<String>>{};
    mockExerciseData[startOfWeek] = ['strength_training'];
    mockExerciseData[startOfWeek.add(const Duration(days: 2))] = [
      'strength_training'
    ];
    mockExerciseData[startOfWeek.add(const Duration(days: 3))] = ['cardio'];
    mockExerciseData[startOfWeek.add(const Duration(days: 5))] = [
      'strength_training'
    ];

    const dayLabels = ['月', '火', '水', '木', '金', '土', '日'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('M月').format(startOfWeek)} ${DateFormat('yyyy').format(today)}（週間）',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.slate800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(7, (index) {
              final date = startOfWeek.add(Duration(days: index));
              final exerciseTypes = mockExerciseData[date] ?? [];
              final isToday = date == today;
              final isFuture = date.isAfter(today);
              final hasRecord = exerciseTypes.isNotEmpty;
              final backgroundColor =
                  hasRecord ? AppColors.indigo50 : AppColors.slate50;

              String? icon;
              if (exerciseTypes.contains('strength_training')) {
                icon = '🏋️';
              } else if (exerciseTypes.any((type) =>
                  type == 'cardio' ||
                  type == 'running' ||
                  type == 'walking' ||
                  type == 'cycling')) {
                icon = '🏃';
              }

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(
                  children: [
                    Text(
                      dayLabels[index],
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.slate400),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 44,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isFuture ? AppColors.slate50 : backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: isToday
                            ? Border.all(color: AppColors.primary600, width: 3)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null && !isFuture) ...[
                            Text(icon, style: const TextStyle(fontSize: 20)),
                          ],
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isFuture
                                  ? AppColors.slate400
                                  : AppColors.slate600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// Mock data for previews
final _mockExerciseRecords = [
  ExerciseRecord(
    id: '1',
    clientId: 'client-1',
    exerciseType: 'strength_training',
    memo: 'Full Body Workout - Squats, Deadlifts, Bench Press',
    images: null,
    duration: 45,
    distance: null,
    calories: 320,
    recordedAt: DateTime.now().subtract(const Duration(hours: 2)),
    source: 'manual',
    messageId: null,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  ExerciseRecord(
    id: '2',
    clientId: 'client-1',
    exerciseType: 'cardio',
    memo: 'Morning Jog in the Park',
    images: null,
    duration: 30,
    distance: 5.0,
    calories: 280,
    recordedAt: DateTime.now().subtract(const Duration(hours: 8)),
    source: 'message',
    messageId: 'msg-1',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  ExerciseRecord(
    id: '3',
    clientId: 'client-1',
    exerciseType: 'strength_training',
    memo: 'Upper Body - Pull-ups, Rows, Curls',
    images: null,
    duration: 40,
    distance: null,
    calories: 250,
    recordedAt: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
    source: 'manual',
    messageId: null,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
];
