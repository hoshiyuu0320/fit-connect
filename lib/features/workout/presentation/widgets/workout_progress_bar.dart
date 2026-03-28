import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

class WorkoutProgressBar extends StatelessWidget {
  const WorkoutProgressBar({
    super.key,
    required this.completed,
    required this.total,
  });

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final bool isCompleted = total > 0 && completed >= total;
    final double progress = total > 0 ? completed / total : 0.0;
    final Color barColor =
        isCompleted ? AppColors.emerald500 : AppColors.primary600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isCompleted ? '$completed/$total種目完了 ✓' : '$completed/$total種目完了',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isCompleted
                ? AppColors.emerald500
                : AppColors.of(context).textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.of(context).border,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'WorkoutProgressBar - In Progress')
Widget previewWorkoutProgressBarInProgress() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: WorkoutProgressBar(completed: 3, total: 5),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutProgressBar - Completed')
Widget previewWorkoutProgressBarCompleted() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: WorkoutProgressBar(completed: 5, total: 5),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutProgressBar - Empty')
Widget previewWorkoutProgressBarEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: WorkoutProgressBar(completed: 0, total: 5),
        ),
      ),
    ),
  );
}
