import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/messages/data/message_repository.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/weekly_mini_calendar.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/overdue_assignment_card.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/reschedule_date_picker.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_exercise_card.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_progress_bar.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_completion_overlay.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  bool _showCompletionOverlay = false;
  String? _completedPlanTitle;

  Future<void> _handleSubmitCompletion(WorkoutAssignment assignment) async {
    final result = await showDialog<_FeedbackResult>(
      context: context,
      builder: (context) => const _FeedbackDialog(),
    );

    if (result == null) return;

    final feedback = result.feedback;
    final calories = result.calories;
    final planTitle = assignment.planInfo?.title ?? 'ワークアウトプラン';
    final clientId = ref.read(currentClientIdProvider);
    final trainerId = ref.read(currentTrainerIdProvider);

    await ref
        .read(workoutScreenNotifierProvider.notifier)
        .submitCompletion(
          assignment.id,
          clientFeedback: feedback,
          calories: calories,
        );

    if (clientId != null && trainerId != null) {
      try {
        final hasCalories = calories != null;
        final hasFeedback = feedback != null && feedback.isNotEmpty;

        String messageContent = '本日のワークアウトプラン「$planTitle」を達成しました！';
        if (hasCalories || hasFeedback) messageContent += '\n';
        if (hasCalories) messageContent += '\n🔥 消費カロリー: ${calories}kcal';
        if (hasFeedback) messageContent += '\n💬 $feedback';

        await MessageRepository().sendMessage(
          senderId: clientId,
          receiverId: trainerId,
          senderType: 'client',
          receiverType: 'trainer',
          content: messageContent,
          tags: ['#運動:完了'],
        );
      } catch (e) {
        debugPrint('[WorkoutScreen] メッセージ送信エラー: $e');
      }
    }

    setState(() {
      _completedPlanTitle = planTitle;
      _showCompletionOverlay = true;
    });
  }

  Future<void> _handleDoToday(String assignmentId) async {
    await ref.read(workoutScreenNotifierProvider.notifier).doToday(assignmentId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('今日に移動しました')),
    );
  }

  Future<void> _handleReschedule(String assignmentId, DateTime newDate) async {
    await ref
        .read(workoutScreenNotifierProvider.notifier)
        .reschedule(assignmentId, newDate);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${newDate.month}月${newDate.day}日に移動しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final screenStateAsync = ref.watch(workoutScreenNotifierProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('ワークアウト')),
        body: Stack(
          children: [
            screenStateAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'エラーが発生しました: $e',
                    style:
                        TextStyle(color: AppColors.of(context).textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (screenState) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 1. 週間ミニカレンダー
                    WeeklyMiniCalendar(weeklyData: screenState.weeklyData),
                    const SizedBox(height: 16),

                    // 2. 未完了セクション（overdueAssignments がある場合のみ）
                    if (screenState.overdueAssignments.isNotEmpty) ...[
                      _OverdueSection(
                        assignments: screenState.overdueAssignments,
                        onDoToday: _handleDoToday,
                        onSkip: (id) => ref
                            .read(workoutScreenNotifierProvider.notifier)
                            .skip(id),
                        onReschedule: _handleReschedule,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // 3. 日付ヘッダー
                    _DateHeader(today: today),
                    const SizedBox(height: 16),

                    // 4. 今日のワークアウト or 空状態
                    if (screenState.isEmpty) ...[
                      _EmptyState(),
                    ] else if (screenState.todayAssignments.isEmpty) ...[
                      _TodayEmptyHint(
                        hasOverdue:
                            screenState.overdueAssignments.isNotEmpty,
                      ),
                    ] else ...[
                      for (int i = 0;
                          i < screenState.todayAssignments.length;
                          i++) ...[
                        if (i > 0) const SizedBox(height: 24),
                        _AssignmentSection(
                          assignment: screenState.todayAssignments[i],
                          onSetsUpdated: (aId, eId, sets) => ref
                              .read(workoutScreenNotifierProvider.notifier)
                              .updateExerciseSets(aId, eId, sets),
                          onSubmit: () => _handleSubmitCompletion(
                              screenState.todayAssignments[i]),
                        ),
                      ],
                    ],

                    // 5. 今後の予定セクション（upcomingAssignments がある場合のみ）
                    if (screenState.upcomingAssignments.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _UpcomingSection(
                        assignments: screenState.upcomingAssignments,
                        onReschedule: _handleReschedule,
                      ),
                    ],
                  ],
                );
              },
            ),

            // 完了オーバーレイ
            if (_showCompletionOverlay)
              WorkoutCompletionOverlay(
                planTitle: _completedPlanTitle,
                onDismiss: () {
                  setState(() {
                    _showCompletionOverlay = false;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}

// 未完了セクションWidget
class _OverdueSection extends StatelessWidget {
  final List<WorkoutAssignment> assignments;
  final void Function(String id) onDoToday;
  final void Function(String id) onSkip;
  final void Function(String id, DateTime date) onReschedule;

  const _OverdueSection({
    required this.assignments,
    required this.onDoToday,
    required this.onSkip,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.alertTriangle,
                size: 16, color: AppColors.orange500),
            const SizedBox(width: 6),
            Text(
              '未完了のワークアウト (${assignments.length}件)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.orange800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < assignments.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          OverdueAssignmentCard(
            assignment: assignments[i],
            onDoToday: () => onDoToday(assignments[i].id),
            onSkip: () => onSkip(assignments[i].id),
            onReschedule: (date) => onReschedule(assignments[i].id, date),
          ),
        ],
      ],
    );
  }
}

// 今日のプランがない場合のヒントWidget
class _TodayEmptyHint extends StatelessWidget {
  final bool hasOverdue;

  const _TodayEmptyHint({this.hasOverdue = false});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendarCheck, size: 40, color: colors.textHint),
          const SizedBox(height: 12),
          Text(
            '今日のプランはありません',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colors.textHint,
            ),
          ),
          if (hasOverdue) ...[
            const SizedBox(height: 4),
            Text(
              '上の未完了プランを「今日やる」で\n実行できます',
              style: TextStyle(
                fontSize: 12,
                color: colors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// 今後の予定セクションWidget
class _UpcomingSection extends StatelessWidget {
  final List<WorkoutAssignment> assignments;
  final void Function(String id, DateTime date) onReschedule;

  const _UpcomingSection({
    required this.assignments,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.calendarClock,
                size: 16, color: AppColors.primary500),
            const SizedBox(width: 6),
            Text(
              '今後の予定 (${assignments.length}件)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < assignments.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _UpcomingAssignmentCard(
            key: ValueKey(assignments[i].id),
            assignment: assignments[i],
            onReschedule: (date) => onReschedule(assignments[i].id, date),
          ),
        ],
      ],
    );
  }
}

// 今後の予定カードWidget（コンパクト版）
class _UpcomingAssignmentCard extends StatelessWidget {
  final WorkoutAssignment assignment;
  final ValueChanged<DateTime> onReschedule;

  const _UpcomingAssignmentCard({
    super.key,
    required this.assignment,
    required this.onReschedule,
  });

  String _weekdayLabel(int weekday) {
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return labels[weekday - 1];
  }

  /// assigned_date（yyyy-MM-dd）を「M/d(E)」形式の日本語に整形
  String _formatAssignedDate(String dateStr) {
    final parts = dateStr.split('-');
    final dt = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    return '${dt.month}/${dt.day}(${_weekdayLabel(dt.weekday)})';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final title = assignment.planInfo?.title ?? 'ワークアウト';
    final exerciseCount = assignment.exercises.length;
    final formattedDate = _formatAssignedDate(assignment.assignedDate);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 日付チップ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surfaceDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              formattedDate,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // タイトル + 種目数
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$exerciseCount種目',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 日付変更アクション
          GestureDetector(
            onTap: () async {
              final picked = await showDialog<DateTime>(
                context: context,
                builder: (_) => const RescheduleDatePicker(),
              );
              if (picked != null) onReschedule(picked);
            },
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary500.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary500.withAlpha(50)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.calendarDays,
                      size: 16, color: AppColors.primary500),
                  const SizedBox(height: 4),
                  const Text(
                    '日付変更',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 日付ヘッダーWidget
class _DateHeader extends StatelessWidget {
  final DateTime today;

  const _DateHeader({required this.today});

  @override
  Widget build(BuildContext context) {
    return Text(
      '${today.year}年${today.month}月${today.day}日',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.of(context).textSecondary,
      ),
    );
  }
}

// 空状態Widget
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.calendarOff,
            size: 56,
            color: colors.textHint,
          ),
          const SizedBox(height: 16),
          Text(
            '本日のプランはありません',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colors.textHint,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'トレーナーがプランを設定すると\nここに表示されます',
            style: TextStyle(
              fontSize: 13,
              color: colors.textHint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// アサインメントセクションWidget
class _AssignmentSection extends StatelessWidget {
  final WorkoutAssignment assignment;
  final void Function(
          String assignmentId, String exerciseId, List<ActualSet> sets)
      onSetsUpdated;
  final VoidCallback onSubmit;

  const _AssignmentSection({
    required this.assignment,
    required this.onSetsUpdated,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final exercises = assignment.exercises;
    final completedCount = exercises.where((e) => e.isCompleted).length;
    final totalCount = exercises.length;
    final planTitle = assignment.planInfo?.title ?? 'ワークアウトプラン';
    final planDescription = assignment.planInfo?.description;
    final isCompleted = assignment.status == 'completed';
    final allDone = completedCount == totalCount && totalCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // プログレスバー
        WorkoutProgressBar(
          completed: completedCount,
          total: totalCount,
        ),
        const SizedBox(height: 16),

        // プランタイトル
        Text(
          planTitle,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),

        // プラン説明（あれば）
        if (planDescription != null && planDescription.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            planDescription,
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 12),

        // 種目カードリスト
        for (final exercise in exercises) ...[
          WorkoutExerciseCard(
            exerciseName: exercise.exerciseName,
            targetSets: exercise.targetSets,
            targetReps: exercise.targetReps,
            targetWeight: exercise.targetWeight,
            memo: exercise.memo,
            isCompleted: exercise.isCompleted,
            actualSets: exercise.actualSets,
            onSetsUpdated: (sets) =>
                onSetsUpdated(assignment.id, exercise.id, sets),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),

        // 完了報告ボタン
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (allDone && !isCompleted) ? onSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isCompleted
                  ? colors.border
                  : (allDone ? AppColors.emerald500 : colors.border),
              foregroundColor: isCompleted ? colors.textHint : Colors.white,
              disabledBackgroundColor: colors.border,
              disabledForegroundColor: colors.textHint,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              isCompleted ? '完了報告済み ✓' : '完了報告',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackResult {
  final String? feedback;
  final int? calories;
  const _FeedbackResult({this.feedback, this.calories});
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _controller = TextEditingController();
  final _caloriesController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('完了報告'),
      content: SingleChildScrollView(
        clipBehavior: Clip.none,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '感想やコンディションを入力してください（任意）',
              style: TextStyle(
                  fontSize: 14, color: AppColors.of(context).textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '例: 今日は調子が良かった！',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '消費カロリー（任意）',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _caloriesController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '例: 300',
                suffixText: 'kcal',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () {
            final caloriesText = _caloriesController.text.trim();
            final calories = caloriesText.isNotEmpty ? int.tryParse(caloriesText) : null;
            Navigator.of(context).pop(
              _FeedbackResult(
                feedback: _controller.text,
                calories: calories,
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.emerald500,
            foregroundColor: Colors.white,
          ),
          child: const Text('完了報告を送信'),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

// プレビュー用静的ヘルパーWidget群

class _PreviewDateHeaderStatic extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Text(
      '${today.year}年${today.month}月${today.day}日',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.of(context).textSecondary,
      ),
    );
  }
}

class _PreviewProgressBarStatic extends StatelessWidget {
  final int completed;
  final int total;

  const _PreviewProgressBarStatic({
    required this.completed,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return WorkoutProgressBar(completed: completed, total: total);
  }
}

class _PreviewExerciseListStatic extends StatelessWidget {
  final bool allCompleted;

  const _PreviewExerciseListStatic({this.allCompleted = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WorkoutExerciseCard(
          exerciseName: 'ベンチプレス',
          targetSets: 3,
          targetReps: 10,
          targetWeight: 60.0,
          isCompleted: allCompleted,
          actualSets: allCompleted
              ? [
                  const ActualSet(
                      setNumber: 1, reps: 10, weight: 60, done: true),
                  const ActualSet(
                      setNumber: 2, reps: 10, weight: 60, done: true),
                  const ActualSet(
                      setNumber: 3, reps: 10, weight: 60, done: true),
                ]
              : null,
          onSetsUpdated: (_) {},
        ),
        const SizedBox(height: 8),
        WorkoutExerciseCard(
          exerciseName: 'インクラインダンベルプレス',
          targetSets: 3,
          targetReps: 12,
          targetWeight: 22.5,
          memo: 'ゆっくりとしたテンポで',
          isCompleted: allCompleted,
          actualSets: allCompleted
              ? [
                  const ActualSet(
                      setNumber: 1, reps: 12, weight: 22.5, done: true),
                  const ActualSet(
                      setNumber: 2, reps: 12, weight: 22.5, done: true),
                  const ActualSet(
                      setNumber: 3, reps: 12, weight: 22.5, done: true),
                ]
              : null,
          onSetsUpdated: (_) {},
        ),
        const SizedBox(height: 8),
        WorkoutExerciseCard(
          exerciseName: 'ケーブルフライ',
          targetSets: 3,
          targetReps: 15,
          isCompleted: allCompleted,
          actualSets: allCompleted
              ? [
                  const ActualSet(
                      setNumber: 1, reps: 15, weight: 0, done: true),
                  const ActualSet(
                      setNumber: 2, reps: 15, weight: 0, done: true),
                  const ActualSet(
                      setNumber: 3, reps: 15, weight: 0, done: true),
                ]
              : null,
          onSetsUpdated: (_) {},
        ),
      ],
    );
  }
}

class _PreviewCompletionButtonStatic extends StatelessWidget {
  final bool enabled;
  final bool completed;

  const _PreviewCompletionButtonStatic({
    this.enabled = false,
    this.completed = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? () {} : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: completed
              ? AppColors.of(context).border
              : (enabled ? AppColors.emerald500 : AppColors.of(context).border),
          foregroundColor:
              completed ? AppColors.of(context).textHint : Colors.white,
          disabledBackgroundColor: AppColors.of(context).border,
          disabledForegroundColor: AppColors.of(context).textHint,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(
          completed ? '完了報告済み ✓' : '完了報告',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _PreviewWeeklyCalendar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
      );
    }

    final weeklyData = <DateTime, List<WorkoutAssignment>>{
      monday: [makeAssignment(monday, 'completed')],
      monday.add(const Duration(days: 2)): [
        makeAssignment(monday.add(const Duration(days: 2)), 'completed')
      ],
      monday.add(const Duration(days: 4)): [
        makeAssignment(monday.add(const Duration(days: 4)), 'pending')
      ],
    };

    return WeeklyMiniCalendar(weeklyData: weeklyData);
  }
}

class _PreviewOverdueSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final twoDaysAgo = now.subtract(const Duration(days: 2));
    final twoDaysAgoStr =
        '${twoDaysAgo.year}-${twoDaysAgo.month.toString().padLeft(2, '0')}-${twoDaysAgo.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.alertTriangle,
                size: 16, color: AppColors.orange500),
            const SizedBox(width: 6),
            const Text(
              '未完了のワークアウト (1件)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.orange800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OverdueAssignmentCard(
          assignment: WorkoutAssignment(
            id: 'preview-overdue-1',
            clientId: 'client-1',
            trainerId: 'trainer-1',
            planId: 'plan-1',
            assignedDate: twoDaysAgoStr,
            status: 'pending',
            planInfo: const WorkoutPlanInfo(
              title: '上半身トレーニング',
              category: '上半身',
              estimatedMinutes: 45,
            ),
          ),
          onDoToday: () {},
          onSkip: () {},
          onReschedule: (_) {},
        ),
      ],
    );
  }
}

class _PreviewUpcomingSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    WorkoutAssignment makeAssignment(int daysAhead, String title) {
      return WorkoutAssignment(
        id: 'preview-upcoming-$daysAhead',
        clientId: 'client-1',
        trainerId: 'trainer-1',
        planId: 'plan-1',
        assignedDate: fmt(now.add(Duration(days: daysAhead))),
        status: 'pending',
        planInfo: WorkoutPlanInfo(
          title: title,
          category: 'strength',
          estimatedMinutes: 45,
        ),
      );
    }

    return _UpcomingSection(
      assignments: [
        makeAssignment(3, '上半身トレーニング'),
        makeAssignment(9, '下半身トレーニング'),
      ],
      onReschedule: (_, __) {},
    );
  }
}

class _PreviewTodayEmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendarCheck, size: 40, color: colors.textHint),
          const SizedBox(height: 12),
          Text(
            '今日のプランはありません',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colors.textHint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '上の未完了プランを「今日やる」で\n実行できます',
            style: TextStyle(
              fontSize: 12,
              color: colors.textHint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

@Preview(name: 'WorkoutScreen - With Data')
Widget previewWorkoutScreenWithData() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(title: const Text('ワークアウト')),
      body: SafeArea(
        child: Builder(
          builder: (context) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PreviewWeeklyCalendar(),
              const SizedBox(height: 16),
              _PreviewDateHeaderStatic(),
              const SizedBox(height: 16),
              _PreviewProgressBarStatic(completed: 1, total: 3),
              const SizedBox(height: 16),
              Text(
                '上半身トレーニング',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.of(context).textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '胸・肩・上腕三頭筋を中心に鍛えるメニュー',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _PreviewExerciseListStatic(allCompleted: false),
              const SizedBox(height: 8),
              _PreviewCompletionButtonStatic(enabled: false),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutScreen - Empty State')
Widget previewWorkoutScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(title: const Text('ワークアウト')),
      body: SafeArea(
        child: Builder(
          builder: (context) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PreviewWeeklyCalendar(),
              const SizedBox(height: 16),
              _PreviewDateHeaderStatic(),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final colors = AppColors.of(context);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 64),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.calendarOff,
                          size: 56,
                          color: colors.textHint,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '本日のプランはありません',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: colors.textHint,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'トレーナーがプランを設定すると\nここに表示されます',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textHint,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutScreen - Completed')
Widget previewWorkoutScreenCompleted() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(title: const Text('ワークアウト')),
      body: SafeArea(
        child: Builder(
          builder: (context) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PreviewWeeklyCalendar(),
              const SizedBox(height: 16),
              _PreviewDateHeaderStatic(),
              const SizedBox(height: 16),
              _PreviewProgressBarStatic(completed: 3, total: 3),
              const SizedBox(height: 16),
              Text(
                '上半身トレーニング',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.of(context).textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '胸・肩・上腕三頭筋を中心に鍛えるメニュー',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _PreviewExerciseListStatic(allCompleted: true),
              const SizedBox(height: 8),
              _PreviewCompletionButtonStatic(enabled: false, completed: true),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutScreen - With Overdue')
Widget previewWorkoutScreenWithOverdue() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(title: const Text('ワークアウト')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 週間カレンダー
            _PreviewWeeklyCalendar(),
            const SizedBox(height: 16),

            // 未完了セクション
            _PreviewOverdueSection(),
            const SizedBox(height: 24),

            // 日付ヘッダー
            _PreviewDateHeaderStatic(),
            const SizedBox(height: 16),

            // 今日のプランなしヒント
            _PreviewTodayEmptyHint(),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutScreen - With Upcoming')
Widget previewWorkoutScreenWithUpcoming() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(title: const Text('ワークアウト')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 週間カレンダー
            _PreviewWeeklyCalendar(),
            const SizedBox(height: 16),

            // 日付ヘッダー
            _PreviewDateHeaderStatic(),
            const SizedBox(height: 16),

            // 今日のプランなしヒント
            _PreviewTodayEmptyHint(),

            // 今後の予定セクション
            const SizedBox(height: 24),
            _PreviewUpcomingSection(),
          ],
        ),
      ),
    ),
  );
}
