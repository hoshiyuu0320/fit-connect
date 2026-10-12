import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_sheet_handle.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_format.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 今週のプランの週ストリップ（正本 `plan-screens.js` の `PlanWeek`）。
///
/// カード（余白 上14・左右10・下10）に、曜日・日付・印の 7 日（`FcWeekStrip`）と、下に凡例
/// （「完了 / 予定 / 日付が過ぎた」）。印は 完了 = 完了マーク（16）／予定 = 塗りの点／
/// 日付が過ぎた = 中抜きの点。今日は選択中の見た目（surfaceSecondary の円 + accent）。
/// プランのある日を押すと、その日のプランの詳細（閲覧専用）をボトムシートで開く
/// （プランのない日は押せず、ボタンとしても読み上げない）。
class WeeklyMiniCalendar extends StatelessWidget {
  const WeeklyMiniCalendar({
    super.key,
    required this.weeklyData,
    this.today,
  });

  final Map<DateTime, List<WorkoutAssignment>> weeklyData;

  /// 「今日」とみなす日（省略すると本物の今日）。テスト・プレビューで日付を固定するためのもの
  final DateTime? today;

  /// カードの余白（正本: 上14・左右10・下10。トークンに無いのでここだけの定数）
  static const EdgeInsets _cardPadding = EdgeInsets.fromLTRB(10, 14, 10, 10);

  /// 日付だけの [DateTime]（時刻・夏時間の影響を受けない）
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 今週の月曜日を返す
  DateTime _getThisMonday(DateTime today) {
    // weekday: 1=月, 7=日。日数の引き算は DateTime のコンストラクタで行い、夏時間でずれないようにする
    return DateTime(today.year, today.month, today.day - (today.weekday - 1));
  }

  /// weeklyDataのキーを date-only の DateTime で比較する
  List<WorkoutAssignment>? _assignmentsForDay(DateTime day) {
    for (final entry in weeklyData.entries) {
      if (_dateOnly(entry.key) == day) return entry.value;
    }
    return null;
  }

  /// その日の印と状態名。最初のアサインメントの状態で決める（複数あっても 1 つの印）。
  /// - 完了 → 完了マーク
  /// - 予定（今日以降の未実施）→ 塗りの点
  /// - 日付が過ぎた（過去の未実施）→ 中抜きの点
  /// - スキップ・プランなし → 印なし（スキップは日付を押すと詳細で分かる）
  ({FcDayMark mark, Widget? markWidget, String? status}) _resolveMark(
    List<WorkoutAssignment>? assignments,
    DateTime today,
  ) {
    if (assignments == null || assignments.isEmpty) {
      return (mark: FcDayMark.none, markWidget: null, status: null);
    }
    final first = assignments.first;
    switch (first.status) {
      case 'completed':
        return (
          mark: FcDayMark.none,
          markWidget: const FcDoneMark(done: true, size: 16),
          status: '完了',
        );
      case 'pending':
        final assigned = parseWorkoutAssignedDate(first.assignedDate);
        final passed = assigned.isBefore(today);
        return (
          mark: passed ? FcDayMark.hollow : FcDayMark.filled,
          markWidget: null,
          status: passed ? '日付が過ぎた' : '予定',
        );
      case 'skipped':
        return (mark: FcDayMark.none, markWidget: null, status: 'スキップ');
      default:
        return (mark: FcDayMark.none, markWidget: null, status: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(this.today ?? DateTime.now());
    final monday = _getThisMonday(today);

    final days = <FcWeekDay>[];
    for (var i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final isToday = day == today;
      final resolved = _resolveMark(_assignmentsForDay(day), today);
      days.add(
        FcWeekDay(
          date: day,
          mark: resolved.mark,
          markWidget: resolved.markWidget,
          selected: isToday,
          today: isToday,
          semanticLabel: [
            '${day.month}月${day.day}日 ${workoutWeekdayLabel(day)}曜日',
            if (isToday) '今日',
            if (resolved.status != null) resolved.status!,
          ].join('、'),
        ),
      );
    }

    return FcCard(
      paddingOverride: _cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 7 日を等幅で並べる。押すと詳細が開くのはプランのある日だけなので、
          // その日だけボタンにする（`FcWeekStrip` は onSelect が null だと表示専用になるため、1 日ずつ置く）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final day in days)
                Expanded(
                  child: FcWeekStrip(
                    days: [day],
                    onSelect: _hasAssignments(day.date)
                        ? (date) => _showDayDetail(
                              context,
                              date,
                              _assignmentsForDay(_dateOnly(date))!,
                            )
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const _WeekLegend(),
        ],
      ),
    );
  }

  /// その日にプランがあるか（あれば押して詳細を開ける）
  bool _hasAssignments(DateTime day) {
    final assignments = _assignmentsForDay(_dateOnly(day));
    return assignments != null && assignments.isNotEmpty;
  }

  void _showDayDetail(
    BuildContext context,
    DateTime day,
    List<WorkoutAssignment> assignments,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DayDetailSheet(
        dateLabel: formatWorkoutLongDate(day),
        assignments: assignments,
      ),
    );
  }
}

/// 週ストリップの凡例（中央・間 16・caption）。印は読み上げ対象外で、文字だけを読み上げる。
class _WeekLegend extends StatelessWidget {
  const _WeekLegend();

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.caption(context);

