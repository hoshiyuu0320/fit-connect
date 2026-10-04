import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/reschedule_date_picker.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_format.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 日付が過ぎたプラン（正本 `plan-screens.js` の `Overdue` のカード）。
///
/// プラン名（20/500）・右に日付「9/11（金）」・「4種目 · {トレーナー}」と、
/// 操作の行（「今日やる」「日付を変更」「スキップ」。文字を拡大すると折り返す）。
/// 警告色・オレンジの枠・「N日前」のバッジは使わない（日付が過ぎたことは日付と見出しで伝える）。
class OverdueAssignmentCard extends StatelessWidget {
  const OverdueAssignmentCard({
    super.key,
    required this.assignment,
    required this.onDoToday,
    required this.onSkip,
    required this.onReschedule,
    this.trainerName,
  });

  final WorkoutAssignment assignment;
  final VoidCallback onDoToday;
  final VoidCallback onSkip;
  final ValueChanged<DateTime> onReschedule;

  /// トレーナーの名前（「4種目 · {名前}トレーナー」に使う。null なら「トレーナー」）
  final String? trainerName;

  Future<void> _confirmSkip(BuildContext context) async {
    final title = assignment.planInfo?.title ?? 'ワークアウト';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('スキップしますか？'),
        content: Text('「$title」をスキップします。この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('スキップする'),
          ),
        ],
      ),
    );
    if (confirmed == true) onSkip();
  }

  Future<void> _pickNewDate(BuildContext context) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => const RescheduleDatePicker(),
    );
    if (picked != null) onReschedule(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final title = assignment.planInfo?.title ?? 'ワークアウト';
    final date = parseWorkoutAssignedDate(assignment.assignedDate);
    final exerciseCount = assignment.exercises.length;

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // プラン名 ＋ 右に日付（ベースラインを揃える）
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(title, style: AppTextStyles.sectionHeading(context)),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                formatWorkoutShortDate(date),
                style: AppTextStyles.supplement(context)
                    .copyWith(fontFeatures: AppTextStyles.tabularFigures),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '$exerciseCount種目 · ${trainerDisplayName(trainerName)}',
              style: AppTextStyles.supplement(context),
            ),
          ),
          const SizedBox(height: 14),
          // 操作の行（正本は縦 4・横 18 の間隔で折り返す）
          Wrap(
            spacing: 18,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FcButton.pill(label: '今日やる', onPressed: onDoToday),
              FcButton.back(
                label: '日付を変更',
                icon: LucideIcons.calendar,
                iconPosition: FcIconPosition.start,
                onPressed: () => _pickNewDate(context),
              ),
              FcPressable(
                onTap: () => _confirmSkip(context),
                minSize: const Size(0, AppSizes.minTouch),
                child: Text(
                  'スキップ',
                  style: AppTextStyles.actionLabel(context).copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
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
  int exerciseCount = 4,
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
    exercises: [
      for (var i = 0; i < exerciseCount; i++)
        WorkoutAssignmentExercise(
          id: 'preview-ex-$i',
          assignmentId: 'preview-id',
          exerciseName: '種目${i + 1}',
          targetSets: 3,
          targetReps: 10,
          orderIndex: i,
          isCompleted: false,
        ),
    ],
  );
}

Widget _previewOverdue(Brightness brightness, {double textScale = 1.0}) {
  final now = DateTime.now();
  final twoDaysAgo = now.subtract(const Duration(days: 2));
  final dateStr =
      '${twoDaysAgo.year}-${twoDaysAgo.month.toString().padLeft(2, '0')}-${twoDaysAgo.day.toString().padLeft(2, '0')}';
  return FcPreviewApp(
    brightness: brightness,
    textScale: textScale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: OverdueAssignmentCard(
            assignment: _makeOverdueAssignment(
              assignedDate: dateStr,
              title: '下半身',
            ),
            trainerName: '田中',
            onDoToday: () {},
            onSkip: () {},
            onReschedule: (_) {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'OverdueAssignmentCard')
Widget previewOverdueAssignmentCard() => _previewOverdue(Brightness.light);

@Preview(name: 'OverdueAssignmentCard - ダーク')
Widget previewOverdueAssignmentCardDark() => _previewOverdue(Brightness.dark);

@Preview(name: 'OverdueAssignmentCard - 文字特大 (1.35)')
Widget previewOverdueAssignmentCardLargeText() =>
    _previewOverdue(Brightness.light, textScale: 1.35);
