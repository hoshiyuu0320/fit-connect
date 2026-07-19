// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_features_enabled_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$aiFeaturesEnabledHash() => r'2810480b3e0afb03675dde0a3d5579d7945a0899';

/// 自身の担当トレーナーが解決できるかどうか（AI機能のUIゲート）。
/// - 担当トレーナーが解決できれば true（Freeプランにも月次クォータ内でAIが
///   開放されたため、プラン文字列による出し分けは行わない）
/// - 取得失敗・未認証・未紐付け → false（保守的にAI非表示）
///
/// クォータ制御はサーバー側（Edge Function の 429 応答）が実体。
/// このUIゲートは将来のkill switch（AI機能の全停止）用に残している。
///
/// 参照経路: auth.uid() → clients.client_id → clients.trainer_id
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
