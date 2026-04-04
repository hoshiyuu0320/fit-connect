// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_achievement_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$goalAchievementNotifierHash() =>
    r'7037157cf80279cb28721e5942052b85438bf2d0';

/// 目標達成時にお祝い画面を表示すべきかを管理するProvider
///
/// 使用方法:
/// 1. HomeScreenで `currentGoalProvider` を監視
/// 2. `goalAchievedAt` が変わったら `checkAndShowCelebration` を呼び出し
/// 3. `showCelebration` が true の場合、お祝いオーバーレイを表示
/// 4. ユーザーが閉じたら `dismissCelebration` を呼び出し
///
/// Copied from [GoalAchievementNotifier].
@ProviderFor(GoalAchievementNotifier)
final goalAchievementNotifierProvider =
    AutoDisposeNotifierProvider<GoalAchievementNotifier, bool>.internal(
  GoalAchievementNotifier.new,
  name: r'goalAchievementNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$goalAchievementNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$GoalAchievementNotifier = AutoDisposeNotifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