    Widget item(Widget mark, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: mark),
          // 正本は印と文字の間 5
          const SizedBox(width: 5),
          Text(label, style: style),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        item(const FcDoneMark(done: true, size: 12), '完了'),
        item(const FcDot(), '予定'),
        item(const FcDot(filled: false), '日付が過ぎた'),
      ],
    );
  }
}

/// 日付タップ時に表示するボトムシート（閲覧専用）。
///
/// 日付（20/500）の下に、その日のプランを 1 件ずつ（プラン名・状態・カテゴリと所要時間・説明・種目）。
/// 状態は色ではなく文字（完了 / 予定 / スキップ）で示し、種目の完了は完了マークで示す。
class _DayDetailSheet extends StatelessWidget {
  const _DayDetailSheet({
    required this.dateLabel,
    required this.assignments,
  });

  final String dateLabel;
  final List<WorkoutAssignment> assignments;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = math.max(
      AppSpacing.xl,
      MediaQuery.paddingOf(context).bottom,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        10,
        AppSpacing.pageHorizontal,
        bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WorkoutSheetHandle(),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              dateLabel,
              style: AppTextStyles.sectionHeading(context),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < assignments.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: AppSpacing.md),
              const FcSeparator(),
              const SizedBox(height: AppSpacing.md),
            ],
            _AssignmentDetail(assignment: assignments[i]),
          ],
        ],
      ),
    );
  }
}

class _AssignmentDetail extends StatelessWidget {
  const _AssignmentDetail({required this.assignment});

  final WorkoutAssignment assignment;

