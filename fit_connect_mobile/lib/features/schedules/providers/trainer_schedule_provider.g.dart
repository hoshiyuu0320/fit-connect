// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trainer_schedule_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$trainerSchedulesHash() => r'd080d990ac7cc7206450e5c3e79e78a097d222ce';

/// トレーナーのスケジュール一覧を取得するProvider
///
/// Copied from [trainerSchedules].
@ProviderFor(trainerSchedules)
final trainerSchedulesProvider =
    AutoDisposeFutureProvider<List<TrainerSchedule>>.internal(
  trainerSchedules,
  name: r'trainerSchedulesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$trainerSchedulesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TrainerSchedulesRef
    = AutoDisposeFutureProviderRef<List<TrainerSchedule>>;
String _$trainerCurrentStatusHash() =>
    r'91c78c03bace61719a3ec1109e1b3a9b2b2a4f5a';

/// トレーナーの現在の稼働状態を返すProvider（後方互換用）
///
/// 既存の UI で `trainerCurrentStatusProvider` を使っている箇所に影響を与えない。
///
/// Copied from [trainerCurrentStatus].
@ProviderFor(trainerCurrentStatus)
final trainerCurrentStatusProvider = AutoDisposeProvider<bool>.internal(
  trainerCurrentStatus,
  name: r'trainerCurrentStatusProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$trainerCurrentStatusHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TrainerCurrentStatusRef = AutoDisposeProviderRef<bool>;
String _$trainerPresenceNotifierHash() =>
    r'e8d5363c4860ae9466b27c52d54a48cb645c16cd';

/// トレーナーのプレゼンス（オンライン状態）を Realtime で監視する Notifier
///
/// Copied from [TrainerPresenceNotifier].
@ProviderFor(TrainerPresenceNotifier)
final trainerPresenceNotifierProvider = AutoDisposeNotifierProvider<
    TrainerPresenceNotifier, TrainerPresence>.internal(
  TrainerPresenceNotifier.new,
  name: r'trainerPresenceNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$trainerPresenceNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TrainerPresenceNotifier = AutoDisposeNotifier<TrainerPresence>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
