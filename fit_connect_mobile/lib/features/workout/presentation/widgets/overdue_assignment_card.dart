import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/reschedule_date_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

class OverdueAssignmentCard extends StatelessWidget {
  const OverdueAssignmentCard({
    super.key,
    required this.assignment,
    required this.onDoToday,
    required this.onSkip,
    required this.onReschedule,
  });

  final WorkoutAssignment assignment;
  final VoidCallback onDoToday;
  final VoidCallback onSkip;
  final ValueChanged<DateTime> onReschedule;

  int _calculateDaysOverdue(String dateStr) {
    final parts = dateStr.split('-');
    final assigned = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return todayDate.difference(assigned).inDays;
  }

  String _weekdayLabel(int weekday) {
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return labels[weekday - 1];
  }

  String _formatAssignedDate(String dateStr) {
    final parts = dateStr.split('-');
    final dt = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    return '${dt.month}月${dt.day}日(${_weekdayLabel(dt.weekday)})';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final daysOverdue = _calculateDaysOverdue(assignment.assignedDate);
    final title = assignment.planInfo?.title ?? 'ワークアウト';
    final formattedDate = _formatAssignedDate(assignment.assignedDate);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange500, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                LucideIcons.alertCircle,
                size: 18,
                color: AppColors.orange500,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.accentOrange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$daysOverdue日前',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Sub text
          Text(
            '$formattedDate のプラン',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),

          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.play,
                  label: '今日やる',
                  color: AppColors.emerald500,
                  onTap: onDoToday,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.skipForward,
                  label: 'スキップ',
                  color: colors.textHint,
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('スキップしますか？'),
                        content: Text(
                          '「${assignment.planInfo?.title ?? 'ワークアウト'}」をスキップします。この操作は取り消せません。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('キャンセル'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.slate400,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('スキップする'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) onSkip();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.calendarDays,
                  label: '日付変更',
                  color: AppColors.primary500,
                  onTap: () async {
                    final picked = await showDialog<DateTime>(
                      context: context,
                      builder: (_) => const RescheduleDatePicker(),
                    );
                    if (picked != null) onReschedule(picked);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

WorkoutAssignment _makeOverdueAssignment({
  required String assignedDate,
  required String title,
}) {
  return WorkoutAssignment(
    id: 'preview-id',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    planId: 'plan-1',
    assignedDate: assignedDate,
    status: 'pending',
    planInfo: WorkoutPlanInfo(
      title: title,
      category: 'strength',
      estimatedMinutes: 45,
    ),
  );
}

@Preview(name: 'OverdueAssignmentCard - 1日前')
Widget previewOverdueAssignmentCard1DayAgo() {
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  final dateStr =
      '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
  final assignment = _makeOverdueAssignment(
    assignedDate: dateStr,
    title: '上半身トレーニング',
  );

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OverdueAssignmentCard(
            assignment: assignment,
            onDoToday: () {},
            onSkip: () {},
            onReschedule: (_) {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'OverdueAssignmentCard - 3日前')
Widget previewOverdueAssignmentCard3DaysAgo() {
  final now = DateTime.now();
  final threeDaysAgo = now.subtract(const Duration(days: 3));
  final dateStr =
      '${threeDaysAgo.year}-${threeDaysAgo.month.toString().padLeft(2, '0')}-${threeDaysAgo.day.toString().padLeft(2, '0')}';
  final assignment = _makeOverdueAssignment(
    assignedDate: dateStr,
    title: '下半身トレーニング',
  );

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OverdueAssignmentCard(
            assignment: assignment,
            onDoToday: () {},
            onSkip: () {},
            onReschedule: (_) {},
          ),
        ),
      ),
    ),
  );
}