  (String, FcPillTone) _status(String status) {
    switch (status) {
      case 'completed':
        return ('完了', FcPillTone.strong);
      case 'skipped':
        return ('スキップ', FcPillTone.muted);
      case 'pending':
        return ('予定', FcPillTone.neutral);
      default:
        return (status, FcPillTone.muted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final plan = assignment.planInfo;
    final title = plan?.title ?? 'ワークアウト';
    final (statusLabel, statusTone) = _status(assignment.status);
    final category = plan?.category ?? '';
    final minutes = plan?.estimatedMinutes;
    final description = plan?.description;

    Widget meta(IconData icon, String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 14, color: colors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(text, style: AppTextStyles.supplement(context)),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.body(context)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FcPill(statusLabel, tone: statusTone),
          ],
        ),
        if (category.isNotEmpty || minutes != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: 2,
              children: [
                if (category.isNotEmpty) meta(LucideIcons.tag, category),
                if (minutes != null) meta(LucideIcons.clock, '$minutes分'),
              ],
            ),
          ),
        if (description != null && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(description, style: AppTextStyles.supplement(context)),
          ),
        if (assignment.exercises.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: FcInfoBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < assignment.exercises.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    _ExerciseDetail(exercise: assignment.exercises[i]),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ExerciseDetail extends StatelessWidget {
  const _ExerciseDetail({required this.exercise});

  final WorkoutAssignmentExercise exercise;

  String _target() {
    final base = '${exercise.targetSets}セット × ${exercise.targetReps}回';
    final weight = exercise.targetWeight;
    if (weight == null) return base;
    return '$base · ${formatWorkoutWeight(weight)} kg';
  }

  String _actualSet(ActualSet set) {
    final weight =
        set.weight > 0 ? '${formatWorkoutWeight(set.weight)} kg × ' : '';
    return 'セット${set.setNumber}: $weight${set.reps}回${set.done ? '' : '（未完了）'}';
  }

  @override
  Widget build(BuildContext context) {
    final actualSets = exercise.actualSets ?? const <ActualSet>[];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: FcDoneMark(done: exercise.isCompleted, size: 18),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exercise.exerciseName,
                style: AppTextStyles.label(context)
                    .copyWith(fontWeight: FontWeight.w500, height: 1.5),
              ),
              Text(_target(), style: AppTextStyles.supplement(context)),
              for (final set in actualSets)
                Text(_actualSet(set), style: AppTextStyles.caption(context)),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

Map<DateTime, List<WorkoutAssignment>> _buildPreviewWeeklyData() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));

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
        title: '上半身',
        description: '肩の動きを確認しながら、ひとつずつ丁寧に。',
        category: '筋トレ',
        estimatedMinutes: 45,
      ),
      exercises: [
        WorkoutAssignmentExercise(
          id: 'ex-preview-1',
          assignmentId: 'preview-${day.day}',
          exerciseName: 'ダンベルプレス',
          targetSets: 3,
          targetReps: 10,
          targetWeight: 12.0,
          orderIndex: 0,
          isCompleted: status == 'completed',
          actualSets: status == 'completed'
              ? const [
                  ActualSet(setNumber: 1, reps: 10, weight: 12.0, done: true),
                  ActualSet(setNumber: 2, reps: 10, weight: 12.0, done: true),
                  ActualSet(setNumber: 3, reps: 8, weight: 12.0, done: true),
                ]
              : null,
        ),
        WorkoutAssignmentExercise(
          id: 'ex-preview-2',
          assignmentId: 'preview-${day.day}',
          exerciseName: 'ラットプルダウン',
          targetSets: 3,
          targetReps: 12,
          targetWeight: 30.0,
          orderIndex: 1,
          isCompleted: false,
        ),
      ],
    );
  }

  DateTime at(int offset) =>
      DateTime(monday.year, monday.month, monday.day + offset);

  return {
    at(0): [makeAssignment(at(0), 'completed')],
    at(2): [makeAssignment(at(2), 'completed')],
    at(3): [makeAssignment(at(3), 'pending')],
    at(4): [makeAssignment(at(4), 'pending')],
    at(5): [makeAssignment(at(5), 'skipped')],
  };
}

Widget _previewCalendar(Brightness brightness, {double textScale = 1.0}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: textScale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: WeeklyMiniCalendar(weeklyData: _buildPreviewWeeklyData()),
        ),
      ),
    ),
  );
}

@Preview(name: 'WeeklyMiniCalendar - With Data')
Widget previewWeeklyMiniCalendar() => _previewCalendar(Brightness.light);

@Preview(name: 'WeeklyMiniCalendar - With Data (Dark)')
Widget previewWeeklyMiniCalendarDark() => _previewCalendar(Brightness.dark);

@Preview(name: 'WeeklyMiniCalendar - 文字特大 (1.35)')
Widget previewWeeklyMiniCalendarLargeText() =>
    _previewCalendar(Brightness.light, textScale: 1.35);

@Preview(name: 'DayDetailSheet - 完了')
Widget previewDayDetailSheetCompleted() {
  final data = _buildPreviewWeeklyData();
  final first = data.entries.first;
  return FcPreviewApp(
    brightness: Brightness.light,
    home: Scaffold(
      body: SafeArea(
        child: _DayDetailSheet(
          dateLabel: formatWorkoutLongDate(first.key),
          assignments: first.value,
        ),
      ),
    ),
  );
}

@Preview(name: 'DayDetailSheet - 予定')
Widget previewDayDetailSheetPending() {
  final data = _buildPreviewWeeklyData();
  final entry = data.entries.firstWhere(
    (e) => e.value.first.status == 'pending',
  );
  return FcPreviewApp(
    brightness: Brightness.dark,
    home: Scaffold(
      body: SafeArea(
        child: _DayDetailSheet(
          dateLabel: formatWorkoutLongDate(entry.key),
          assignments: entry.value,
        ),
      ),
    ),
  );
}
