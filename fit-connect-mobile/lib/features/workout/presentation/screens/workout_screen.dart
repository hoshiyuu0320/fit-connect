import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/messages/data/message_repository.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_screen_state.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/overdue_assignment_card.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/reschedule_date_picker.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/weekly_mini_calendar.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_completion_overlay.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_exercise_card.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_progress_bar.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_completion_message.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_format.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// プランタブ（今日のプラン・日付が過ぎたプラン・今後の予定・完了の報告）。
///
/// 正本は `plan-screens.js` の `PlanScreen`（今日のプラン／完了を報告／プランがない日）。
/// - 見出し: eyebrow = 今日の日付、title =「プラン」
/// - 週ストリップ → 日付が過ぎたプラン（あれば）→ 今日のプラン（無ければ「今日のプランはありません」）→ 今後の予定（あれば）
/// - 完了の報告は、全種目が完了したら「完了を報告する」から開くボトムシートで行う（演出は出さない）
class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  /// 完了の報告シートを開く。送信はシートの「報告する」で行う（失敗したらシートに残って入力を保つ）
  Future<void> _handleOpenCompletionSheet(
    WorkoutAssignment assignment,
    String? trainerName,
  ) async {
    // 送信後にこの画面が閉じていても困らないよう、使うものは先に取り出しておく
    final clientId = ref.read(currentClientIdProvider);
    final trainerId = ref.read(currentTrainerIdProvider);
    final notifier = ref.read(workoutScreenNotifierProvider.notifier);

    await showWorkoutCompletionSheet(
      context,
      planTitle: assignment.planInfo?.title ?? 'ワークアウトプラン',
      exerciseCount: assignment.exercises.length,
      date: parseWorkoutAssignedDate(assignment.assignedDate),
      trainerName: trainerName,
      onSubmit: (feedback, calories) => _submitCompletion(
        assignment: assignment,
        feedback: feedback,
        calories: calories,
        clientId: clientId,
        trainerId: trainerId,
        notifier: notifier,
      ),
    );
  }

  /// 完了を記録して、トレーナーへ報告のメッセージを送る（既存の完了フローのまま）。
  /// 記録に失敗したら例外を投げる（シートがエラーを示す）。メッセージの送信失敗は記録を取り消さない。
  Future<void> _submitCompletion({
    required WorkoutAssignment assignment,
    required String? feedback,
    required int? calories,
    required String? clientId,
    required String? trainerId,
    required WorkoutScreenNotifier notifier,
  }) async {
    final planTitle = assignment.planInfo?.title ?? 'ワークアウトプラン';

    await notifier.submitCompletion(
      assignment.id,
      clientFeedback: feedback,
      calories: calories,
    );

    if (clientId != null && trainerId != null) {
      try {
        // 本文とタグは Web 側が解析する取り決め。組み立ては workout_completion_message.dart に固定してある
        final message = buildWorkoutCompletionMessage(
          planTitle: planTitle,
          feedback: feedback,
          calories: calories,
        );

        await MessageRepository().sendMessage(
          senderId: clientId,
          receiverId: trainerId,
          senderType: 'client',
          receiverType: 'trainer',
          content: message.content,
          tags: message.tags,
        );
      } catch (e) {
        debugPrint('[WorkoutScreen] メッセージ送信エラー: $e');
      }
    }
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
    final trainerName = ref.watch(trainerProfileProvider).valueOrNull?.name;

    final Widget body = screenStateAsync.when(
      loading: () => const _WorkoutLoading(),
      error: (e, _) => FcStateMessage.error(
        title: 'プランを読み込めませんでした',
        message: '通信状況を確認して、もう一度お試しください。',
        actionLabel: '再試行',
        actionIcon: LucideIcons.refreshCw,
        onAction: () => ref.invalidate(workoutScreenNotifierProvider),
      ),
      data: (screenState) => _WorkoutBody(
        state: screenState,
        trainerName: trainerName,
        onDoToday: _handleDoToday,
        onSkip: (id) =>
            ref.read(workoutScreenNotifierProvider.notifier).skip(id),
        onReschedule: _handleReschedule,
        onSetsUpdated: (aId, eId, sets) => ref
            .read(workoutScreenNotifierProvider.notifier)
            .updateExerciseSets(aId, eId, sets),
        onSubmit: (assignment) =>
            _handleOpenCompletionSheet(assignment, trainerName),
      ),
    );

    // 欄の外を押したらフォーカスを外す（重量・回数は欄を離れたときに保存されるため）
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: _WorkoutPage(today: today, child: body),
        ),
      ),
    );
  }
}

