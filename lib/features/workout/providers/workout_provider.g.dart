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
    r'd6b0ec4de50ead2e577bee5a250dd1ebb83315e5';

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
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return CompletedWorkoutAssignmentsProvider(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  CompletedWorkoutAssignmentsProvider getProviderOverride(
    covariant CompletedWorkoutAssignmentsProvider provider,
  ) {
    return call(
      period: provider.period,
      startDate: provider.startDate,
      endDate: provider.endDate,
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
    DateTime? startDate,
    DateTime? endDate,
  }) : this._internal(
          (ref) => completedWorkoutAssignments(
            ref as CompletedWorkoutAssignmentsRef,
            period: period,
            startDate: startDate,
            endDate: endDate,
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
          startDate: startDate,
          endDate: endDate,
        );

  CompletedWorkoutAssignmentsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.period,
    required this.startDate,
    required this.endDate,
  }) : super.internal();

  final PeriodFilter period;
  final DateTime? startDate;
  final DateTime? endDate;

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
        startDate: startDate,
        endDate: endDate,
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
        other.period == period &&
        other.startDate == startDate &&
        other.endDate == endDate;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, period.hashCode);
    hash = _SystemHash.combine(hash, startDate.hashCode);
    hash = _SystemHash.combine(hash, endDate.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin CompletedWorkoutAssignmentsRef
    on AutoDisposeFutureProviderRef<List<WorkoutAssignment>> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;

  /// The parameter `startDate` of this provider.
  DateTime? get startDate;

  /// The parameter `endDate` of this provider.
  DateTime? get endDate;
}

class _CompletedWorkoutAssignmentsProviderElement
    extends AutoDisposeFutureProviderElement<List<WorkoutAssignment>>
    with CompletedWorkoutAssignmentsRef {
  _CompletedWorkoutAssignmentsProviderElement(super.provider);

  @override
  PeriodFilter get period =>
      (origin as CompletedWorkoutAssignmentsProvider).period;
  @override
  DateTime? get startDate =>
      (origin as CompletedWorkoutAssignmentsProvider).startDate;
  @override
  DateTime? get endDate =>
      (origin as CompletedWorkoutAssignmentsProvider).endDate;
}

String _$workoutScreenNotifierHash() =>
    r'787849580641cb2ccc6d76ff5bd02dae3ffbd6ec';

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
