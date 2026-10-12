import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_date_format.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'exercise_entry_card.dart';

/// 完了したプラン 1 件のカード。種別は「プランの完了」で、運動の記録と同じカードの形
/// （[ExerciseEntryCard]）。正本は `record-screens.js` の `ExRecord`（プランの完了の分）。
///
/// - 見出し: dumbbell「プランの完了」（右に完了した日。時刻は出さない）
/// - 題名: 「プラン名 · 4種目」。種目が登録されていなければプラン名だけ
/// - ノート: 完了報告に添えた感想（`clientFeedback`）。無ければ出さない
/// - 補足: 「消費 280 kcal」。消費カロリーの入力が無ければ補足の行ごと出さない
///
/// 以前は種目ごとの目標・実績のセットを一覧に並べていたが、正本の一覧には無いので出さない。
class CompletedWorkoutCard extends StatelessWidget {
  final WorkoutAssignment assignment;

  const CompletedWorkoutCard({super.key, required this.assignment});

  @override
  Widget build(BuildContext context) {
    return ExerciseEntryCard(
      icon: LucideIcons.dumbbell,
      type: 'プランの完了',
      time: recordDateLabel(completedWorkoutDate(assignment)),
      title: completedWorkoutTitle(assignment),
      note: assignment.clientFeedback,
      meta: completedWorkoutMeta(assignment),
    );
  }
}

/// 完了した日（完了日時があればその日、なければ予定日）
DateTime completedWorkoutDate(WorkoutAssignment assignment) {
  final finishedAt = assignment.finishedAt;
  if (finishedAt != null) return finishedAt;
  final parts = assignment.assignedDate.split('-');
  if (parts.length == 3) {
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year != null && month != null && day != null) {
      return DateTime(year, month, day);
    }
  }
  return DateTime.now();
}

/// 題名。例:「全身 · 4種目」
String completedWorkoutTitle(WorkoutAssignment assignment) {
  final name = assignment.planInfo?.title ?? 'ワークアウト';
  final count = assignment.exercises.length;
  return count > 0 ? '$name · $count種目' : name;
}

/// 補足。例:「消費 280 kcal」。消費カロリーの入力が無ければ null
String? completedWorkoutMeta(WorkoutAssignment assignment) {
  final calories = assignment.calories;
  if (calories == null) return null;
  return '消費 ${NumberFormat('#,###').format(calories)} kcal';
}

// ============================================
// Previews
// ============================================

Widget _previewApp(Brightness brightness, double textScale, Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
}

WorkoutAssignmentExercise _exercise(String id, String name, int order) =>
    WorkoutAssignmentExercise(
      id: id,
      assignmentId: 'assignment-1',
      exerciseName: name,
      targetSets: 3,
      targetReps: 10,
      orderIndex: order,
      isCompleted: true,
    );

final _mockAssignmentFull = WorkoutAssignment(
  id: 'assignment-1',
  clientId: 'client-1',
  trainerId: 'trainer-1',
  planId: 'plan-1',
  assignedDate: '2026-09-09',
  status: 'completed',
  finishedAt: DateTime(2026, 9, 9, 18, 40),
  calories: 280,
  clientFeedback: 'スクワットのフォームを意識できました。',
  planInfo: const WorkoutPlanInfo(
    title: '全身',
    category: '全身',
    estimatedMinutes: 45,
    planType: 'self_guided',
  ),
  exercises: [
    _exercise('e1', 'スクワット', 0),
    _exercise('e2', 'ベンチプレス', 1),
    _exercise('e3', 'ラットプルダウン', 2),
    _exercise('e4', 'プランク', 3),
  ],
);

final _mockAssignmentMinimal = WorkoutAssignment(
  id: 'assignment-2',
  clientId: 'client-1',
  trainerId: 'trainer-1',
  planId: 'plan-2',
  assignedDate: '2026-09-07',
  status: 'completed',
  planInfo: const WorkoutPlanInfo(
    title: '下半身',
    category: '脚',
    planType: 'self_guided',
  ),
  exercises: [_exercise('e5', 'レッグプレス', 0)],
);

Widget _previewCards() => Column(
      children: [
        CompletedWorkoutCard(assignment: _mockAssignmentFull),
        const SizedBox(height: 16),
        CompletedWorkoutCard(assignment: _mockAssignmentMinimal),
      ],
    );

@Preview(name: 'CompletedWorkoutCard - 通常')
Widget previewCompletedWorkoutCard() =>
    _previewApp(Brightness.light, 1, _previewCards());

@Preview(name: 'CompletedWorkoutCard - ダーク')
Widget previewCompletedWorkoutCardDark() =>
    _previewApp(Brightness.dark, 1, _previewCards());

@Preview(name: 'CompletedWorkoutCard - 文字拡大 1.35')
Widget previewCompletedWorkoutCardLargeText() =>
    _previewApp(Brightness.light, 1.35, _previewCards());