/// 見出し（今日の日付 ＋「プラン」）と本文を縦に並べるスクロール領域。
/// 内容は下部ナビ（すりガラス）の下まで潜れるようにする（`SafeArea(bottom: false)` を外側に置き、
/// 下余白に `MediaQuery.padding.bottom` を足す。ナビぶんの余白は別に足さない）。
/// スクロールの終端では、内容がナビの上（余白 28 を挟んで）に収まる。
class _WorkoutPage extends StatelessWidget {
  const _WorkoutPage({required this.today, required this.child});

  final DateTime today;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    return ListView(
      // 正本: 本文の上余白 4。下は、ナビ（FcBottomNavLayout）が確保する余白ぶん
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.xs,
        horizontal,
        MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        FcPageHeading(eyebrow: formatWorkoutLongDate(today), title: 'プラン'),
        child,
      ],
    );
  }
}

/// 読み込み中の仮表示（配置を保つ。点滅はさせない）
class _WorkoutLoading extends StatelessWidget {
  const _WorkoutLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '読み込み中',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 週ストリップ
            const FcSkeleton.card(height: 124),
            const SizedBox(height: AppSpacing.cardGap),
            // 今日のプラン
            const FcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FcSkeleton.line(width: 88),
                  SizedBox(height: AppSpacing.md),
                  FcSkeleton(width: 160, height: 26, radius: 8),
                  SizedBox(height: AppSpacing.sm),
                  FcSkeleton.line(width: 132),
                  SizedBox(height: AppSpacing.md),
                  FcSkeleton.line(),
                  SizedBox(height: AppSpacing.lg),
                  FcSkeleton(height: 4, radius: 2),
                ],
              ),
            ),
            // 種目
            for (var i = 0; i < 3; i++) ...[
              const SizedBox(height: AppSpacing.cardGap),
              const FcCard(
                paddingOverride:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    FcSkeleton.circle(size: 26),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FcSkeleton.line(width: 140),
                          SizedBox(height: AppSpacing.sm),
                          FcSkeleton.line(width: 104),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 読み込めたときの本文。ブロックの間は 16。
class _WorkoutBody extends StatelessWidget {
  const _WorkoutBody({
    required this.state,
    required this.trainerName,
    required this.onDoToday,
    required this.onSkip,
    required this.onReschedule,
    required this.onSetsUpdated,
    required this.onSubmit,
  });

  final WorkoutScreenState state;
  final String? trainerName;
  final void Function(String id) onDoToday;
  final void Function(String id) onSkip;
  final void Function(String id, DateTime date) onReschedule;
  final void Function(
          String assignmentId, String exerciseId, List<ActualSet> sets)
      onSetsUpdated;
  final void Function(WorkoutAssignment assignment) onSubmit;

  @override
  Widget build(BuildContext context) {
    final today = state.todayAssignments;

    final blocks = <Widget>[
      // 1. 週ストリップ
      WeeklyMiniCalendar(weeklyData: state.weeklyData),

      // 2. 日付が過ぎたプラン（ある場合のみ）
      if (state.overdueAssignments.isNotEmpty)
        _OverdueSection(
          assignments: state.overdueAssignments,
          trainerName: trainerName,
          onDoToday: onDoToday,
          onSkip: onSkip,
          onReschedule: onReschedule,
        ),

      // 3. 今日のプラン、または「今日のプランはありません」
      if (today.isEmpty)
        FcStateMessage.empty(
          title: '今日のプランはありません',
          message:
              '${trainerDisplayName(trainerName)}がプランを設定すると、ここに表示されます。',
        )
      else
        for (var i = 0; i < today.length; i++)
          Padding(
            // 今日のプランが複数あるときは、プランどうしを少し離す
            padding: EdgeInsets.only(top: i > 0 ? AppSpacing.sm : 0),
            child: _AssignmentSection(
              assignment: today[i],
              trainerName: trainerName,
              onSetsUpdated: onSetsUpdated,
              onSubmit: () => onSubmit(today[i]),
            ),
          ),

      // 4. 今後の予定（ある場合のみ）
      if (state.upcomingAssignments.isNotEmpty)
        _UpcomingSection(
          assignments: state.upcomingAssignments,
          trainerName: trainerName,
          onReschedule: onReschedule,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.cardGap),
          blocks[i],
        ],
      ],
    );
  }
}

