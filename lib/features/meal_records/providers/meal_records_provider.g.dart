// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meal_records_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$mealRepositoryHash() => r'607e889699211d3aa17bae522b1760e3090fa208';

/// MealRepositoryのProvider
///
/// Copied from [mealRepository].
@ProviderFor(mealRepository)
final mealRepositoryProvider = AutoDisposeProvider<MealRepository>.internal(
  mealRepository,
  name: r'mealRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$mealRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MealRepositoryRef = AutoDisposeProviderRef<MealRepository>;
String _$todayMealCountHash() => r'ccff336a489c666214f4a9b4f91ececd7f100361';

/// 今日の食事記録数を取得するProvider
///
/// Copied from [todayMealCount].
@ProviderFor(todayMealCount)
final todayMealCountProvider = AutoDisposeFutureProvider<int>.internal(
  todayMealCount,
  name: r'todayMealCountProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$todayMealCountHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TodayMealCountRef = AutoDisposeFutureProviderRef<int>;
String _$mealRecordCountsHash() => r'7f4deb2501129098774386bb9866174f223d0705';

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

/// 月間の食事記録カウント（カレンダー用）を取得するProvider
///
/// Copied from [mealRecordCounts].
@ProviderFor(mealRecordCounts)
const mealRecordCountsProvider = MealRecordCountsFamily();

/// 月間の食事記録カウント（カレンダー用）を取得するProvider
///
/// Copied from [mealRecordCounts].
class MealRecordCountsFamily extends Family<AsyncValue<Map<DateTime, int>>> {
  /// 月間の食事記録カウント（カレンダー用）を取得するProvider
  ///
  /// Copied from [mealRecordCounts].
  const MealRecordCountsFamily();

  /// 月間の食事記録カウント（カレンダー用）を取得するProvider
  ///
  /// Copied from [mealRecordCounts].
  MealRecordCountsProvider call({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return MealRecordCountsProvider(
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  MealRecordCountsProvider getProviderOverride(
    covariant MealRecordCountsProvider provider,
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
  String? get name => r'mealRecordCountsProvider';
}

/// 月間の食事記録カウント（カレンダー用）を取得するProvider
///
/// Copied from [mealRecordCounts].
class MealRecordCountsProvider
    extends AutoDisposeFutureProvider<Map<DateTime, int>> {
  /// 月間の食事記録カウント（カレンダー用）を取得するProvider
  ///
  /// Copied from [mealRecordCounts].
  MealRecordCountsProvider({
    required DateTime startDate,
    required DateTime endDate,
  }) : this._internal(
          (ref) => mealRecordCounts(
            ref as MealRecordCountsRef,
            startDate: startDate,
            endDate: endDate,
          ),
          from: mealRecordCountsProvider,
          name: r'mealRecordCountsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$mealRecordCountsHash,
          dependencies: MealRecordCountsFamily._dependencies,
          allTransitiveDependencies:
              MealRecordCountsFamily._allTransitiveDependencies,
          startDate: startDate,
          endDate: endDate,
        );

  MealRecordCountsProvider._internal(
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
    FutureOr<Map<DateTime, int>> Function(MealRecordCountsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: MealRecordCountsProvider._internal(
        (ref) => create(ref as MealRecordCountsRef),
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
    return _MealRecordCountsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is MealRecordCountsProvider &&
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
mixin MealRecordCountsRef on AutoDisposeFutureProviderRef<Map<DateTime, int>> {
  /// The parameter `startDate` of this provider.
  DateTime get startDate;

  /// The parameter `endDate` of this provider.
  DateTime get endDate;
}

class _MealRecordCountsProviderElement
    extends AutoDisposeFutureProviderElement<Map<DateTime, int>>
    with MealRecordCountsRef {
  _MealRecordCountsProviderElement(super.provider);

  @override
  DateTime get startDate => (origin as MealRecordCountsProvider).startDate;
  @override
  DateTime get endDate => (origin as MealRecordCountsProvider).endDate;
}

String _$mealRecordsHash() => r'f5af3386d16c6618a91503ca5456d0bed5b547c3';

abstract class _$MealRecords
    extends BuildlessAutoDisposeAsyncNotifier<List<MealRecord>> {
  late final PeriodFilter period;
  late final String? mealType;
  late final DateTime? startDate;
  late final DateTime? endDate;

  FutureOr<List<MealRecord>> build({
    PeriodFilter period = PeriodFilter.month,
    String? mealType,
    DateTime? startDate,
    DateTime? endDate,
  });
}

/// 食事記録リストを取得するProvider
///
/// Copied from [MealRecords].
@ProviderFor(MealRecords)
const mealRecordsProvider = MealRecordsFamily();

/// 食事記録リストを取得するProvider
///
/// Copied from [MealRecords].
class MealRecordsFamily extends Family<AsyncValue<List<MealRecord>>> {
  /// 食事記録リストを取得するProvider
  ///
  /// Copied from [MealRecords].
  const MealRecordsFamily();

  /// 食事記録リストを取得するProvider
  ///
  /// Copied from [MealRecords].
  MealRecordsProvider call({
    PeriodFilter period = PeriodFilter.month,
    String? mealType,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return MealRecordsProvider(
      period: period,
      mealType: mealType,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  MealRecordsProvider getProviderOverride(
    covariant MealRecordsProvider provider,
  ) {
    return call(
      period: provider.period,
      mealType: provider.mealType,
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
  String? get name => r'mealRecordsProvider';
}

/// 食事記録リストを取得するProvider
///
/// Copied from [MealRecords].
class MealRecordsProvider extends AutoDisposeAsyncNotifierProviderImpl<
    MealRecords, List<MealRecord>> {
  /// 食事記録リストを取得するProvider
  ///
  /// Copied from [MealRecords].
  MealRecordsProvider({
    PeriodFilter period = PeriodFilter.month,
    String? mealType,
    DateTime? startDate,
    DateTime? endDate,
  }) : this._internal(
          () => MealRecords()
            ..period = period
            ..mealType = mealType
            ..startDate = startDate
            ..endDate = endDate,
          from: mealRecordsProvider,
          name: r'mealRecordsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$mealRecordsHash,
          dependencies: MealRecordsFamily._dependencies,
          allTransitiveDependencies:
              MealRecordsFamily._allTransitiveDependencies,
          period: period,
          mealType: mealType,
          startDate: startDate,
          endDate: endDate,
        );

  MealRecordsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.period,
    required this.mealType,
    required this.startDate,
    required this.endDate,
  }) : super.internal();

  final PeriodFilter period;
  final String? mealType;
  final DateTime? startDate;
  final DateTime? endDate;

  @override
  FutureOr<List<MealRecord>> runNotifierBuild(
    covariant MealRecords notifier,
  ) {
    return notifier.build(
      period: period,
      mealType: mealType,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  Override overrideWith(MealRecords Function() create) {
    return ProviderOverride(
      origin: this,
      override: MealRecordsProvider._internal(
        () => create()
          ..period = period
          ..mealType = mealType
          ..startDate = startDate
          ..endDate = endDate,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        period: period,
        mealType: mealType,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<MealRecords, List<MealRecord>>
      createElement() {
    return _MealRecordsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is MealRecordsProvider &&
        other.period == period &&
        other.mealType == mealType &&
        other.startDate == startDate &&
        other.endDate == endDate;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, period.hashCode);
    hash = _SystemHash.combine(hash, mealType.hashCode);
    hash = _SystemHash.combine(hash, startDate.hashCode);
    hash = _SystemHash.combine(hash, endDate.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin MealRecordsRef on AutoDisposeAsyncNotifierProviderRef<List<MealRecord>> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;

  /// The parameter `mealType` of this provider.
  String? get mealType;

  /// The parameter `startDate` of this provider.
  DateTime? get startDate;

  /// The parameter `endDate` of this provider.
  DateTime? get endDate;
}

class _MealRecordsProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<MealRecords,
        List<MealRecord>> with MealRecordsRef {
  _MealRecordsProviderElement(super.provider);

  @override
  PeriodFilter get period => (origin as MealRecordsProvider).period;
  @override
  String? get mealType => (origin as MealRecordsProvider).mealType;
  @override
  DateTime? get startDate => (origin as MealRecordsProvider).startDate;
  @override
  DateTime? get endDate => (origin as MealRecordsProvider).endDate;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
