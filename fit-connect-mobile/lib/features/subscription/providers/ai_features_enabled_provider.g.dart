// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_features_enabled_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$aiFeaturesEnabledHash() => r'42108248a53aa87cb864f5a4ce2070690dda2fc8';

/// 自身の担当トレーナーがAI機能を利用可能かどうか（実効プラン判定）。
/// - subscription_plan が 'pro' または 'business' → 利用可
/// - 'free' でも trial_ends_at が現在より未来（トライアル中・Pro相当） → 利用可
/// - それ以外・取得失敗・未認証・未紐付け → false（保守的にAI非表示）
///
/// 参照経路: auth.uid() → clients.client_id → clients.trainer_id
///           → trainers.subscription_plan / trainers.trial_ends_at
///
/// Copied from [aiFeaturesEnabled].
@ProviderFor(aiFeaturesEnabled)
final aiFeaturesEnabledProvider = FutureProvider<bool>.internal(
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
typedef AiFeaturesEnabledRef = FutureProviderRef<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
