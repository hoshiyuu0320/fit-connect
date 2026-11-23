// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'current_user_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$currentClientHash() => r'a1f6de4dabd4fa2dbde0cd7168092690f9b7cc48';

/// 現在のクライアント情報を取得するProvider
///
/// 「行が無い」と「取得に失敗した」を区別する。呼び出し側も区別して扱うこと。
/// - clients の行が無い: `null`（未ログインのときも `null`）。
///   app.dart が「残ったセッション」とみなしてサインアウトする。
/// - 取得に失敗した（オフライン・サーバーエラー・応答の不整合など）: AsyncError。
///   行が無いとは限らないので、サインアウトさせない（再試行を促す）。
///
/// Copied from [currentClient].
@ProviderFor(currentClient)
final currentClientProvider = AutoDisposeFutureProvider<Client?>.internal(
  currentClient,
  name: r'currentClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CurrentClientRef = AutoDisposeFutureProviderRef<Client?>;
String _$currentClientIdHash() => r'dc5638cd7a23c29c2573f51c633bb63bf7e7e2a6';

/// 現在のクライアントIDを取得するProvider
///
/// Copied from [currentClientId].
@ProviderFor(currentClientId)
final currentClientIdProvider = AutoDisposeProvider<String?>.internal(
  currentClientId,
  name: r'currentClientIdProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentClientIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CurrentClientIdRef = AutoDisposeProviderRef<String?>;
String _$currentTrainerIdHash() => r'0d44748436d43eaab26174b88e9e0e891a9d8013';

/// 現在のトレーナーIDを取得するProvider
///
/// Copied from [currentTrainerId].
@ProviderFor(currentTrainerId)
final currentTrainerIdProvider = AutoDisposeProvider<String?>.internal(
  currentTrainerId,
  name: r'currentTrainerIdProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentTrainerIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CurrentTrainerIdRef = AutoDisposeProviderRef<String?>;
String _$trainerProfileHash() => r'576747f36d971cbcd9a849a038e593fddf4f7a8e';

/// トレーナーのプロフィール情報を取得するProvider
///
/// Copied from [trainerProfile].
@ProviderFor(trainerProfile)
final trainerProfileProvider = AutoDisposeFutureProvider<Trainer?>.internal(
  trainerProfile,
  name: r'trainerProfileProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$trainerProfileHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TrainerProfileRef = AutoDisposeFutureProviderRef<Trainer?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
