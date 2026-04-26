import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/goals/data/goal_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';

part 'goal_provider.g.dart';

/// GoalRepositoryのProvider
@riverpod
GoalRepository goalRepository(GoalRepositoryRef ref) {
  return GoalRepository();
}

/// 現在の目標情報を取得するProvider
@riverpod
Future<Client?> currentGoal(CurrentGoalRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return null;

  final repository = ref.watch(goalRepositoryProvider);
  return repository.getClientGoal(clientId);
}

/// 目標達成率を計算するProvider
@riverpod
Future<double> achievementRate(AchievementRateRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  final latestWeight = await ref.watch(latestWeightRecordProvider.future);

  if (clientId == null || latestWeight == null) return 0.0;

  final repository = ref.watch(goalRepositoryProvider);
  return repository.calculateAchievementRate(
    clientId: clientId,
    currentWeight: latestWeight.weight,
  );
}

/// 目標達成判定を行うProvider
@riverpod
Future<bool> isGoalAchieved(IsGoalAchievedRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  final latestWeight = await ref.watch(latestWeightRecordProvider.future);

  if (clientId == null || latestWeight == null) return false;

  final repository = ref.watch(goalRepositoryProvider);
  return repository.checkGoalAchievement(
    clientId: clientId,
    currentWeight: latestWeight.weight,
  );
}

/// 目標達成までの残り体重を計算するProvider
@riverpod
Future<double?> remainingWeight(RemainingWeightRef ref) async {
  final goal = await ref.watch(currentGoalProvider.future);
  final latestWeight = await ref.watch(latestWeightRecordProvider.future);

  if (goal == null || latestWeight == null) return null;

  final repository = ref.watch(goalRepositoryProvider);
  return repository.getRemainingWeight(goal, latestWeight.weight);
}

/// 開始時からの変化量を計算するProvider
@riverpod
Future<double?> weightChangeFromStart(WeightChangeFromStartRef ref) async {
  final goal = await ref.watch(currentGoalProvider.future);
  final latestWeight = await ref.watch(latestWeightRecordProvider.future);

  if (goal == null || latestWeight == null) return null;

  final repository = ref.watch(goalRepositoryProvider);
  return repository.getWeightChange(goal, latestWeight.weight);
}

/// 目標達成までの残り日数を取得するProvider
@riverpod
Future<int?> daysUntilDeadline(DaysUntilDeadlineRef ref) async {
  final goal = await ref.watch(currentGoalProvider.future);
  if (goal == null) return null;

  final repository = ref.watch(goalRepositoryProvider);
  return repository.getDaysUntilDeadline(goal);
}
