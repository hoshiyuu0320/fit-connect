// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise_records_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$exerciseRepositoryHash() =>
    r'995a3011a059a0092b9f9911a315c8a0c1b1a8e0';

/// ExerciseRepositoryのProvider
///
/// Copied from [exerciseRepository].
@ProviderFor(exerciseRepository)
final exerciseRepositoryProvider =
    AutoDisposeProvider<ExerciseRepository>.internal(
  exerciseRepository,
  name: r'exerciseRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$exerciseRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ExerciseRepositoryRef = AutoDisposeProviderRef<ExerciseRepository>;
String _$weeklyExerciseCountHash() =>
    r'8aa6b721170434ba4e52ad83d546b5cd2143f8a8';

/// 今週の運動回数を取得するProvider
///
/// Copied from [weeklyExerciseCount].
@ProviderFor(weeklyExerciseCount)
final weeklyExerciseCountProvider = AutoDisposeFutureProvider<int>.internal(
  weeklyExerciseCount,
  name: r'weeklyExerciseCountProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$weeklyExerciseCountHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef WeeklyExerciseCountRef = AutoDisposeFutureProviderRef<int>;
String _$exerciseTypeCountsHash() =>
    r'b2e189c9adfd6b39d4ba51996a58a38bb4b5b9d0';

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

/// 運動タイプ別カウントを取得するProvider
///
/// Copied from [exerciseTypeCounts].
@ProviderFor(exerciseTypeCounts)
const exerciseTypeCountsProvider = ExerciseTypeCountsFamily();

/// 運動タイプ別カウントを取得するProvider
///
/// Copied from [exerciseTypeCounts].
class ExerciseTypeCountsFamily extends Family<AsyncValue<Map<String, int>>> {
  /// 運動タイプ別カウントを取得するProvider
  ///
  /// Copied from [exerciseTypeCounts].
  const ExerciseTypeCountsFamily();

  /// 運動タイプ別カウントを取得するProvider
  ///
  /// Copied from [exerciseTypeCounts].
  ExerciseTypeCountsProvider call({
    PeriodFilter period = PeriodFilter.month,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return ExerciseTypeCountsProvider(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  ExerciseTypeCountsProvider getProviderOverride(
    covariant ExerciseTypeCountsProvider provider,
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
  String? get name => r'exerciseTypeCountsProvider';
}

/// 運動タイプ別カウントを取得するProvider
///
/// Copied from [exerciseTypeCounts].
class ExerciseTypeCountsProvider
    extends AutoDisposeFutureProvider<Map<String, int>> {
  /// 運動タイプ別カウントを取得するProvider
  ///
  /// Copied from [exerciseTypeCounts].
  ExerciseTypeCountsProvider({
    PeriodFilter period = PeriodFilter.month,
    DateTime? startDate,
    DateTime? endDate,
  }) : this._internal(
          (ref) => exerciseTypeCounts(
            ref as ExerciseTypeCountsRef,
            period: period,
            startDate: startDate,
            endDate: endDate,
          ),
          from: exerciseTypeCountsProvider,
          name: r'exerciseTypeCountsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$exerciseTypeCountsHash,
          dependencies: ExerciseTypeCountsFamily._dependencies,
          allTransitiveDependencies:
              ExerciseTypeCountsFamily._allTransitiveDependencies,
          period: period,
          startDate: startDate,
          endDate: endDate,
        );

  ExerciseTypeCountsProvider._internal(
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
    FutureOr<Map<String, int>> Function(ExerciseTypeCountsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ExerciseTypeCountsProvider._internal(
        (ref) => create(ref as ExerciseTypeCountsRef),
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
  AutoDisposeFutureProviderElement<Map<String, int>> createElement() {
    return _ExerciseTypeCountsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ExerciseTypeCountsProvider &&
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
mixin ExerciseTypeCountsRef on AutoDisposeFutureProviderRef<Map<String, int>> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;

  /// The parameter `startDate` of this provider.
  DateTime? get startDate;

  /// The parameter `endDate` of this provider.
  DateTime? get endDate;
}

class _ExerciseTypeCountsProviderElement
    extends AutoDisposeFutureProviderElement<Map<String, int>>
    with ExerciseTypeCountsRef {
  _ExerciseTypeCountsProviderElement(super.provider);

  @override
  PeriodFilter get period => (origin as ExerciseTypeCountsProvider).period;
  @override
  DateTime? get startDate => (origin as ExerciseTypeCountsProvider).startDate;
  @override
  DateTime? get endDate => (origin as ExerciseTypeCountsProvider).endDate;
}

String _$weeklyExerciseDataHash() =>
    r'60d1157d6fd269d4c78ba9e9fba6868b6358a492';

/// 週間カレンダー用の運動データを取得するProvider
///
/// Copied from [weeklyExerciseData].
@ProviderFor(weeklyExerciseData)
const weeklyExerciseDataProvider = WeeklyExerciseDataFamily();

/// 週間カレンダー用の運動データを取得するProvider
///
/// Copied from [weeklyExerciseData].
class WeeklyExerciseDataFamily
    extends Family<AsyncValue<Map<DateTime, List<String>>>> {
  /// 週間カレンダー用の運動データを取得するProvider
  ///
  /// Copied from [weeklyExerciseData].
  const WeeklyExerciseDataFamily();

  /// 週間カレンダー用の運動データを取得するProvider
  ///
  /// Copied from [weeklyExerciseData].
  WeeklyExerciseDataProvider call({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return WeeklyExerciseDataProvider(
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  WeeklyExerciseDataProvider getProviderOverride(
    covariant WeeklyExerciseDataProvider provider,
  ) {
    return call(
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
  String? get name => r'weeklyExerciseDataProvider';
}

/// 週間カレンダー用の運動データを取得するProvider
///
/// Copied from [weeklyExerciseData].
class WeeklyExerciseDataProvider
    extends AutoDisposeFutureProvider<Map<DateTime, List<String>>> {
  /// 週間カレンダー用の運動データを取得するProvider
  ///
  /// Copied from [weeklyExerciseData].
  WeeklyExerciseDataProvider({
    required DateTime startDate,
    required DateTime endDate,
  }) : this._internal(
          (ref) => weeklyExerciseData(
            ref as WeeklyExerciseDataRef,
            startDate: startDate,
            endDate: endDate,
          ),
          from: weeklyExerciseDataProvider,
          name: r'weeklyExerciseDataProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$weeklyExerciseDataHash,
          dependencies: WeeklyExerciseDataFamily._dependencies,
          allTransitiveDependencies:
              WeeklyExerciseDataFamily._allTransitiveDependencies,
          startDate: startDate,
          endDate: endDate,
        );

  WeeklyExerciseDataProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.startDate,
    required this.endDate,
  }) : super.internal();

  final DateTime startDate;
  final DateTime endDate;

  @override
  Override overrideWith(
    FutureOr<Map<DateTime, List<String>>> Function(
            WeeklyExerciseDataRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: WeeklyExerciseDataProvider._internal(
        (ref) => create(ref as WeeklyExerciseDataRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Map<DateTime, List<String>>>
      createElement() {
    return _WeeklyExerciseDataProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is WeeklyExerciseDataProvider &&
        other.startDate == startDate &&
        other.endDate == endDate;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, startDate.hashCode);
    hash = _SystemHash.combine(hash, endDate.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin WeeklyExerciseDataRef
    on AutoDisposeFutureProviderRef<Map<DateTime, List<String>>> {
  /// The parameter `startDate` of this provider.
  DateTime get startDate;

  /// The parameter `endDate` of this provider.
  DateTime get endDate;
}

class _WeeklyExerciseDataProviderElement
    extends AutoDisposeFutureProviderElement<Map<DateTime, List<String>>>
    with WeeklyExerciseDataRef {
  _WeeklyExerciseDataProviderElement(super.provider);

  @override
  DateTime get startDate => (origin as WeeklyExerciseDataProvider).startDate;
  @override
  DateTime get endDate => (origin as WeeklyExerciseDataProvider).endDate;
}

String _$exerciseRecordCountsHash() =>
    r'3440f37e8ccb40cf768124dbc88f3aa047a65d01';

/// 月カレンダー用の日別運動回数を取得するProvider
///
/// Copied from [exerciseRecordCounts].
@ProviderFor(exerciseRecordCounts)
const exerciseRecordCountsProvider = ExerciseRecordCountsFamily();

/// 月カレンダー用の日別運動回数を取得するProvider
///
/// Copied from [exerciseRecordCounts].
class ExerciseRecordCountsFamily
    extends Family<AsyncValue<Map<DateTime, int>>> {
  /// 月カレンダー用の日別運動回数を取得するProvider
  ///
  /// Copied from [exerciseRecordCounts].
  const ExerciseRecordCountsFamily();

  /// 月カレンダー用の日別運動回数を取得するProvider
  ///
  /// Copied from [exerciseRecordCounts].
  ExerciseRecordCountsProvider call({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return ExerciseRecordCountsProvider(
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  ExerciseRecordCountsProvider getProviderOverride(
    covariant ExerciseRecordCountsProvider provider,
  ) {
    return call(
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
  String? get name => r'exerciseRecordCountsProvider';
}

/// 月カレンダー用の日別運動回数を取得するProvider
///
/// Copied from [exerciseRecordCounts].
class ExerciseRecordCountsProvider
    extends AutoDisposeFutureProvider<Map<DateTime, int>> {
  /// 月カレンダー用の日別運動回数を取得するProvider
  ///
  /// Copied from [exerciseRecordCounts].
  ExerciseRecordCountsProvider({
    required DateTime startDate,
    required DateTime endDate,
  }) : this._internal(
          (ref) => exerciseRecordCounts(
            ref as ExerciseRecordCountsRef,
            startDate: startDate,
            endDate: endDate,
          ),
          from: exerciseRecordCountsProvider,
          name: r'exerciseRecordCountsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$exerciseRecordCountsHash,
          dependencies: ExerciseRecordCountsFamily._dependencies,
          allTransitiveDependencies:
              ExerciseRecordCountsFamily._allTransitiveDependencies,
          startDate: startDate,
          endDate: endDate,
        );

  ExerciseRecordCountsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.startDate,
    required this.endDate,
  }) : super.internal();

  final DateTime startDate;
  final DateTime endDate;

  @override
  Override overrideWith(
    FutureOr<Map<DateTime, int>> Function(ExerciseRecordCountsRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ExerciseRecordCountsProvider._internal(
        (ref) => create(ref as ExerciseRecordCountsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Map<DateTime, int>> createElement() {
    return _ExerciseRecordCountsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ExerciseRecordCountsProvider &&
        other.startDate == startDate &&
        other.endDate == endDate;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, startDate.hashCode);
    hash = _SystemHash.combine(hash, endDate.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ExerciseRecordCountsRef
    on AutoDisposeFutureProviderRef<Map<DateTime, int>> {
  /// The parameter `startDate` of this provider.
  DateTime get startDate;

  /// The parameter `endDate` of this provider.
  DateTime get endDate;
}

class _ExerciseRecordCountsProviderElement
    extends AutoDisposeFutureProviderElement<Map<DateTime, int>>
    with ExerciseRecordCountsRef {
  _ExerciseRecordCountsProviderElement(super.provider);

  @override
  DateTime get startDate => (origin as ExerciseRecordCountsProvider).startDate;
  @override
  DateTime get endDate => (origin as ExerciseRecordCountsProvider).endDate;
}

String _$exerciseTotalCaloriesHash() =>
    r'4250b82a429fd5d33fb4fc77ecbcfe58bb40dade';

/// 期間内の消費カロリー合計を取得するProvider
///
/// Copied from [exerciseTotalCalories].
@ProviderFor(exerciseTotalCalories)
const exerciseTotalCaloriesProvider = ExerciseTotalCaloriesFamily();

/// 期間内の消費カロリー合計を取得するProvider
///
/// Copied from [exerciseTotalCalories].
class ExerciseTotalCaloriesFamily extends Family<AsyncValue<double>> {
  /// 期間内の消費カロリー合計を取得するProvider
  ///
  /// Copied from [exerciseTotalCalories].
  const ExerciseTotalCaloriesFamily();

  /// 期間内の消費カロリー合計を取得するProvider
  ///
  /// Copied from [exerciseTotalCalories].
  ExerciseTotalCaloriesProvider call({
    PeriodFilter period = PeriodFilter.month,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return ExerciseTotalCaloriesProvider(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  ExerciseTotalCaloriesProvider getProviderOverride(
    covariant ExerciseTotalCaloriesProvider provider,
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
  String? get name => r'exerciseTotalCaloriesProvider';
}

/// 期間内の消費カロリー合計を取得するProvider
///
/// Copied from [exerciseTotalCalories].
class ExerciseTotalCaloriesProvider extends AutoDisposeFutureProvider<double> {
  /// 期間内の消費カロリー合計を取得するProvider
  ///
  /// Copied from [exerciseTotalCalories].
  ExerciseTotalCaloriesProvider({
    PeriodFilter period = PeriodFilter.month,
    DateTime? startDate,
    DateTime? endDate,
  }) : this._internal(
          (ref) => exerciseTotalCalories(
            ref as ExerciseTotalCaloriesRef,
            period: period,
            startDate: startDate,
            endDate: endDate,
          ),
          from: exerciseTotalCaloriesProvider,
          name: r'exerciseTotalCaloriesProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$exerciseTotalCaloriesHash,
          dependencies: ExerciseTotalCaloriesFamily._dependencies,
          allTransitiveDependencies:
              ExerciseTotalCaloriesFamily._allTransitiveDependencies,
          period: period,
          startDate: startDate,
          endDate: endDate,
        );

  ExerciseTotalCaloriesProvider._internal(
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
    FutureOr<double> Function(ExerciseTotalCaloriesRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ExerciseTotalCaloriesProvider._internal(
        (ref) => create(ref as ExerciseTotalCaloriesRef),
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
  AutoDisposeFutureProviderElement<double> createElement() {
    return _ExerciseTotalCaloriesProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ExerciseTotalCaloriesProvider &&
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
mixin ExerciseTotalCaloriesRef on AutoDisposeFutureProviderRef<double> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;

  /// The parameter `startDate` of this provider.
  DateTime? get startDate;

  /// The parameter `endDate` of this provider.
  DateTime? get endDate;
}

class _ExerciseTotalCaloriesProviderElement
    extends AutoDisposeFutureProviderElement<double>
    with ExerciseTotalCaloriesRef {
  _ExerciseTotalCaloriesProviderElement(super.provider);

  @override
  PeriodFilter get period => (origin as ExerciseTotalCaloriesProvider).period;
  @override
  DateTime? get startDate =>
      (origin as ExerciseTotalCaloriesProvider).startDate;
  @override
  DateTime? get endDate => (origin as ExerciseTotalCaloriesProvider).endDate;
}

String _$exerciseRecordsHash() => r'095bf2dcfdaac8f8e5061690eb3468e09b1bd470';

abstract class _$ExerciseRecords
    extends BuildlessAutoDisposeAsyncNotifier<List<ExerciseRecord>> {
  late final PeriodFilter period;
  late final String? exerciseType;
  late final DateTime? startDate;
  late final DateTime? endDate;

  FutureOr<List<ExerciseRecord>> build({
    PeriodFilter period = PeriodFilter.month,
    String? exerciseType,
    DateTime? startDate,
    DateTime? endDate,
  });
}

/// 運動記録リストを取得するProvider
///
/// Copied from [ExerciseRecords].
@ProviderFor(ExerciseRecords)
const exerciseRecordsProvider = ExerciseRecordsFamily();

/// 運動記録リストを取得するProvider
///
/// Copied from [ExerciseRecords].
class ExerciseRecordsFamily extends Family<AsyncValue<List<ExerciseRecord>>> {
  /// 運動記録リストを取得するProvider
  ///
  /// Copied from [ExerciseRecords].
  const ExerciseRecordsFamily();

  /// 運動記録リストを取得するProvider
  ///
  /// Copied from [ExerciseRecords].
  ExerciseRecordsProvider call({
    PeriodFilter period = PeriodFilter.month,
    String? exerciseType,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return ExerciseRecordsProvider(
      period: period,
      exerciseType: exerciseType,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  ExerciseRecordsProvider getProviderOverride(
    covariant ExerciseRecordsProvider provider,
  ) {
    return call(
      period: provider.period,
      exerciseType: provider.exerciseType,
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
  String? get name => r'exerciseRecordsProvider';
}

/// 運動記録リストを取得するProvider
///
/// Copied from [ExerciseRecords].
class ExerciseRecordsProvider extends AutoDisposeAsyncNotifierProviderImpl<
    ExerciseRecords, List<ExerciseRecord>> {
  /// 運動記録リストを取得するProvider
  ///
  /// Copied from [ExerciseRecords].
  ExerciseRecordsProvider({
    PeriodFilter period = PeriodFilter.month,
    String? exerciseType,
    DateTime? startDate,
    DateTime? endDate,
  }) : this._internal(
          () => ExerciseRecords()
            ..period = period
            ..exerciseType = exerciseType
            ..startDate = startDate
            ..endDate = endDate,
          from: exerciseRecordsProvider,
          name: r'exerciseRecordsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$exerciseRecordsHash,
          dependencies: ExerciseRecordsFamily._dependencies,
          allTransitiveDependencies:
              ExerciseRecordsFamily._allTransitiveDependencies,
          period: period,
          exerciseType: exerciseType,
          startDate: startDate,
          endDate: endDate,
        );

  ExerciseRecordsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.period,
    required this.exerciseType,
    required this.startDate,
    required this.endDate,
  }) : super.internal();

  final PeriodFilter period;
  final String? exerciseType;
  final DateTime? startDate;
  final DateTime? endDate;

  @override
  FutureOr<List<ExerciseRecord>> runNotifierBuild(
    covariant ExerciseRecords notifier,
  ) {
    return notifier.build(
      period: period,
      exerciseType: exerciseType,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  Override overrideWith(ExerciseRecords Function() create) {
    return ProviderOverride(
      origin: this,
      override: ExerciseRecordsProvider._internal(
        () => create()
          ..period = period
          ..exerciseType = exerciseType
          ..startDate = startDate
          ..endDate = endDate,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        period: period,
        exerciseType: exerciseType,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<ExerciseRecords, List<ExerciseRecord>>
      createElement() {
    return _ExerciseRecordsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ExerciseRecordsProvider &&
        other.period == period &&
        other.exerciseType == exerciseType &&
        other.startDate == startDate &&
        other.endDate == endDate;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, period.hashCode);
    hash = _SystemHash.combine(hash, exerciseType.hashCode);
    hash = _SystemHash.combine(hash, startDate.hashCode);
    hash = _SystemHash.combine(hash, endDate.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ExerciseRecordsRef
    on AutoDisposeAsyncNotifierProviderRef<List<ExerciseRecord>> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;

  /// The parameter `exerciseType` of this provider.
  String? get exerciseType;

  /// The parameter `startDate` of this provider.
  DateTime? get startDate;

  /// The parameter `endDate` of this provider.
  DateTime? get endDate;
}

class _ExerciseRecordsProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<ExerciseRecords,
        List<ExerciseRecord>> with ExerciseRecordsRef {
  _ExerciseRecordsProviderElement(super.provider);

  @override
  PeriodFilter get period => (origin as ExerciseRecordsProvider).period;
  @override
  String? get exerciseType => (origin as ExerciseRecordsProvider).exerciseType;
  @override
  DateTime? get startDate => (origin as ExerciseRecordsProvider).startDate;
  @override
  DateTime? get endDate => (origin as ExerciseRecordsProvider).endDate;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
