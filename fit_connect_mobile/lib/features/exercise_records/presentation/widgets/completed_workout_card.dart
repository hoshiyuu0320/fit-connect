import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_exercise_model.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:lucide_icons/lucide_icons.dart';

class CompletedWorkoutCard extends StatelessWidget {
  final WorkoutAssignment assignment;

  const CompletedWorkoutCard({super.key, required this.assignment});

  String _formatWeight(double weight) {
    if (weight == weight.truncateToDouble()) {
      return weight.toInt().toString();
    }
    return weight.toString();
  }

  @override
  Widget build(BuildContext context) {
    final plan = assignment.planInfo;
    final exercises = List<WorkoutAssignmentExercise>.from(assignment.exercises)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(plan),

          // Divider
          const Divider(height: 1, thickness: 1, color: AppColors.slate100),

          // Exercise Sections
          if (exercises.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: exercises
                    .map((exercise) => _buildExerciseSection(exercise))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(WorkoutPlanInfo? plan) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.emerald100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('🏋️', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              // Title
              Expanded(
                child: Text(
                  plan?.title ?? 'ワークアウト',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Completed Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.emerald100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.checkCircle2,
                      size: 12,
                      color: AppColors.emerald600,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '完了',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.emerald600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (plan != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  plan.category,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
                if (plan.estimatedMinutes != null) ...[
                  const Text(
                    ' • ',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.slate400,
                    ),
                  ),
                  Icon(LucideIcons.clock,
                      size: 12, color: AppColors.slate400),
                  const SizedBox(width: 3),
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
        ],
      ),
    );
  }

  Widget _buildExerciseSection(WorkoutAssignmentExercise exercise) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exercise name + completion badge
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.exerciseName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildExerciseBadge(exercise.isCompleted),
            ],
          ),
          const SizedBox(height: 6),

          // Target row
          _buildTargetRow(exercise),

          // Actual sets
          if (exercise.actualSets != null &&
              exercise.actualSets!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 1, color: AppColors.slate200),
            const SizedBox(height: 8),
            ...exercise.actualSets!.map((set) => _buildActualSetRow(set)),
          ],
        ],
      ),
    );
  }

  Widget _buildExerciseBadge(bool isCompleted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isCompleted ? AppColors.emerald100 : AppColors.slate100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isCompleted ? '✅' : '⬜',
            style: const TextStyle(fontSize: 10),
          ),
          const SizedBox(width: 3),
          Text(
            isCompleted ? '完了' : '未完了',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isCompleted ? AppColors.emerald600 : AppColors.slate500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetRow(WorkoutAssignmentExercise exercise) {
    final parts = <String>[
      '${exercise.targetSets}セット × ${exercise.targetReps}回',
    ];
    if (exercise.targetWeight != null) {
      parts.add('× ${_formatWeight(exercise.targetWeight!)}kg');
    }

    return Row(
      children: [
        Icon(LucideIcons.target, size: 11, color: AppColors.slate400),
        const SizedBox(width: 4),
        Text(
          '目標: ${parts.join(' ')}',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.slate500,
          ),
        ),
      ],
    );
  }

  Widget _buildActualSetRow(ActualSet set) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              'Set ${set.setNumber}:',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.slate600,
              ),
            ),
          ),
          Text(
            '${_formatWeight(set.weight)}kg × ${set.reps}回',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.slate700,
            ),
          ),
          if (set.done) ...[
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.check,
              size: 12,
              color: AppColors.emerald500,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

final _mockAssignmentWithSets = WorkoutAssignment(
  id: 'assignment-1',
  clientId: 'client-1',
  trainerId: 'trainer-1',
  planId: 'plan-1',
  assignedDate: '2026-02-22',
  status: 'completed',
  finishedAt: DateTime(2026, 2, 22, 11, 30),
  planInfo: const WorkoutPlanInfo(
    title: '大胸筋の強化',
    description: '胸筋メインのトレーニング',
    category: '胸',
    estimatedMinutes: 60,
    planType: 'self_guided',
  ),
  exercises: [
    WorkoutAssignmentExercise(
      id: 'ex-1',
      assignmentId: 'assignment-1',
      exerciseName: 'インクラインダンベルベンチ',
      targetSets: 3,
      targetReps: 10,
      targetWeight: 60.0,
      orderIndex: 0,
      isCompleted: true,
      actualSets: const [
        ActualSet(setNumber: 1, reps: 11, weight: 60.0, done: true),
        ActualSet(setNumber: 2, reps: 8, weight: 70.0, done: true),
        ActualSet(setNumber: 3, reps: 10, weight: 60.0, done: true),
      ],
    ),
    WorkoutAssignmentExercise(
      id: 'ex-2',
      assignmentId: 'assignment-1',
      exerciseName: 'ダンベルフライ',
      targetSets: 3,
      targetReps: 12,
      targetWeight: 15.5,
      orderIndex: 1,
      isCompleted: true,
      actualSets: const [
        ActualSet(setNumber: 1, reps: 12, weight: 15.5, done: true),
        ActualSet(setNumber: 2, reps: 12, weight: 15.5, done: true),
        ActualSet(setNumber: 3, reps: 10, weight: 15.5, done: true),
      ],
    ),
    WorkoutAssignmentExercise(
      id: 'ex-3',
      assignmentId: 'assignment-1',
      exerciseName: 'プッシュアップ',
      targetSets: 3,
      targetReps: 20,
      targetWeight: null,
      orderIndex: 2,
      isCompleted: false,
      actualSets: const [
        ActualSet(setNumber: 1, reps: 18, weight: 0, done: true),
        ActualSet(setNumber: 2, reps: 15, weight: 0, done: true),
      ],
    ),
  ],
);

final _mockAssignmentNoSets = WorkoutAssignment(
  id: 'assignment-2',
  clientId: 'client-1',
  trainerId: 'trainer-1',
  planId: 'plan-2',
  assignedDate: '2026-02-21',
  status: 'completed',
  finishedAt: DateTime(2026, 2, 21, 10, 0),
  planInfo: const WorkoutPlanInfo(
    title: '下半身強化メニュー',
    category: '脚',
    estimatedMinutes: 45,
    planType: 'self_guided',
  ),
  exercises: [
    WorkoutAssignmentExercise(
      id: 'ex-4',
      assignmentId: 'assignment-2',
      exerciseName: 'バーベルスクワット',
      targetSets: 4,
      targetReps: 8,
      targetWeight: 80.0,
      orderIndex: 0,
      isCompleted: true,
    ),
    WorkoutAssignmentExercise(
      id: 'ex-5',
      assignmentId: 'assignment-2',
      exerciseName: 'レッグプレス',
      targetSets: 3,
      targetReps: 12,
      targetWeight: 120.0,
      orderIndex: 1,
      isCompleted: true,
    ),
  ],
);

@Preview(name: 'CompletedWorkoutCard - With Sets')
Widget previewCompletedWorkoutCardWithSets() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CompletedWorkoutCard(assignment: _mockAssignmentWithSets),
        ),
      ),
    ),
  );
}

@Preview(name: 'CompletedWorkoutCard - No Sets')
Widget previewCompletedWorkoutCardNoSets() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CompletedWorkoutCard(assignment: _mockAssignmentNoSets),
        ),
      ),
    ),
  );
}
