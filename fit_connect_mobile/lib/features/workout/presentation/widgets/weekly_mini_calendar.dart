import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:lucide_icons/lucide_icons.dart';

class WeeklyMiniCalendar extends StatelessWidget {
  const WeeklyMiniCalendar({
    super.key,
    required this.weeklyData,
  });

  final Map<DateTime, List<WorkoutAssignment>> weeklyData;

  /// 今週の月曜日を返す
  DateTime _getThisMonday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // weekday: 1=月, 7=日
    final offset = today.weekday - 1;
    return today.subtract(Duration(days: offset));
  }

  /// assignedDate文字列 "YYYY-MM-DD" を DateTime(date only)に変換
  DateTime _parseDateStr(String dateStr) {
    final parts = dateStr.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// weeklyDataのキーを date-only の DateTime で比較するためのマップを構築
  List<WorkoutAssignment>? _assignmentsForDay(DateTime day) {
    for (final entry in weeklyData.entries) {
      final key = DateTime(entry.key.year, entry.key.month, entry.key.day);
      if (key == day) return entry.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final monday = _getThisMonday();
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));
    const weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            '今週のワークアウト',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(7, (i) {
              final day = weekDays[i];
              final isToday = day == today;
              final assignments = _assignmentsForDay(day);
              return Expanded(
                child: _DayCell(
                  day: day,
                  weekdayLabel: weekdayLabels[i],
                  isToday: isToday,
                  assignments: assignments,
                  parseDateStr: _parseDateStr,
                  today: today,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.weekdayLabel,
    required this.isToday,
    required this.assignments,
    required this.parseDateStr,
    required this.today,
  });

  final DateTime day;
  final String weekdayLabel;
  final bool isToday;
  final List<WorkoutAssignment>? assignments;
  final DateTime Function(String) parseDateStr;
  final DateTime today;

  _CellStyle _resolveCellStyle() {
    if (assignments == null || assignments!.isEmpty) {
      return _CellStyle(
        backgroundColor: AppColors.slate50,
        icon: null,
        iconColor: null,
      );
    }

    // 最初のアサインメントのステータスで判断
    final first = assignments!.first;
    final status = first.status;
    final assignedDate = parseDateStr(first.assignedDate);
    final isFuture = assignedDate.isAfter(today);

    if (status == 'completed') {
      return _CellStyle(
        backgroundColor: AppColors.emerald50,
        icon: Icons.check_circle_outline,
        iconColor: AppColors.emerald500,
      );
    } else if (status == 'skipped') {
      return _CellStyle(
        backgroundColor: AppColors.slate100,
        icon: Icons.skip_next_outlined,
        iconColor: AppColors.slate400,
      );
    } else if (status == 'pending') {
      if (isFuture) {
        return _CellStyle(
          backgroundColor: AppColors.indigo50,
          icon: Icons.fitness_center,
          iconColor: AppColors.indigo600,
        );
      } else {
        return _CellStyle(
          backgroundColor: AppColors.orange50,
          icon: Icons.hourglass_empty,
          iconColor: AppColors.orange500,
        );
      }
    }

    return _CellStyle(
      backgroundColor: AppColors.slate50,
      icon: null,
      iconColor: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _resolveCellStyle();
    final hasAssignments = assignments != null && assignments!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: hasAssignments
            ? () => _showDayDetail(context)
            : null,
        child: Container(
          decoration: BoxDecoration(
            color: style.backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: isToday
                ? Border.all(color: AppColors.primary600, width: 2)
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekdayLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isToday ? AppColors.primary600 : AppColors.slate500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isToday ? AppColors.primary600 : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 20,
                child: style.icon != null
                    ? Icon(style.icon, size: 16, color: style.iconColor)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDayDetail(BuildContext context) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final dateLabel = '${day.month}月${day.day}日(${weekdays[day.weekday - 1]})';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DayDetailSheet(
        dateLabel: dateLabel,
        assignments: assignments!,
      ),
    );
  }
}

/// 日付タップ時に表示するボトムシート（閲覧専用）
class _DayDetailSheet extends StatelessWidget {
  const _DayDetailSheet({
    required this.dateLabel,
    required this.assignments,
  });

  final String dateLabel;
  final List<WorkoutAssignment> assignments;

  String _formatWeight(double weight) {
    if (weight == weight.truncateToDouble()) {
      return weight.toInt().toString();
    }
    return weight.toString();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return '完了';
      case 'skipped':
        return 'スキップ';
      case 'pending':
        return '予定';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.emerald500;
      case 'skipped':
        return AppColors.slate400;
      case 'pending':
        return AppColors.indigo600;
      default:
        return AppColors.slate500;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'completed':
        return AppColors.emerald50;
      case 'skipped':
        return AppColors.slate100;
      case 'pending':
        return AppColors.indigo50;
      default:
        return AppColors.slate50;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ハンドル
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 日付タイトル
            Text(
              dateLabel,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // アサインメント一覧
            for (int i = 0; i < assignments.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _buildAssignmentTile(assignments[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentTile(WorkoutAssignment assignment) {
    final plan = assignment.planInfo;
    final title = plan?.title ?? 'ワークアウト';
    final status = assignment.status;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // タイトル + ステータスバッジ
          Row(
            children: [
              Icon(LucideIcons.dumbbell, size: 16, color: AppColors.slate500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusBg(status),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(status),
                  ),
                ),
              ),
            ],
          ),

          // カテゴリ・時間
          if (plan != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (plan.category.isNotEmpty) ...[
                  Icon(LucideIcons.tag, size: 12, color: AppColors.slate400),
                  const SizedBox(width: 4),
                  Text(
                    plan.category,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate500,
                    ),
                  ),
                ],
                if (plan.estimatedMinutes != null) ...[
                  const SizedBox(width: 12),
                  Icon(LucideIcons.clock, size: 12, color: AppColors.slate400),
                  const SizedBox(width: 4),
                  Text(
                    '${plan.estimatedMinutes}分',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate500,
                    ),
                  ),
                ],
              ],
            ),
          ],

          // 説明（あれば）
          if (plan?.description != null && plan!.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              plan.description!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.slate500,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // 種目リスト（あれば）
          if (assignment.exercises.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 1, color: AppColors.slate100),
            const SizedBox(height: 10),
            ...assignment.exercises
                .toList()
                .asMap()
                .entries
                .map((entry) => _buildExerciseRow(entry.value, entry.key < assignment.exercises.length - 1)),
          ],
        ],
      ),
    );
  }

  Widget _buildExerciseRow(WorkoutAssignmentExercise exercise, bool showBottomMargin) {
    final hasActualSets = exercise.actualSets != null && exercise.actualSets!.isNotEmpty;

    // 目標テキスト組み立て
    final targetParts = <String>[
      '${exercise.targetSets}×${exercise.targetReps}',
    ];
    if (exercise.targetWeight != null) {
      targetParts.add('${_formatWeight(exercise.targetWeight!)}kg');
    }
    final targetText = targetParts.join('  ');

    return Padding(
      padding: EdgeInsets.only(bottom: showBottomMargin ? 8 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 種目行: アイコン + 種目名 + 目標
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                exercise.isCompleted
                    ? LucideIcons.checkCircle2
                    : LucideIcons.circle,
                size: 14,
                color: exercise.isCompleted
                    ? AppColors.emerald500
                    : AppColors.slate300,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  exercise.exerciseName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                targetText,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.slate500,
                ),
              ),
            ],
          ),

          // 実績セット（あれば）
          if (hasActualSets) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 2,
                children: exercise.actualSets!
                    .map((set) => _buildActualSetChip(set))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActualSetChip(ActualSet set) {
    final weightText = set.weight > 0 ? '${_formatWeight(set.weight)}kg × ' : '';
    return Text(
      'Set${set.setNumber}: $weightText${set.reps}回',
      style: TextStyle(
        fontSize: 11,
        color: set.done ? AppColors.slate500 : AppColors.slate400,
      ),
    );
  }
}

