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
    r'4e454b5d3f5a3fccac6d2ff9cfd1e95c530e76fc';

/// トレーナーの現在の稼働状態を判定するProvider
/// - スケジュール未設定 → true（常時オン扱い）
/// - 今日のスケジュールなし or is_available=false → false
/// - start_time〜end_time内 → true
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
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
