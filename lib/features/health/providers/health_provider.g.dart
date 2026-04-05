// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$healthRepositoryHash() => r'f583a8e0a938df5aa276a7f12a58e5f839110f12';

/// HealthRepository のプロバイダ
///
/// Copied from [healthRepository].
@ProviderFor(healthRepository)
final healthRepositoryProvider = AutoDisposeProvider<HealthRepository>.internal(
  healthRepository,
  name: r'healthRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$healthRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HealthRepositoryRef = AutoDisposeProviderRef<HealthRepository>;
String _$healthAvailableHash() => r'18900c77080342336e1852573f10dc21aad67b3a';

/// HealthKit 連携が利用可能かどうか
///
/// Copied from [healthAvailable].
@ProviderFor(healthAvailable)
final healthAvailableProvider = AutoDisposeFutureProvider<bool>.internal(
  healthAvailable,
  name: r'healthAvailableProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$healthAvailableHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HealthAvailableRef = AutoDisposeFutureProviderRef<bool>;
String _$healthSettingsHash() => r'1677342922d0f608d2f66815d93b538105927a13';

/// ヘルスケア連携設定の状態管理
///
/// Copied from [HealthSettings].
@ProviderFor(HealthSettings)
final healthSettingsProvider = AutoDisposeAsyncNotifierProvider<HealthSettings,
    HealthSettingsState>.internal(
  HealthSettings.new,
  name: r'healthSettingsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$healthSettingsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$HealthSettings = AutoDisposeAsyncNotifier<HealthSettingsState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