/// 小見出し（アイコン 15 ＋ 13 の secondary 文字）。正本の `SubLabel`
/// （上 8・下 -4・左右 2。下の -4 は、直後のカードとの間を 16 → 12 に詰める）。
class _SubLabel extends StatelessWidget {
  const _SubLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  /// 直後のカードとの間（カード間 16 から、正本の下マージン -4 を引いた値）
  static const double gapAfter = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, AppSpacing.sm, 2, 0),
      child: Semantics(
        header: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 15, color: colors.textSecondary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: AppTextStyles.supplement(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 日付が過ぎたプラン
class _OverdueSection extends StatelessWidget {
  const _OverdueSection({
    required this.assignments,
    required this.trainerName,
    required this.onDoToday,
    required this.onSkip,
    required this.onReschedule,
  });

  final List<WorkoutAssignment> assignments;
  final String? trainerName;
  final void Function(String id) onDoToday;
  final void Function(String id) onSkip;
  final void Function(String id, DateTime date) onReschedule;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubLabel(
          icon: LucideIcons.calendarClock,
          text: '日付が過ぎたプラン（${assignments.length}件）',
        ),
        const SizedBox(height: _SubLabel.gapAfter),
        for (int i = 0; i < assignments.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.cardGap),
          OverdueAssignmentCard(
            assignment: assignments[i],
            trainerName: trainerName,
            onDoToday: () => onDoToday(assignments[i].id),
            onSkip: () => onSkip(assignments[i].id),
            onReschedule: (date) => onReschedule(assignments[i].id, date),
          ),
        ],
      ],
    );
  }
}

/// 今後の予定
class _UpcomingSection extends StatelessWidget {
  const _UpcomingSection({
    required this.assignments,
    required this.trainerName,
    required this.onReschedule,
  });

  final List<WorkoutAssignment> assignments;
  final String? trainerName;
  final void Function(String id, DateTime date) onReschedule;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubLabel(
          icon: LucideIcons.calendarDays,
          text: '今後の予定（${assignments.length}件）',
        ),
        const SizedBox(height: _SubLabel.gapAfter),
        FcCard(
          // 正本: 上下 2・左右 20（行の上下余白 10 が付く）
          paddingOverride:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < assignments.length; i++) ...[
                if (i > 0) const FcSeparator(),
                _UpcomingRow(
                  key: ValueKey(assignments[i].id),
                  assignment: assignments[i],
                  onReschedule: (date) =>
                      onReschedule(assignments[i].id, date),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 今後の予定の 1 行: 日付 13（幅 72）＋ タイトル 16/500 ＋「4種目」＋「日付を変更」。
/// 文字を大きくしたら、日付とタイトルの下に操作を置く（縮めない）。
class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({
    super.key,
    required this.assignment,
    required this.onReschedule,
  });

  final WorkoutAssignment assignment;
  final ValueChanged<DateTime> onReschedule;

  /// 日付の最小幅（正本 72）
  static const double _dateMinWidth = 72;

  /// これより文字が大きいとき（1.15 倍超）は、操作を次の行に置く
  static const double _stackedTextScale = 1.15;

  Future<void> _pickNewDate(BuildContext context) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => const RescheduleDatePicker(),
    );
    if (picked != null) onReschedule(picked);
  }

