import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/exercise_records/models/exercise_record_model.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_week_calendar.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_month_calendar.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/completed_workout_card.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

// 統合表示用のラッパー型
sealed class _ActivityItem {
  DateTime get date;
  Widget buildCard(_ExerciseRecordScreenState state);
}

class _ExerciseRecordItem extends _ActivityItem {
  final ExerciseRecord record;
  _ExerciseRecordItem(this.record);

  @override
  DateTime get date => DateTime(
        record.recordedAt.year,
        record.recordedAt.month,
        record.recordedAt.day,
      );

  @override
  Widget buildCard(_ExerciseRecordScreenState state) =>
      state._buildExerciseCard(record);
}

class _WorkoutAssignmentItem extends _ActivityItem {
  final WorkoutAssignment assignment;
  _WorkoutAssignmentItem(this.assignment);

  @override
  DateTime get date {
    if (assignment.finishedAt != null) {
      return DateTime(
        assignment.finishedAt!.year,
        assignment.finishedAt!.month,
        assignment.finishedAt!.day,
      );
    }
    // fallback: assignedDate を parse
    final parts = assignment.assignedDate.split('-');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    return DateTime.now();
  }

  @override
  Widget buildCard(_ExerciseRecordScreenState state) =>
      CompletedWorkoutCard(assignment: assignment);
}

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
    final workoutsAsync = ref.watch(
      completedWorkoutAssignmentsProvider(period: _selectedPeriod),
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

        // Exercise Records List (with workout assignments)
        _buildRecordsList(recordsAsync, workoutsAsync),
      ],
    );
  }

  Widget _buildPeriodFilter() {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
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
                      color: isActive ? Colors.white : colors.textHint,
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
    final colors = AppColors.of(context);
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
                  color: isActive ? colors.accentIndigo : colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive ? colors.accentIndigoBorder : colors.border,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      type.$3,
                      size: 16,
                      color: isActive ? AppColors.indigo600 : colors.textHint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type.$2,
                      style: TextStyle(
                        color: isActive
                            ? AppColors.indigo600
                            : colors.textSecondary,
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.accentIndigo, colors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.accentIndigoBorder),
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
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _buildSummaryStat('合計', total.toString(), '📊')),
                  const SizedBox(width: 8),
                  Expanded(
                      child:
                          _buildSummaryStat('筋トレ', strength.toString(), '🏋️')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _buildSummaryStat('有酸素', cardio.toString(), '🏃')),
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
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }

  Widget _buildCaloriesRow(double? calories) {
    final colors = AppColors.of(context);
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
        color: colors.surface.withAlpha(153),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surface),
      ),
      child: Row(
        children: [
          const Text(
            '🔥',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          Text(
            '消費カロリー',
            style: TextStyle(
              color: colors.textSecondary,
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(153),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surface),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList(
    AsyncValue<List<ExerciseRecord>> recordsAsync,
    AsyncValue<List<WorkoutAssignment>> workoutsAsync,
  ) {
    final colors = AppColors.of(context);
    // どちらかがロード中の場合はローディング表示
    if (recordsAsync.isLoading || workoutsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // エラーハンドリング（recordsを優先）
    if (recordsAsync.hasError) {
      return Center(child: Text('エラー: ${recordsAsync.error}'));
    }

    final records = recordsAsync.valueOrNull ?? [];
    final allWorkouts = workoutsAsync.valueOrNull ?? [];

    // TypeFilterに応じてワークアウト表示を切り替える
    // cardio フィルター選択時はワークアウトを非表示
    // すべて or strength_training のときはワークアウトも表示
    final showWorkouts = _selectedType != 'cardio';
    final filteredWorkouts = showWorkouts ? allWorkouts : <WorkoutAssignment>[];

    // 統合アイテムリストを作成
    final List<_ActivityItem> items = [
      ...records.map(_ExerciseRecordItem.new),
      ...filteredWorkouts.map(_WorkoutAssignmentItem.new),
    ];

    // 両データソースが空の場合のみ空状態を表示
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.dumbbell, size: 48, color: colors.textHint),
              const SizedBox(height: 12),
              Text(
                '運動記録がありません',
                style: TextStyle(color: colors.textHint),
              ),
              const SizedBox(height: 8),
              Text(
                '運動を記録しましょう！',
                style: TextStyle(color: colors.textHint, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // 日付降順でソート
    items.sort((a, b) => b.date.compareTo(a.date));

    // 日付グルーピング
    final Map<DateTime, List<_ActivityItem>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item.date, () => []);
      grouped[item.date]!.add(item);
    }

    // 日付キーを降順にソート
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedDates.map((date) {
        final dateItems = grouped[date]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Header
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(
                _formatDateHeader(date),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 16),
            // Activity Cards
            ...dateItems.map((item) => item.buildCard(this)),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
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
    final colors = AppColors.of(context);
    final isStrength = record.exerciseType == 'strength_training';
    final color = isStrength ? AppColors.purple500 : AppColors.orange500;
    final bg = isStrength ? colors.accentPurple : colors.accentOrange;
    final icon = isStrength ? '🏋️' : '🏃';
    final typeLabel = _getExerciseTypeLabel(record.exerciseType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
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
                    Icon(LucideIcons.clock, size: 12, color: colors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(record.recordedAt),
                      style: TextStyle(color: colors.textHint, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  record.memo ?? typeLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (record.duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${record.duration}分',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
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

            // Records List Preview (with workout cards)
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
            Builder(builder: (context) {
              final colors = AppColors.of(context);
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.dumbbell,
                          size: 48, color: colors.textHint),
                      const SizedBox(height: 12),
                      Text(
                        '運動記録がありません',
                        style: TextStyle(color: colors.textHint),
                      ),
                    ],
                  ),
                ),
              );
            }),
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: ['今日', '週', '月', '3ヶ月', '全期間'].asMap().entries.map((e) {
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
                    color: isActive ? Colors.white : colors.textHint,
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
    final colors = AppColors.of(context);
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
                color: isActive ? colors.accentIndigo : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? colors.accentIndigoBorder : colors.border,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type.$2,
                    size: 16,
                    color: isActive ? AppColors.indigo600 : colors.textHint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    type.$1,
                    style: TextStyle(
                      color:
                          isActive ? AppColors.indigo600 : colors.textSecondary,
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.accentIndigo, colors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.accentIndigoBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "📊 今週のサマリー",
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStat(context, '合計', '5', '📊')),
              const SizedBox(width: 8),
              Expanded(child: _buildStat(context, '筋トレ', '3', '🏋️')),
              const SizedBox(width: 8),
              Expanded(child: _buildStat(context, '有酸素', '2', '🏃')),
            ],
          ),
          const SizedBox(height: 12),
          // Calories Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surface.withAlpha(153),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.surface),
            ),
            child: Row(
              children: [
                const Text(
                  '🔥',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  '消費カロリー',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Text(
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

  Widget _buildStat(
      BuildContext context, String label, String value, String icon) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(153),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surface),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.accentIndigo, colors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.accentIndigoBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "📊 今週のサマリー",
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _PreviewSummaryCard()
                      ._buildStat(context, '合計', '0', '📊')),
              const SizedBox(width: 8),
              Expanded(
                  child: _PreviewSummaryCard()
                      ._buildStat(context, '筋トレ', '0', '🏋️')),
              const SizedBox(width: 8),
              Expanded(
                  child: _PreviewSummaryCard()
                      ._buildStat(context, '有酸素', '0', '🏃')),
            ],
          ),
          const SizedBox(height: 12),
          // Calories Row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surface.withAlpha(153),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.surface),
            ),
            child: Row(
              children: [
                const Text(
                  '🔥',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  '消費カロリー',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Text(
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
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Today section
        Text(
          '今日',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Divider(height: 24, color: colors.border),
        _buildExerciseCard(context, _mockExerciseRecords[0]),
        CompletedWorkoutCard(assignment: _mockWorkoutAssignment),
        const SizedBox(height: 8),

        // Yesterday section
        Text(
          '昨日',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Divider(height: 24, color: colors.border),
        _buildExerciseCard(context, _mockExerciseRecords[1]),
        _buildExerciseCard(context, _mockExerciseRecords[2]),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildExerciseCard(BuildContext context, ExerciseRecord record) {
    final colors = AppColors.of(context);
    final isStrength = record.exerciseType == 'strength_training';
    final color = isStrength ? AppColors.purple500 : AppColors.orange500;
    final bg = isStrength ? colors.accentPurple : colors.accentOrange;
    final icon = isStrength ? '🏋️' : '🏃';
    final typeLabel = isStrength ? '筋トレ' : '有酸素運動';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
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
                    Icon(LucideIcons.clock, size: 12, color: colors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(record.recordedAt),
                      style: TextStyle(color: colors.textHint, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  record.memo ?? typeLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (record.duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${record.duration}分',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
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
    final colors = AppColors.of(context);
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
        color: colors.surface,
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
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
                  hasRecord ? colors.accentIndigo : colors.surfaceDim;

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
                        style: TextStyle(fontSize: 11, color: colors.textHint),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 44,
                        height: 52,
                        decoration: BoxDecoration(
                          color: isFuture ? colors.surfaceDim : backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday
                              ? Border.all(
                                  color: AppColors.primary600, width: 3)
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
                                    ? colors.textHint
                                    : colors.textSecondary,
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
    memo: '全身トレーニング - スクワット、デッドリフト、ベンチプレス',
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
    memo: '朝の公園ジョギング',
    images: null,
    duration: 30,
    distance: 5.0,
    calories: 280,
    recordedAt: DateTime.now().subtract(const Duration(days: 1, hours: 8)),
    source: 'message',
    messageId: 'msg-1',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  ExerciseRecord(
    id: '3',
    clientId: 'client-1',
    exerciseType: 'strength_training',
    memo: '上半身トレーニング - 懸垂、ローイング、カール',
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

final _mockWorkoutAssignment = WorkoutAssignment(
  id: 'preview-wa-1',
  clientId: 'client-1',
  trainerId: 'trainer-1',
  planId: 'plan-1',
  assignedDate: '2026-02-22',
  status: 'completed',
  finishedAt: DateTime.now().subtract(const Duration(hours: 4)),
  planInfo: const WorkoutPlanInfo(
    title: '上半身トレーニング',
    category: '上半身',
    estimatedMinutes: 45,
    planType: 'self_guided',
  ),
  exercises: [
    WorkoutAssignmentExercise(
      id: 'preview-ex-1',
      assignmentId: 'preview-wa-1',
      exerciseName: 'ベンチプレス',
      targetSets: 3,
      targetReps: 10,
      targetWeight: 60.0,
      orderIndex: 0,
      isCompleted: true,
      actualSets: const [
        ActualSet(setNumber: 1, reps: 10, weight: 60.0, done: true),
        ActualSet(setNumber: 2, reps: 8, weight: 65.0, done: true),
        ActualSet(setNumber: 3, reps: 8, weight: 60.0, done: true),
      ],
    ),
  ],
);
