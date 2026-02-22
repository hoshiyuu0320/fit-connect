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
    // フィードバック入力ダイアログを表示
    final feedback = await showDialog<String>(
      context: context,
      builder: (context) => const _FeedbackDialog(),
    );

    // キャンセル時は何もしない
    if (feedback == null) return;

    final planTitle = assignment.planInfo?.title ?? 'ワークアウトプラン';
    final clientId = ref.read(currentClientIdProvider);
    final trainerId = ref.read(currentTrainerIdProvider);

    // DB更新（フィードバック付き）
    await ref
        .read(workoutScreenNotifierProvider.notifier)
        .submitCompletion(assignment.id, clientFeedback: feedback);

    // 通知メッセージ送信（タグなし）
    if (clientId != null && trainerId != null) {
      try {
        final messageContent = feedback.isNotEmpty
            ? '本日のワークアウトプラン「$planTitle」を達成しました！\n\n💬 $feedback'
            : '本日のワークアウトプラン「$planTitle」を達成しました！';

        await MessageRepository().sendMessage(
          senderId: clientId,
          receiverId: trainerId,
          senderType: 'client',
          receiverType: 'trainer',
          content: messageContent,
        );
      } catch (e) {
        // メッセージ送信失敗しても完了報告は成功として扱う
        debugPrint('[WorkoutScreen] メッセージ送信エラー: $e');
      }
    }

    setState(() {
      _completedPlanTitle = planTitle;
      _showCompletionOverlay = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final screenStateAsync = ref.watch(workoutScreenNotifierProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('ワークアウト')),
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            screenStateAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'エラーが発生しました: $e',
                    style: const TextStyle(color: AppColors.slate500),
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
                        onDoToday: (id) => ref
                            .read(workoutScreenNotifierProvider.notifier)
                            .doToday(id),
                        onSkip: (id) => ref
                            .read(workoutScreenNotifierProvider.notifier)
                            .skip(id),
                        onReschedule: (id, date) => ref
                            .read(workoutScreenNotifierProvider.notifier)
                            .reschedule(id, date),
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
                      _TodayEmptyHint(),
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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendarCheck, size: 40, color: AppColors.slate300),
          const SizedBox(height: 12),
          const Text(
            '今日のプランはありません',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.slate400,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '上の未完了プランを「今日やる」で\n実行できます',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.slate300,
            ),
            textAlign: TextAlign.center,
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
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.slate600,
      ),
    );
  }
}

// 空状態Widget
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.calendarOff,
            size: 56,
            color: AppColors.slate300,
          ),
          const SizedBox(height: 16),
          const Text(
            '本日のプランはありません',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.slate400,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'トレーナーがプランを設定すると\nここに表示されます',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.slate300,
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
  final void Function(String assignmentId, String exerciseId,
      List<ActualSet> sets) onSetsUpdated;
  final VoidCallback onSubmit;

  const _AssignmentSection({
    required this.assignment,
    required this.onSetsUpdated,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
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
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),

        // プラン説明（あれば）
        if (planDescription != null && planDescription.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            planDescription,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.slate500,
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
                  ? AppColors.slate200
                  : (allDone ? AppColors.emerald500 : AppColors.slate200),
              foregroundColor: isCompleted ? AppColors.slate400 : Colors.white,
              disabledBackgroundColor: AppColors.slate200,
              disabledForegroundColor: AppColors.slate400,
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

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
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
              style: const TextStyle(fontSize: 14, color: AppColors.slate500),
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
            const SizedBox(height: 2),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
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
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.slate600,
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
                  const ActualSet(setNumber: 1, reps: 10, weight: 60, done: true),
                  const ActualSet(setNumber: 2, reps: 10, weight: 60, done: true),
                  const ActualSet(setNumber: 3, reps: 10, weight: 60, done: true),
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
                  const ActualSet(setNumber: 1, reps: 15, weight: 0, done: true),
                  const ActualSet(setNumber: 2, reps: 15, weight: 0, done: true),
                  const ActualSet(setNumber: 3, reps: 15, weight: 0, done: true),
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
              ? AppColors.slate200
              : (enabled ? AppColors.emerald500 : AppColors.slate200),
          foregroundColor: completed ? AppColors.slate400 : Colors.white,
          disabledBackgroundColor: AppColors.slate200,
          disabledForegroundColor: AppColors.slate400,
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

class _PreviewTodayEmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendarCheck, size: 40, color: AppColors.slate300),
          const SizedBox(height: 12),
          const Text(
            '今日のプランはありません',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.slate400,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '上の未完了プランを「今日やる」で\n実行できます',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.slate300,
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PreviewWeeklyCalendar(),
            const SizedBox(height: 16),
            _PreviewDateHeaderStatic(),
            const SizedBox(height: 16),
            _PreviewProgressBarStatic(completed: 1, total: 3),
            const SizedBox(height: 16),
            const Text(
              '上半身トレーニング',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '胸・肩・上腕三頭筋を中心に鍛えるメニュー',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.slate500,
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
  );
}

@Preview(name: 'WorkoutScreen - Empty State')
Widget previewWorkoutScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(title: const Text('ワークアウト')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PreviewWeeklyCalendar(),
            const SizedBox(height: 16),
            _PreviewDateHeaderStatic(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.calendarOff,
                    size: 56,
                    color: AppColors.slate300,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '本日のプランはありません',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.slate400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'トレーナーがプランを設定すると\nここに表示されます',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.slate300,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PreviewWeeklyCalendar(),
            const SizedBox(height: 16),
            _PreviewDateHeaderStatic(),
            const SizedBox(height: 16),
            _PreviewProgressBarStatic(completed: 3, total: 3),
            const SizedBox(height: 16),
            const Text(
              '上半身トレーニング',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '胸・肩・上腕三頭筋を中心に鍛えるメニュー',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.slate500,
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
  );
}

@Preview(name: 'WorkoutScreen - With Overdue')
Widget previewWorkoutScreenWithOverdue() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(title: const Text('ワークアウト')),
      backgroundColor: AppColors.background,
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