  @override
  Widget build(BuildContext context) {
    final title = assignment.planInfo?.title ?? 'ワークアウト';
    final exerciseCount = assignment.exercises.length;
    final date = parseWorkoutAssignedDate(assignment.assignedDate);
    final stacked =
        MediaQuery.textScalerOf(context).scale(100) / 100 > _stackedTextScale;

    final dateText = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _dateMinWidth),
      child: Text(
        formatWorkoutShortDate(date),
        style: AppTextStyles.supplement(context)
            .copyWith(fontFeatures: AppTextStyles.tabularFigures),
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.body(context)
              .copyWith(fontWeight: FontWeight.w500),
        ),
        Text('$exerciseCount種目', style: AppTextStyles.caption(context)),
      ],
    );
    final changeButton = FcButton.back(
      label: '日付を変更',
      icon: LucideIcons.calendar,
      iconPosition: FcIconPosition.start,
      onPressed: () => _pickNewDate(context),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    dateText,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: info),
                  ],
                ),
                changeButton,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                dateText,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: info),
                const SizedBox(width: AppSpacing.md),
                changeButton,
              ],
            ),
    );
  }
}

/// 今日の 1 件のプラン: プランのカード → 種目のカード → 完了の報告。
class _AssignmentSection extends StatelessWidget {
  const _AssignmentSection({
    required this.assignment,
    required this.trainerName,
    required this.onSetsUpdated,
    required this.onSubmit,
  });

  final WorkoutAssignment assignment;
  final String? trainerName;
  final void Function(
          String assignmentId, String exerciseId, List<ActualSet> sets)
      onSetsUpdated;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final exercises = assignment.exercises;
    final completedCount = exercises.where((e) => e.isCompleted).length;
    final totalCount = exercises.length;
    final isCompleted = assignment.status == 'completed';
    final allDone = completedCount == totalCount && totalCount > 0;

    // いま取り組む種目（最初の未完了）だけ最初から開いておく。報告済みなら開かない
    WorkoutAssignmentExercise? current;
    if (!isCompleted) {
      for (final e in exercises) {
        if (!e.isCompleted) {
          current = e;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodayPlanCard(
          assignment: assignment,
          trainerName: trainerName,
          completedCount: completedCount,
          totalCount: totalCount,
        ),
        for (final exercise in exercises) ...[
          const SizedBox(height: AppSpacing.cardGap),
          WorkoutExerciseCard(
            key: ValueKey(exercise.id),
            exerciseName: exercise.exerciseName,
            targetSets: exercise.targetSets,
            targetReps: exercise.targetReps,
            targetWeight: exercise.targetWeight,
            memo: exercise.memo,
            isCompleted: exercise.isCompleted,
            actualSets: exercise.actualSets,
            trainerName: trainerName,
            initiallyExpanded: exercise.id == current?.id,
            onSetsUpdated: (sets) =>
                onSetsUpdated(assignment.id, exercise.id, sets),
          ),
        ],
        const SizedBox(height: AppSpacing.cardGap),
        if (isCompleted)
          FcInlineNotice.success(
            message: assignment.calories == null
                ? '完了を報告しました。'
                : '完了を報告しました。消費カロリー ${assignment.calories} kcal',
          )
        else ...[
          FcButton.block(
            label: '完了を報告する',
            onPressed: allDone ? onSubmit : null,
          ),
          if (!allDone)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'すべての種目を終えると報告できます',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(context),
              ),
            ),
        ],
      ],
    );
  }
}

