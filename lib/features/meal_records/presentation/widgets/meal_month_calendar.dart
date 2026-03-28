import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';

/// 月カレンダー（7列×複数行のグリッド）
class MealMonthCalendar extends ConsumerStatefulWidget {
  final void Function(DateTime date, int mealCount)? onDayTap;
  final void Function(DateTime month)? onMonthChanged;

  const MealMonthCalendar({
    super.key,
    this.onDayTap,
    this.onMonthChanged,
  });

  @override
  ConsumerState<MealMonthCalendar> createState() => _MealMonthCalendarState();
}

class _MealMonthCalendarState extends ConsumerState<MealMonthCalendar> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
  }

  void _previousMonth() {
    final newMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    setState(() {
      _currentMonth = newMonth;
    });
    widget.onMonthChanged?.call(newMonth);
  }

  void _nextMonth() {
    final now = DateTime.now();
    final newMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    if (!newMonth.isAfter(DateTime(now.year, now.month, 1))) {
      setState(() {
        _currentMonth = newMonth;
      });
      widget.onMonthChanged?.call(newMonth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfMonth = _currentMonth;
    final endOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    final mealCountsAsync = ref.watch(
      mealRecordCountsProvider(startDate: startOfMonth, endDate: endOfMonth),
    );

    // Calculate total meals for the displayed month
    final totalMeals = mealCountsAsync.whenOrNull(
      data: (counts) => counts.values.fold<int>(0, (sum, v) => sum + v),
    );

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
          // ヘッダー（← 2026年2月 →）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(LucideIcons.chevronLeft, color: colors.textHint),
                onPressed: _previousMonth,
              ),
              Text(
                '${_currentMonth.year}年${_currentMonth.month}月',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              IconButton(
                icon: Icon(
                  LucideIcons.chevronRight,
                  color: _currentMonth.year == now.year &&
                          _currentMonth.month == now.month
                      ? colors.border
                      : colors.textHint,
                ),
                onPressed: _nextMonth,
              ),
            ],
          ),

          // 合計食数
          if (totalMeals != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '合計: $totalMeals食',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
            )
          else
            const SizedBox(height: 8),

          // 曜日ヘッダー
          _buildDayHeaders(),
          const SizedBox(height: 6),

          // カレンダーグリッド
          mealCountsAsync.when(
            data: (mealCounts) => _buildCalendarGrid(
              context,
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

          // 凡例
          const SizedBox(height: 12),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildDayHeaders() {
    final colors = AppColors.of(context);
    const dayLabels = ['月', '火', '水', '木', '金', '土', '日'];
    return Row(
      children: dayLabels.map((label) {
        return Expanded(
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textHint,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalendarGrid(
    BuildContext context,
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

              final date =
                  DateTime(startOfMonth.year, startOfMonth.month, dayNumber);
              final count = mealCounts[date] ?? 0;
              final isToday = date == today;
              final isFuture = date.isAfter(today);

              return Expanded(
                child: _buildDayCell(
                  context: context,
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
    required BuildContext context,
    required DateTime date,
    required int mealCount,
    required bool isToday,
    required bool isFuture,
  }) {
    final colors = AppColors.of(context);
    final color =
        isFuture ? Colors.transparent : _getGrassColor(mealCount, colors);
    final textColor = isFuture
        ? colors.textHint
        : (mealCount >= 2 ? Colors.white : colors.textSecondary);

    return GestureDetector(
      onTap: !isFuture && widget.onDayTap != null
          ? () => widget.onDayTap!(date, mealCount)
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
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildLegendItem(context, AppColors.grassLevel3, '3'),
        const SizedBox(width: 8),
        _buildLegendItem(context, AppColors.grassLevel2, '2'),
        const SizedBox(width: 8),
        _buildLegendItem(context, AppColors.grassLevel1, '1'),
        const SizedBox(width: 8),
        _buildLegendItem(context, colors.calendarEmpty, '0'),
      ],
    );
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    final colors = AppColors.of(context);
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
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Color _getGrassColor(int mealCount, AppColorsExtension colors) {
    switch (mealCount) {
      case 0:
        return colors.calendarEmpty;
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _PreviewMealMonthCalendar(),
        ),
      ),
    ),
  );
}

class _PreviewMealMonthCalendar extends StatefulWidget {
  @override
  State<_PreviewMealMonthCalendar> createState() =>
      _PreviewMealMonthCalendarState();
}

class _PreviewMealMonthCalendarState extends State<_PreviewMealMonthCalendar> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    if (!nextMonth.isAfter(DateTime(now.year, now.month, 1))) {
      setState(() {
        _currentMonth = nextMonth;
      });
    }
  }

  Color _getGrassColor(int count, AppColorsExtension colors) {
    switch (count) {
      case 0:
        return colors.calendarEmpty;
      case 1:
        return AppColors.grassLevel1;
      case 2:
        return AppColors.grassLevel2;
      default:
        return AppColors.grassLevel3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfMonth = _currentMonth;
    final endOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    // Mock data - pattern based on day % 4
    final mockMealCounts = <DateTime, int>{};
    for (int day = 1; day <= endOfMonth.day; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      if (!date.isAfter(today)) {
        mockMealCounts[date] = (day + _currentMonth.month) % 4;
      }
    }
    // Ensure some variety
    final day1 = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final day3 = DateTime(_currentMonth.year, _currentMonth.month, 3);
    final day5 = DateTime(_currentMonth.year, _currentMonth.month, 5);
    if (!day1.isAfter(today)) mockMealCounts[day1] = 2;
    if (!day3.isAfter(today)) mockMealCounts[day3] = 3;
    if (!day5.isAfter(today)) mockMealCounts[day5] = 1;

    final totalMeals = mockMealCounts.values.fold<int>(0, (sum, v) => sum + v);

    // Calculate first day offset
    final firstDayOffset = (startOfMonth.weekday - 1) % 7;
    final daysInMonth = endOfMonth.day;
    final totalCells = firstDayOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー（← 2026年2月 →）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(LucideIcons.chevronLeft, color: colors.textHint),
                onPressed: _previousMonth,
              ),
              Text(
                '${_currentMonth.year}年${_currentMonth.month}月',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              IconButton(
                icon: Icon(
                  LucideIcons.chevronRight,
                  color: _currentMonth.year == now.year &&
                          _currentMonth.month == now.month
                      ? colors.border
                      : colors.textHint,
                ),
                onPressed: _nextMonth,
              ),
            ],
          ),

          // 合計食数
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '合計: $totalMeals食',
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
          ),

          // 曜日ヘッダー
          Row(
            children: dayLabels.map((label) {
              return Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textHint,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),

          // カレンダーグリッド
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

                  final date = DateTime(
                      startOfMonth.year, startOfMonth.month, dayNumber);
                  final count = mockMealCounts[date] ?? 0;
                  final isToday = date == today;
                  final isFuture = date.isAfter(today);

                  final color = isFuture
                      ? Colors.transparent
                      : _getGrassColor(count, colors);
                  final textColor = isFuture
                      ? colors.textHint
                      : (count >= 2 ? Colors.white : colors.textSecondary);

                  return Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isFuture ? Colors.transparent : color,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday
                              ? Border.all(
                                  color: AppColors.primary600, width: 3)
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

          // 凡例
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildLegendItem(context, AppColors.grassLevel3, '3'),
              const SizedBox(width: 8),
              _buildLegendItem(context, AppColors.grassLevel2, '2'),
              const SizedBox(width: 8),
              _buildLegendItem(context, AppColors.grassLevel1, '1'),
              const SizedBox(width: 8),
              _buildLegendItem(context, colors.calendarEmpty, '0'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    final colors = AppColors.of(context);
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
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
