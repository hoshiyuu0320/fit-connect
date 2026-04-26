import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';
import 'package:intl/intl.dart';

/// 運動記録の週カレンダー（横一列7日、アイコン表示）
class ExerciseWeekCalendar extends ConsumerWidget {
  final void Function(DateTime date)? onDayTap;

  const ExerciseWeekCalendar({
    super.key,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Calculate the week range (Monday to Sunday)
    final daysFromMonday = (today.weekday - 1) % 7;
    final startOfWeek = today.subtract(Duration(days: daysFromMonday));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    final exerciseDataAsync = ref.watch(
      weeklyExerciseDataProvider(startDate: startOfWeek, endDate: endOfWeek),
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
          // Header
          Text(
            '${DateFormat('M月').format(startOfWeek)} ${DateFormat('yyyy').format(today)}（週間）',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Week days grid
          exerciseDataAsync.when(
            data: (exerciseData) => _buildWeekGrid(
              context,
              today,
              startOfWeek,
              exerciseData,
            ),
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
    BuildContext context,
    DateTime today,
    DateTime startOfWeek,
    Map<DateTime, List<String>> exerciseData,
  ) {
    const dayLabels = ['月', '火', '水', '木', '金', '土', '日'];

    return Row(
      children: List.generate(7, (index) {
        final date = startOfWeek.add(Duration(days: index));
        final exerciseTypes = exerciseData[date] ?? [];
        final isToday = date == today;
        final isFuture = date.isAfter(today);

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: _buildDayCell(
              context: context,
              dayLabel: dayLabels[index],
              date: date,
              exerciseTypes: exerciseTypes,
              isToday: isToday,
              isFuture: isFuture,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDayCell({
    required BuildContext context,
    required String dayLabel,
    required DateTime date,
    required List<String> exerciseTypes,
    required bool isToday,
    required bool isFuture,
  }) {
    final colors = AppColors.of(context);
    final hasRecord = exerciseTypes.isNotEmpty;
    final backgroundColor = hasRecord ? colors.accentIndigo : colors.surfaceDim;

    // Pick the icon to display (prioritize strength_training)
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

    return GestureDetector(
      onTap: !isFuture && onDayTap != null ? () => onDayTap!(date) : null,
      child: Column(
        children: [
          // Day label
          Text(
            dayLabel,
            style: TextStyle(
              fontSize: 11,
              color: colors.textHint,
            ),
          ),
          const SizedBox(height: 6),
          // Day cell
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: isFuture ? colors.surfaceDim : backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: isToday
                    ? Border.all(color: AppColors.primary600, width: 3)
                    : null,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null && !isFuture) ...[
                        Text(
                          icon,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ],
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              isFuture ? colors.textHint : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'ExerciseWeekCalendar - Static Preview')
Widget previewExerciseWeekCalendarStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _PreviewExerciseWeekCalendar(),
        ),
      ),
    ),
  );
}

class _PreviewExerciseWeekCalendar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysFromMonday = (today.weekday - 1) % 7;
    final startOfWeek = today.subtract(Duration(days: daysFromMonday));

    // Mock data - exercise types by date
    final mockExerciseData = <DateTime, List<String>>{};
    // Monday - strength training
    mockExerciseData[startOfWeek] = ['strength_training'];
    // Wednesday - strength training
    mockExerciseData[startOfWeek.add(const Duration(days: 2))] = [
      'strength_training'
    ];
    // Thursday - cardio
    mockExerciseData[startOfWeek.add(const Duration(days: 3))] = ['cardio'];
    // Saturday - strength training
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('M月').format(startOfWeek)} ${DateFormat('yyyy').format(today)}（週間）',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
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
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Column(
                    children: [
                      Text(
                        dayLabels[index],
                        style: TextStyle(fontSize: 11, color: colors.textHint),
                      ),
                      const SizedBox(height: 6),
                      AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                isFuture ? colors.surfaceDim : backgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: isToday
                                ? Border.all(
                                    color: AppColors.primary600, width: 3)
                                : null,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (icon != null && !isFuture) ...[
                                    Text(icon,
                                        style: const TextStyle(fontSize: 18)),
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
                          ),
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
