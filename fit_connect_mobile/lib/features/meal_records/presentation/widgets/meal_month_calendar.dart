import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:intl/intl.dart';

/// 月カレンダー（7列×複数行のグリッド）
class MealMonthCalendar extends ConsumerWidget {
  final void Function(DateTime date, int mealCount)? onDayTap;

  const MealMonthCalendar({
    super.key,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Current month range
    final startOfMonth = DateTime(today.year, today.month, 1);
    final endOfMonth = DateTime(today.year, today.month + 1, 0);

    final mealCountsAsync = ref.watch(
      mealRecordCountsProvider(startDate: startOfMonth, endDate: endOfMonth),
    );

    // Calculate total meals this month
    final totalMeals = mealCountsAsync.whenOrNull(
      data: (counts) => counts.values.fold<int>(0, (sum, v) => sum + v),
    );

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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(today),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate800,
                ),
              ),
              if (totalMeals != null)
                Text(
                  '合計: ${totalMeals}食',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.slate500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Day headers
          _buildDayHeaders(),
          const SizedBox(height: 6),

          // Calendar grid
          mealCountsAsync.when(
            data: (mealCounts) => _buildCalendarGrid(
              today,
              startOfMonth,
              endOfMonth,
              mealCounts,
            ),
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('エラー: $e'),
          ),

          // Legend
          const SizedBox(height: 12),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildDayHeaders() {
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: dayLabels.map((label) {
        return Expanded(
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.slate400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalendarGrid(
    DateTime today,
    DateTime startOfMonth,
    DateTime endOfMonth,
    Map<DateTime, int> mealCounts,
  ) {
    // Calculate first day offset (Monday = 0)
    final firstDayOffset = (startOfMonth.weekday - 1) % 7;

    // Calculate number of rows needed
    final daysInMonth = endOfMonth.day;
    final totalCells = firstDayOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (rowIndex) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: List.generate(7, (colIndex) {
              final cellIndex = rowIndex * 7 + colIndex;
              final dayNumber = cellIndex - firstDayOffset + 1;

              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return Expanded(child: Container());
              }

              final date = DateTime(startOfMonth.year, startOfMonth.month, dayNumber);
              final count = mealCounts[date] ?? 0;
              final isToday = date == today;
              final isFuture = date.isAfter(today);

              return Expanded(
                child: _buildDayCell(
                  date: date,
                  mealCount: count,
                  isToday: isToday,
                  isFuture: isFuture,
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildDayCell({
    required DateTime date,
    required int mealCount,
    required bool isToday,
    required bool isFuture,
  }) {
    final color = isFuture ? Colors.transparent : _getGrassColor(mealCount);
    final textColor = isFuture
        ? AppColors.slate300
        : (mealCount >= 2 ? Colors.white : AppColors.slate600);

    return GestureDetector(
      onTap: !isFuture && onDayTap != null
          ? () => onDayTap!(date, mealCount)
          : null,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isFuture ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(12),
            border: isToday
                ? Border.all(color: AppColors.primary600, width: 3)
                : null,
          ),
          child: Center(
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildLegendItem(AppColors.grassLevel3, '3'),
        const SizedBox(width: 8),
        _buildLegendItem(AppColors.grassLevel2, '2'),
        const SizedBox(width: 8),
        _buildLegendItem(AppColors.grassLevel1, '1'),
        const SizedBox(width: 8),
        _buildLegendItem(AppColors.grassLevel0, '0'),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.slate500,
          ),
        ),
      ],
    );
  }

  Color _getGrassColor(int mealCount) {
    switch (mealCount) {
      case 0:
        return AppColors.grassLevel0;
      case 1:
        return AppColors.grassLevel1;
      case 2:
        return AppColors.grassLevel2;
      default:
        return AppColors.grassLevel3;
    }
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'MealMonthCalendar - Static Preview')
Widget previewMealMonthCalendarStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _PreviewMealMonthCalendar(),
        ),
      ),
    ),
  );
}

class _PreviewMealMonthCalendar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfMonth = DateTime(today.year, today.month, 1);
    final endOfMonth = DateTime(today.year, today.month + 1, 0);

    // Mock data
    final mockMealCounts = <DateTime, int>{};
    for (int day = 1; day <= endOfMonth.day; day++) {
      final date = DateTime(today.year, today.month, day);
      if (!date.isAfter(today)) {
        mockMealCounts[date] = (day + today.month) % 4;
      }
    }
    // Ensure some variety
    mockMealCounts[DateTime(today.year, today.month, 1)] = 2;
    mockMealCounts[DateTime(today.year, today.month, 3)] = 3;
    mockMealCounts[DateTime(today.year, today.month, 5)] = 1;

    final totalMeals = mockMealCounts.values.fold<int>(0, (sum, v) => sum + v);

    // Calculate first day offset
    final firstDayOffset = (startOfMonth.weekday - 1) % 7;
    final daysInMonth = endOfMonth.day;
    final totalCells = firstDayOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(today),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate800,
                ),
              ),
              Text(
                '合計: ${totalMeals}食',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.slate500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Day headers
          Row(
            children: dayLabels.map((label) {
              return Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.slate400,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),

          // Calendar grid
          ...List.generate(rows, (rowIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: List.generate(7, (colIndex) {
                  final cellIndex = rowIndex * 7 + colIndex;
                  final dayNumber = cellIndex - firstDayOffset + 1;

                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    return Expanded(child: Container());
                  }

                  final date = DateTime(startOfMonth.year, startOfMonth.month, dayNumber);
                  final count = mockMealCounts[date] ?? 0;
                  final isToday = date == today;
                  final isFuture = date.isAfter(today);

                  final color = isFuture ? Colors.transparent : _getGrassColor(count);
                  final textColor = isFuture
                      ? AppColors.slate300
                      : (count >= 2 ? Colors.white : AppColors.slate600);

                  return Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isFuture ? Colors.transparent : color,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday
                              ? Border.all(color: AppColors.primary600, width: 3)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$dayNumber',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),

          // Legend
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildLegendItem(AppColors.grassLevel3, '3'),
              const SizedBox(width: 8),
              _buildLegendItem(AppColors.grassLevel2, '2'),
              const SizedBox(width: 8),
              _buildLegendItem(AppColors.grassLevel1, '1'),
              const SizedBox(width: 8),
              _buildLegendItem(AppColors.grassLevel0, '0'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.slate500,
          ),
        ),
      ],
    );
  }

  Color _getGrassColor(int count) {
    switch (count) {
      case 0:
        return AppColors.grassLevel0;
      case 1:
        return AppColors.grassLevel1;
      case 2:
        return AppColors.grassLevel2;
      default:
        return AppColors.grassLevel3;
    }
  }
}