class _CellStyle {
  const _CellStyle({
    required this.backgroundColor,
    required this.icon,
    required this.iconColor,
  });

  final Color backgroundColor;
  final IconData? icon;
  final Color? iconColor;
}

// ============================================
// Previews
// ============================================

Map<DateTime, List<WorkoutAssignment>> _buildPreviewWeeklyData() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));

  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  WorkoutAssignment makeAssignment(DateTime day, String status) {
    return WorkoutAssignment(
      id: 'preview-${day.day}',
      clientId: 'client-1',
      trainerId: 'trainer-1',
      planId: 'plan-1',
      assignedDate: fmt(day),
      status: status,
      planInfo: const WorkoutPlanInfo(
        title: 'ワークアウト',
        category: 'strength',
      ),
      exercises: [
        WorkoutAssignmentExercise(
          id: 'ex-preview-1',
          assignmentId: 'preview-${day.day}',
          exerciseName: 'ベンチプレス',
          targetSets: 3,
          targetReps: 10,
          targetWeight: 60.0,
          orderIndex: 0,
          isCompleted: status == 'completed',
          actualSets: status == 'completed'
              ? const [
                  ActualSet(setNumber: 1, reps: 10, weight: 60.0, done: true),
                  ActualSet(setNumber: 2, reps: 8, weight: 60.0, done: true),
                  ActualSet(setNumber: 3, reps: 10, weight: 55.0, done: true),
                ]
              : null,
        ),
        WorkoutAssignmentExercise(
          id: 'ex-preview-2',
          assignmentId: 'preview-${day.day}',
          exerciseName: 'ケーブルクロス',
          targetSets: 3,
          targetReps: 15,
          targetWeight: null,
          orderIndex: 1,
          isCompleted: false,
        ),
      ],
    );
  }

  final mon = monday;
  final wed = monday.add(const Duration(days: 2));
  final thu = monday.add(const Duration(days: 3));
  final fri = monday.add(const Duration(days: 4));
  final sat = monday.add(const Duration(days: 5));

  return {
    mon: [makeAssignment(mon, 'completed')],
    // 火: アサインメントなし
    wed: [makeAssignment(wed, 'completed')],
    thu: [makeAssignment(thu, 'pending')],
    fri: [makeAssignment(fri, 'pending')],
    sat: [makeAssignment(sat, 'skipped')],
  };
}

