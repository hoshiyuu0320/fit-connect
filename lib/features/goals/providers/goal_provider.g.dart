// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$goalRepositoryHash() => r'1253149613e20c2e481f4893f895de0477eac768';

/// GoalRepositoryのProvider
///
/// Copied from [goalRepository].
@ProviderFor(goalRepository)
final goalRepositoryProvider = AutoDisposeProvider<GoalRepository>.internal(
  goalRepository,
  name: r'goalRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$goalRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GoalRepositoryRef = AutoDisposeProviderRef<GoalRepository>;
String _$currentGoalHash() => r'754fb2bcef76c8d42d5dd2716f7569e937294af6';

/// 現在の目標情報を取得するProvider
///
/// Copied from [currentGoal].
@ProviderFor(currentGoal)
final currentGoalProvider = AutoDisposeFutureProvider<Client?>.internal(
  currentGoal,
  name: r'currentGoalProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$currentGoalHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CurrentGoalRef = AutoDisposeFutureProviderRef<Client?>;
String _$achievementRateHash() => r'b823d563b5b814a1a41fda03cb10af2ba45b74fd';

/// 目標達成率を計算するProvider
///
/// Copied from [achievementRate].
@ProviderFor(achievementRate)
final achievementRateProvider = AutoDisposeFutureProvider<double>.internal(
  achievementRate,
  name: r'achievementRateProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$achievementRateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AchievementRateRef = AutoDisposeFutureProviderRef<double>;
String _$isGoalAchievedHash() => r'736daa6637f82ceba6d800f9922862ec0696e998';

/// 目標達成判定を行うProvider
///
/// Copied from [isGoalAchieved].
@ProviderFor(isGoalAchieved)
final isGoalAchievedProvider = AutoDisposeFutureProvider<bool>.internal(
  isGoalAchieved,
  name: r'isGoalAchievedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$isGoalAchievedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsGoalAchievedRef = AutoDisposeFutureProviderRef<bool>;
String _$remainingWeightHash() => r'caa1e453b53b0721441f9693153a8def051e6f15';

/// 目標達成までの残り体重を計算するProvider
///
/// Copied from [remainingWeight].
@ProviderFor(remainingWeight)
final remainingWeightProvider = AutoDisposeFutureProvider<double?>.internal(
  remainingWeight,
  name: r'remainingWeightProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$remainingWeightHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RemainingWeightRef = AutoDisposeFutureProviderRef<double?>;
String _$weightChangeFromStartHash() =>
    r'cbe74a68c1df897e58b6275c87d17767c6d2a64e';

/// 開始時からの変化量を計算するProvider
///
/// Copied from [weightChangeFromStart].
@ProviderFor(weightChangeFromStart)
final weightChangeFromStartProvider =
    AutoDisposeFutureProvider<double?>.internal(
  weightChangeFromStart,
  name: r'weightChangeFromStartProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$weightChangeFromStartHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef WeightChangeFromStartRef = AutoDisposeFutureProviderRef<double?>;
String _$daysUntilDeadlineHash() => r'71e6d2b90ecd006f208f83437f4db60b41e00cb6';

/// 目標達成までの残り日数を取得するProvider
///
/// Copied from [daysUntilDeadline].
@ProviderFor(daysUntilDeadline)
final daysUntilDeadlineProvider = AutoDisposeFutureProvider<int?>.internal(
  daysUntilDeadline,
  name: r'daysUntilDeadlineProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$daysUntilDeadlineHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DaysUntilDeadlineRef = AutoDisposeFutureProviderRef<int?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