/// 今日のプランのカード（正本 `TodayPlan` の先頭のカード）:
/// 「今日のプラン」＋ dumbbell・プラン名 26・「{トレーナー} · 3種目」・説明・進み具合。
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard({
    required this.assignment,
    required this.trainerName,
    required this.completedCount,
    required this.totalCount,
  });

  final WorkoutAssignment assignment;
  final String? trainerName;
  final int completedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final planTitle = assignment.planInfo?.title ?? 'ワークアウトプラン';
    final description = assignment.planInfo?.description;

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 見出し行（左は文字だけ・右に dumbbell。FcCardHead は左のアイコンが必須のため、ここだけ自前）
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '今日のプラン',
                      style: AppTextStyles.label(context)
                          .copyWith(color: colors.accent, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ExcludeSemantics(
                  child: Icon(
                    LucideIcons.dumbbell,
                    size: AppSizes.icon,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          ),
          Text(planTitle, style: AppTextStyles.planName(context)),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '${trainerDisplayName(trainerName)} · $totalCount種目',
              style: AppTextStyles.label(context).copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                description,
                style: AppTextStyles.body(context).copyWith(height: 1.6),
              ),
            ),
          if (totalCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: WorkoutProgressBar(
                completed: completedCount,
                total: totalCount,
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

String _previewDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _previewDay(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset);
}

WorkoutAssignment _previewAssignment({
  required String id,
  required int dayOffset,
  required String title,
  required String status,
  String? description,
  required List<WorkoutAssignmentExercise> exercises,
}) {
  return WorkoutAssignment(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    planId: 'plan-$id',
    assignedDate: _previewDate(_previewDay(dayOffset)),
    status: status,
    planInfo: WorkoutPlanInfo(
      title: title,
      description: description,
      category: '筋トレ',
      planType: 'self_guided',
    ),
    exercises: exercises,
  );
}

WorkoutAssignmentExercise _previewExercise({
  required String id,
  required String name,
  required int sets,
  required int reps,
  double? weight,
  String? memo,
  bool done = false,
  List<ActualSet>? actual,
}) {
  return WorkoutAssignmentExercise(
    id: id,
    assignmentId: 'today',
    exerciseName: name,
    targetSets: sets,
    targetReps: reps,
    targetWeight: weight,
    orderIndex: 0,
    isCompleted: done,
    memo: memo,
    actualSets: actual,
  );
}

/// 今日のプランの見本。[allDone] なら全種目が完了（完了を報告できる）
WorkoutAssignment _previewTodayPlan({bool allDone = false}) {
  return _previewAssignment(
    id: 'today',
    dayOffset: 0,
    title: '上半身',
    status: 'pending',
    description: '肩の動きを確認しながら、ひとつずつ丁寧に。',
    exercises: [
      _previewExercise(
        id: 'ex-1',
        name: 'ダンベルプレス',
        sets: 3,
        reps: 10,
        weight: 12,
        done: true,
      ),
      _previewExercise(
        id: 'ex-2',
        name: 'ラットプルダウン',
        sets: 3,
        reps: 12,
        weight: 30,
        memo: '肘を後ろに引く意識で、反動を使わずに。',
        done: allDone,
        actual: const [
          ActualSet(setNumber: 1, reps: 12, weight: 30, done: true),
          ActualSet(setNumber: 2, reps: 12, weight: 30, done: true),
          ActualSet(setNumber: 3, reps: 0, weight: 30, done: false),
        ],
      ),
      _previewExercise(
        id: 'ex-3',
        name: 'シーテッドロー',
        sets: 3,
        reps: 12,
        weight: 25,
        done: allDone,
      ),
    ],
  );
}

WorkoutScreenState _previewState({
  bool allDone = false,
  bool withToday = true,
  bool withOverdue = true,
}) {
  final today = withToday ? _previewTodayPlan(allDone: allDone) : null;
  final overdue = _previewAssignment(
    id: 'overdue',
    dayOffset: -2,
    title: '下半身',
    status: 'pending',
    exercises: [
      for (var i = 0; i < 4; i++)
        _previewExercise(
          id: 'od-$i',
          name: '種目${i + 1}',
          sets: 3,
          reps: 10,
        ),
    ],
  );
  final upcoming = [
    _previewAssignment(
      id: 'up-1',
      dayOffset: 3,
      title: '全身',
      status: 'pending',
      exercises: [
        for (var i = 0; i < 4; i++)
          _previewExercise(id: 'u1-$i', name: '種目${i + 1}', sets: 3, reps: 10),
      ],
    ),
    _previewAssignment(
      id: 'up-2',
      dayOffset: 5,
      title: '下半身',
      status: 'pending',
      exercises: [
        for (var i = 0; i < 4; i++)
          _previewExercise(id: 'u2-$i', name: '種目${i + 1}', sets: 3, reps: 10),
      ],
    ),
  ];

  final todayDate = _previewDay(0);
  final monday = DateTime(
      todayDate.year, todayDate.month, todayDate.day - (todayDate.weekday - 1));
  DateTime at(int i) => DateTime(monday.year, monday.month, monday.day + i);
  final weekly = <DateTime, List<WorkoutAssignment>>{
    if (monday.isBefore(todayDate))
      monday: [
        _previewAssignment(
          id: 'w-0',
          dayOffset: -(todayDate.weekday - 1),
          title: '上半身',
          status: 'completed',
          exercises: const [],
        ),
      ],
    if (today != null) todayDate: [today],
    at(6): [upcoming.first],
  };

  return WorkoutScreenState(
    overdueAssignments: withOverdue ? [overdue] : const [],
    todayAssignments: today == null ? const [] : [today],
    upcomingAssignments: upcoming,
    weeklyData: weekly,
  );
}

Widget _previewWorkoutPage(
  Widget body, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: textScale,
    home: Scaffold(
      body: SafeArea(
        bottom: false,
        child: _WorkoutPage(today: DateTime.now(), child: body),
      ),
    ),
  );
}

