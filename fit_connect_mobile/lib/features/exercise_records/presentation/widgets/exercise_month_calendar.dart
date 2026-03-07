import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';

/// 月カレンダー（運動記録）
class ExerciseMonthCalendar extends ConsumerStatefulWidget {
  final void Function(DateTime month)? onMonthChanged;

  const ExerciseMonthCalendar({
    super.key,
    this.onMonthChanged,
  });

  @override
  ConsumerState<ExerciseMonthCalendar> createState() =>
      _ExerciseMonthCalendarState();
}

class _ExerciseMonthCalendarState extends ConsumerState<ExerciseMonthCalendar> {
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

    final countsAsync = ref.watch(
      exerciseRecordCountsProvider(
        startDate: startOfMonth,
        endDate: endOfMonth,
      ),
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
          // ヘッダー（←  2026年2月  →）
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
          const SizedBox(height: 8),

          // 曜日ヘッダー
          _buildDayHeaders(),
          const SizedBox(height: 6),

          // カレンダーグリッド
          countsAsync.when(
            data: (counts) => _buildCalendarGrid(
              context,
              today,
              startOfMonth,
              endOfMonth,
              counts,
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
    Map<DateTime, int> counts,
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
              final count = counts[date] ?? 0;
              final isToday = date == today;
              final isFuture = date.isAfter(today);

              return Expanded(
                child: _buildDayCell(
                  context: context,
                  date: date,
                  count: count,
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
    required int count,
    required bool isToday,
    required bool isFuture,
  }) {
    final colors = AppColors.of(context);
    final color = isFuture ? Colors.transparent : _getGrassColor(count, colors);
    final textColor = isFuture
        ? colors.textHint
        : (count >= 2 ? Colors.white : colors.textSecondary);

    return AspectRatio(
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
    );
  }

  Widget _buildLegend() {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildLegendItem(_blueLevel3, '3+'),
        const SizedBox(width: 8),
        _buildLegendItem(_blueLevel2, '2'),
        const SizedBox(width: 8),
        _buildLegendItem(_blueLevel1, '1'),
        const SizedBox(width: 8),
        _buildLegendItem(colors.calendarEmpty, '0'),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
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

  static const Color _blueLevel0 = Color(0xFFE2E8F0); // slate200相当
  static const Color _blueLevel1 = Color(0xFFBFDBFE); // primary200相当
  static const Color _blueLevel2 = Color(0xFF60A5FA); // primary400相当
  static const Color _blueLevel3 = Color(0xFF2563EB); // primary600相当

  Color _getGrassColor(int count, AppColorsExtension colors) {
    switch (count) {
      case 0:
        return colors.calendarEmpty;
      case 1:
        return _blueLevel1;
      case 2:
        return _blueLevel2;
      default:
        return _blueLevel3;
    }
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'ExerciseMonthCalendar - Static Preview')
Widget previewExerciseMonthCalendarStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _PreviewExerciseMonthCalendar(),
        ),
      ),
    ),
  );
}

class _PreviewExerciseMonthCalendar extends StatefulWidget {
  @override
  State<_PreviewExerciseMonthCalendar> createState() =>
      _PreviewExerciseMonthCalendarState();
}

class _PreviewExerciseMonthCalendarState
    extends State<_PreviewExerciseMonthCalendar> {
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfMonth = _currentMonth;
    final endOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    // Mock data - pattern based on day % 4
    final mockCounts = <DateTime, int>{};
    for (int day = 1; day <= endOfMonth.day; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      if (!date.isAfter(today)) {
        mockCounts[date] = (day % 4);
      }
    }

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
          // ヘッダー（←  2026年2月  →）
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
          const SizedBox(height: 8),

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
                  final count = mockCounts[date] ?? 0;
                  final isToday = date == today;
                  final isFuture = date.isAfter(today);

                  final color =
                      isFuture ? Colors.transparent : _getGrassColor(count, colors);
                  final textColor = isFuture
                      ? colors.textHint
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
              _buildLegendItem(context, const Color(0xFF2563EB), '3+'),
              const SizedBox(width: 8),
              _buildLegendItem(context, const Color(0xFF60A5FA), '2'),
              const SizedBox(width: 8),
              _buildLegendItem(context, const Color(0xFFBFDBFE), '1'),
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

  Color _getGrassColor(int count, AppColorsExtension colors) {
    switch (count) {
      case 0:
        return colors.calendarEmpty;
      case 1:
        return const Color(0xFFBFDBFE);
      case 2:
        return const Color(0xFF60A5FA);
      default:
        return const Color(0xFF2563EB);
    }
  }
}
