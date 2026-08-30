// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'force_update_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$packageInfoHash() => r'6d24887a45825322730812d638eae4192104901b';

/// アプリのパッケージ情報（実行中バージョンの取得）。
/// 強制アップデート判定のほか、設定画面のバージョン表示でも使用する。
///
/// Copied from [packageInfo].
@ProviderFor(packageInfo)
final packageInfoProvider = AutoDisposeFutureProvider<PackageInfo>.internal(
  packageInfo,
  name: r'packageInfoProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$packageInfoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PackageInfoRef = AutoDisposeFutureProviderRef<PackageInfo>;
String _$forceUpdateHash() => r'53b022bb9665c85dc3ecd41dec5c9f375deefdec';

/// 強制アップデート判定 Provider。
/// 要更新の場合のみ [AppConfig] を返し、更新不要・app_config 行なしは null。
/// 通信例外はそのまま throw する（タイムアウト・fail-open 制御は
/// AppUpdateGate 側で行う）。
///
/// Copied from [forceUpdate].
@ProviderFor(forceUpdate)
final forceUpdateProvider = AutoDisposeFutureProvider<AppConfig?>.internal(
  forceUpdate,
  name: r'forceUpdateProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$forceUpdateHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ForceUpdateRef = AutoDisposeFutureProviderRef<AppConfig?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
