import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:intl/intl.dart';

/// 週カレンダー（横一列7日）
class MealWeekCalendar extends ConsumerWidget {
  final void Function(DateTime date, int mealCount)? onDayTap;

  const MealWeekCalendar({
    super.key,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Calculate the week range (Monday to Sunday)
    final daysFromMonday = (today.weekday - 1) % 7;
    final startOfWeek = today.subtract(Duration(days: daysFromMonday));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    final mealCountsAsync = ref.watch(
      mealRecordCountsProvider(startDate: startOfWeek, endDate: endOfWeek),
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
          // Header with date range
          Text(
            '${DateFormat('M月d日').format(startOfWeek)}〜${DateFormat('M月d日').format(endOfWeek)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.slate800,
            ),
          ),
          const SizedBox(height: 16),

          // Week days grid
          mealCountsAsync.when(
            data: (mealCounts) => _buildWeekGrid(today, startOfWeek, mealCounts),
            loading: () => const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('エラー: $e'),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekGrid(
    DateTime today,
    DateTime startOfWeek,
    Map<DateTime, int> mealCounts,
  ) {
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      children: List.generate(7, (index) {
        final date = startOfWeek.add(Duration(days: index));
        final count = mealCounts[date] ?? 0;
        final isToday = date == today;
        final isFuture = date.isAfter(today);

        return Expanded(
          child: _buildDayCell(
            dayLabel: dayLabels[index],
            date: date,
            mealCount: count,
            isToday: isToday,
            isFuture: isFuture,
          ),
        );
      }),
    );
  }

  Widget _buildDayCell({
    required String dayLabel,
    required DateTime date,
    required int mealCount,
    required bool isToday,
    required bool isFuture,
  }) {
    final color = isFuture ? AppColors.grassLevel0 : _getGrassColor(mealCount);
    final textColor = mealCount >= 2 && !isFuture ? Colors.white : AppColors.slate600;

    return GestureDetector(
      onTap: !isFuture && onDayTap != null
          ? () => onDayTap!(date, mealCount)
          : null,
      child: Column(
        children: [
          // Day label (M, T, W...)
          Text(
            dayLabel,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.slate400,
            ),
          ),
          const SizedBox(height: 6),
          // Day cell
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: isToday
                  ? Border.all(color: AppColors.primary600, width: 3)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isFuture ? AppColors.slate400 : textColor,
                  ),
                ),
                if (mealCount > 0 && !isFuture)
                  Text(
                    '$mealCount食',
                    style: TextStyle(
                      fontSize: 10,
                      color: textColor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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

@Preview(name: 'MealWeekCalendar - Static Preview')
Widget previewMealWeekCalendarStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _PreviewMealWeekCalendar(),
        ),
      ),
    ),
  );
}

class _PreviewMealWeekCalendar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysFromMonday = (today.weekday - 1) % 7;
    final startOfWeek = today.subtract(Duration(days: daysFromMonday));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    // Mock data
    final mockMealCounts = <DateTime, int>{};
    for (int i = 0; i < 7; i++) {
      final date = startOfWeek.add(Duration(days: i));
      if (date.isBefore(today) || date == today) {
        mockMealCounts[date] = (date.day + i) % 4;
      }
    }
    // Ensure today has some meals
    mockMealCounts[today] = 2;

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
          Text(
            '${DateFormat('M月d日').format(startOfWeek)}〜${DateFormat('M月d日').format(endOfWeek)}',
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
              final count = mockMealCounts[date] ?? 0;
              final isToday = date == today;
              final isFuture = date.isAfter(today);
              final color = isFuture ? AppColors.grassLevel0 : _getGrassColor(count);
              final textColor = count >= 2 && !isFuture ? Colors.white : AppColors.slate600;

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      dayLabels[index],
                      style: const TextStyle(fontSize: 11, color: AppColors.slate400),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        border: isToday
                            ? Border.all(color: AppColors.primary600, width: 3)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isFuture ? AppColors.slate400 : textColor,
                            ),
                          ),
                          if (count > 0 && !isFuture)
                            Text(
                              '$count食',
                              style: TextStyle(fontSize: 10, color: textColor),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
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