@Preview(name: 'WeeklyMiniCalendar - With Data')
Widget previewWeeklyMiniCalendar() {
  final weeklyData = _buildPreviewWeeklyData();

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: WeeklyMiniCalendar(weeklyData: weeklyData),
        ),
      ),
    ),
  );
}

@Preview(name: 'DayDetailSheet - With Exercises (Completed)')
Widget previewDayDetailSheetCompleted() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final assignments = [
    WorkoutAssignment(
      id: 'preview-sheet-1',
      clientId: 'client-1',
      trainerId: 'trainer-1',
      planId: 'plan-1',
      assignedDate:
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      status: 'completed',
      planInfo: const WorkoutPlanInfo(
        title: '大胸筋の強化',
        description: '胸筋メインのトレーニング',
        category: '胸',
        estimatedMinutes: 60,
      ),
      exercises: [
        WorkoutAssignmentExercise(
          id: 'ex-1',
          assignmentId: 'preview-sheet-1',
          exerciseName: 'ベンチプレス',
          targetSets: 3,
          targetReps: 10,
          targetWeight: 60.0,
          orderIndex: 0,
          isCompleted: true,
          actualSets: const [
            ActualSet(setNumber: 1, reps: 10, weight: 60.0, done: true),
            ActualSet(setNumber: 2, reps: 8, weight: 60.0, done: true),
            ActualSet(setNumber: 3, reps: 10, weight: 55.0, done: true),
          ],
        ),
        WorkoutAssignmentExercise(
          id: 'ex-2',
          assignmentId: 'preview-sheet-1',
          exerciseName: 'インクラインダンベル',
          targetSets: 3,
          targetReps: 10,
          targetWeight: 40.0,
          orderIndex: 1,
          isCompleted: true,
          actualSets: const [
            ActualSet(setNumber: 1, reps: 10, weight: 40.0, done: true),
            ActualSet(setNumber: 2, reps: 10, weight: 40.0, done: true),
            ActualSet(setNumber: 3, reps: 8, weight: 40.0, done: true),
          ],
        ),
        WorkoutAssignmentExercise(
          id: 'ex-3',
          assignmentId: 'preview-sheet-1',
          exerciseName: 'ケーブルクロス',
          targetSets: 3,
          targetReps: 15,
          targetWeight: null,
          orderIndex: 2,
          isCompleted: false,
        ),
      ],
    ),
  ];

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _DayDetailSheet(
          dateLabel: '${today.month}月${today.day}日(月)',
          assignments: assignments,
        ),
      ),
    ),
  );
}

@Preview(name: 'DayDetailSheet - Pending (No Actual Sets)')
Widget previewDayDetailSheetPending() {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);

  final assignments = [
    WorkoutAssignment(
      id: 'preview-sheet-2',
      clientId: 'client-1',
      trainerId: 'trainer-1',
      planId: 'plan-2',
      assignedDate:
          '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}',
      status: 'pending',
      planInfo: const WorkoutPlanInfo(
        title: '下半身強化メニュー',
        category: '脚',
        estimatedMinutes: 45,
      ),
      exercises: [
        WorkoutAssignmentExercise(
          id: 'ex-4',
          assignmentId: 'preview-sheet-2',
          exerciseName: 'バーベルスクワット',
          targetSets: 4,
          targetReps: 8,
          targetWeight: 80.0,
          orderIndex: 0,
          isCompleted: false,
        ),
        WorkoutAssignmentExercise(
          id: 'ex-5',
          assignmentId: 'preview-sheet-2',
          exerciseName: 'レッグプレス',
          targetSets: 3,
          targetReps: 12,
          targetWeight: 120.0,
          orderIndex: 1,
          isCompleted: false,
        ),
        WorkoutAssignmentExercise(
          id: 'ex-6',
          assignmentId: 'preview-sheet-2',
          exerciseName: 'カーフレイズ',
          targetSets: 3,
          targetReps: 20,
          targetWeight: null,
          orderIndex: 2,
          isCompleted: false,
        ),
      ],
    ),
  ];

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _DayDetailSheet(
          dateLabel: '${tomorrow.month}月${tomorrow.day}日(火)',
          assignments: assignments,
        ),
      ),
    ),
  );
}
