// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_features_enabled_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$aiFeaturesEnabledHash() => r'6788a4cbe47b41a92ad5cf34f15925bd0500c133';

/// 自身の担当トレーナーの subscription_plan が 'pro' かどうか。
/// 取得失敗・未認証・未紐付けの場合は false を返す（保守的にAI非表示）。
///
/// 参照経路: auth.uid() → clients.client_id → clients.trainer_id → trainers.subscription_plan
///
/// Copied from [aiFeaturesEnabled].
@ProviderFor(aiFeaturesEnabled)
final aiFeaturesEnabledProvider = AutoDisposeFutureProvider<bool>.internal(
  aiFeaturesEnabled,
  name: r'aiFeaturesEnabledProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$aiFeaturesEnabledHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AiFeaturesEnabledRef = AutoDisposeFutureProviderRef<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
