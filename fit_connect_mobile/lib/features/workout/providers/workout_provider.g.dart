// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$workoutRepositoryHash() => r'36366b9d6c905dd0aa51006a52cb71b98a124b57';

/// WorkoutRepository を提供するProvider
///
/// Copied from [workoutRepository].
@ProviderFor(workoutRepository)
final workoutRepositoryProvider =
    AutoDisposeProvider<WorkoutRepository>.internal(
  workoutRepository,
  name: r'workoutRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$workoutRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef WorkoutRepositoryRef = AutoDisposeProviderRef<WorkoutRepository>;
String _$completedWorkoutAssignmentsHash() =>
    r'e3aacf0fef4cb70a6a15dca0466647b575de6223';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// 完了済みワークアウトアサインメントを取得するProvider
///
/// Copied from [completedWorkoutAssignments].
@ProviderFor(completedWorkoutAssignments)
const completedWorkoutAssignmentsProvider = CompletedWorkoutAssignmentsFamily();

/// 完了済みワークアウトアサインメントを取得するProvider
///
/// Copied from [completedWorkoutAssignments].
class CompletedWorkoutAssignmentsFamily
    extends Family<AsyncValue<List<WorkoutAssignment>>> {
  /// 完了済みワークアウトアサインメントを取得するProvider
  ///
  /// Copied from [completedWorkoutAssignments].
  const CompletedWorkoutAssignmentsFamily();

  /// 完了済みワークアウトアサインメントを取得するProvider
  ///
  /// Copied from [completedWorkoutAssignments].
  CompletedWorkoutAssignmentsProvider call({
    PeriodFilter period = PeriodFilter.week,
  }) {
    return CompletedWorkoutAssignmentsProvider(
      period: period,
    );
  }

  @override
  CompletedWorkoutAssignmentsProvider getProviderOverride(
    covariant CompletedWorkoutAssignmentsProvider provider,
  ) {
    return call(
      period: provider.period,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'completedWorkoutAssignmentsProvider';
}

/// 完了済みワークアウトアサインメントを取得するProvider
///
/// Copied from [completedWorkoutAssignments].
class CompletedWorkoutAssignmentsProvider
    extends AutoDisposeFutureProvider<List<WorkoutAssignment>> {
  /// 完了済みワークアウトアサインメントを取得するProvider
  ///
  /// Copied from [completedWorkoutAssignments].
  CompletedWorkoutAssignmentsProvider({
    PeriodFilter period = PeriodFilter.week,
  }) : this._internal(
          (ref) => completedWorkoutAssignments(
            ref as CompletedWorkoutAssignmentsRef,
            period: period,
          ),
          from: completedWorkoutAssignmentsProvider,
          name: r'completedWorkoutAssignmentsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$completedWorkoutAssignmentsHash,
          dependencies: CompletedWorkoutAssignmentsFamily._dependencies,
          allTransitiveDependencies:
              CompletedWorkoutAssignmentsFamily._allTransitiveDependencies,
          period: period,
        );

  CompletedWorkoutAssignmentsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.period,
  }) : super.internal();

  final PeriodFilter period;

  @override
  Override overrideWith(
    FutureOr<List<WorkoutAssignment>> Function(
            CompletedWorkoutAssignmentsRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: CompletedWorkoutAssignmentsProvider._internal(
        (ref) => create(ref as CompletedWorkoutAssignmentsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        period: period,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<WorkoutAssignment>> createElement() {
    return _CompletedWorkoutAssignmentsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CompletedWorkoutAssignmentsProvider &&
        other.period == period;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, period.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin CompletedWorkoutAssignmentsRef
    on AutoDisposeFutureProviderRef<List<WorkoutAssignment>> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;
}

class _CompletedWorkoutAssignmentsProviderElement
    extends AutoDisposeFutureProviderElement<List<WorkoutAssignment>>
    with CompletedWorkoutAssignmentsRef {
  _CompletedWorkoutAssignmentsProviderElement(super.provider);

  @override
  PeriodFilter get period =>
      (origin as CompletedWorkoutAssignmentsProvider).period;
}

String _$workoutScreenNotifierHash() =>
    r'f3a697181867835f769a384469e14ec5e8c61f33';

/// ワークアウト画面の状態を管理するNotifier
///
/// - 初期ロード: 期限切れ・今日・週間の3クエリを並列取得して WorkoutScreenState を返す
/// - [toggleExercise]: 種目の完了状態をDB更新 + ローカルstateの楽観的更新
/// - [updateExerciseSets]: セット記録をDB更新 + 楽観的ローカルstate更新
/// - [submitCompletion]: アサインメントをDB上で完了にしてローカルstateを更新
/// - [doToday]: 期限切れアサインメントを今日のリストに移動
/// - [skip]: 期限切れアサインメントをスキップ
/// - [reschedule]: 期限切れアサインメントの日付を変更
///
/// Copied from [WorkoutScreenNotifier].
@ProviderFor(WorkoutScreenNotifier)
final workoutScreenNotifierProvider = AutoDisposeAsyncNotifierProvider<
    WorkoutScreenNotifier, WorkoutScreenState>.internal(
  WorkoutScreenNotifier.new,
  name: r'workoutScreenNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$workoutScreenNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$WorkoutScreenNotifier = AutoDisposeAsyncNotifier<WorkoutScreenState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