Widget _previewBody(WorkoutScreenState state) => _WorkoutBody(
      state: state,
      trainerName: '田中',
      onDoToday: (_) {},
      onSkip: (_) {},
      onReschedule: (_, __) {},
      onSetsUpdated: (_, __, ___) {},
      onSubmit: (_) {},
    );

@Preview(name: 'WorkoutScreen - 今日のプラン')
Widget previewWorkoutScreenToday() =>
    _previewWorkoutPage(_previewBody(_previewState()));

@Preview(name: 'WorkoutScreen - 全種目完了（報告できる）')
Widget previewWorkoutScreenAllDone() => _previewWorkoutPage(
      _previewBody(_previewState(allDone: true, withOverdue: false)),
    );

@Preview(name: 'WorkoutScreen - プランがない日')
Widget previewWorkoutScreenEmpty() => _previewWorkoutPage(
      _previewBody(_previewState(withToday: false, withOverdue: false)),
    );

@Preview(name: 'WorkoutScreen - 読み込み中')
Widget previewWorkoutScreenLoading() =>
    _previewWorkoutPage(const _WorkoutLoading());

@Preview(name: 'WorkoutScreen - 読み込めない')
Widget previewWorkoutScreenError() => _previewWorkoutPage(
      FcStateMessage.error(
        title: 'プランを読み込めませんでした',
        message: '通信状況を確認して、もう一度お試しください。',
        actionLabel: '再試行',
        actionIcon: LucideIcons.refreshCw,
        onAction: () {},
      ),
    );

@Preview(name: 'WorkoutScreen - ダーク')
Widget previewWorkoutScreenDark() => _previewWorkoutPage(
      _previewBody(_previewState()),
      brightness: Brightness.dark,
    );

@Preview(name: 'WorkoutScreen - 文字特大 (1.35)')
Widget previewWorkoutScreenLargeText() => _previewWorkoutPage(
      _previewBody(_previewState()),
      textScale: 1.35,
    );
