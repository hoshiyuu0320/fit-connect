// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weight_records_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$weightRepositoryHash() => r'e5bdac430ae20bcf03837d6e1a51265cf24ffc21';

/// WeightRepositoryのProvider
///
/// Copied from [weightRepository].
@ProviderFor(weightRepository)
final weightRepositoryProvider = AutoDisposeProvider<WeightRepository>.internal(
  weightRepository,
  name: r'weightRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$weightRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef WeightRepositoryRef = AutoDisposeProviderRef<WeightRepository>;
String _$latestWeightRecordHash() =>
    r'996b7e8eed7ce2e1e9c7565d5df3a28ab45bcc3f';

/// 最新の体重記録を取得するProvider
///
/// Copied from [latestWeightRecord].
@ProviderFor(latestWeightRecord)
final latestWeightRecordProvider =
    AutoDisposeFutureProvider<WeightRecord?>.internal(
  latestWeightRecord,
  name: r'latestWeightRecordProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$latestWeightRecordHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LatestWeightRecordRef = AutoDisposeFutureProviderRef<WeightRecord?>;
String _$weightStatsHash() => r'174e7c2a4c63e3ce70293fd54c57f63824a71823';

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

/// 体重統計を取得するProvider
///
/// Copied from [weightStats].
@ProviderFor(weightStats)
const weightStatsProvider = WeightStatsFamily();

/// 体重統計を取得するProvider
///
/// Copied from [weightStats].
class WeightStatsFamily extends Family<AsyncValue<Map<String, double>>> {
  /// 体重統計を取得するProvider
  ///
  /// Copied from [weightStats].
  const WeightStatsFamily();

  /// 体重統計を取得するProvider
  ///
  /// Copied from [weightStats].
  WeightStatsProvider call({
    PeriodFilter period = PeriodFilter.month,
  }) {
    return WeightStatsProvider(
      period: period,
    );
  }

  @override
  WeightStatsProvider getProviderOverride(
    covariant WeightStatsProvider provider,
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
  String? get name => r'weightStatsProvider';
}

/// 体重統計を取得するProvider
///
/// Copied from [weightStats].
class WeightStatsProvider
    extends AutoDisposeFutureProvider<Map<String, double>> {
  /// 体重統計を取得するProvider
  ///
  /// Copied from [weightStats].
  WeightStatsProvider({
    PeriodFilter period = PeriodFilter.month,
  }) : this._internal(
          (ref) => weightStats(
            ref as WeightStatsRef,
            period: period,
          ),
          from: weightStatsProvider,
          name: r'weightStatsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$weightStatsHash,
          dependencies: WeightStatsFamily._dependencies,
          allTransitiveDependencies:
              WeightStatsFamily._allTransitiveDependencies,
          period: period,
        );

  WeightStatsProvider._internal(
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
    FutureOr<Map<String, double>> Function(WeightStatsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: WeightStatsProvider._internal(
        (ref) => create(ref as WeightStatsRef),
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
  AutoDisposeFutureProviderElement<Map<String, double>> createElement() {
    return _WeightStatsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is WeightStatsProvider && other.period == period;
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
mixin WeightStatsRef on AutoDisposeFutureProviderRef<Map<String, double>> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;
}

class _WeightStatsProviderElement
    extends AutoDisposeFutureProviderElement<Map<String, double>>
    with WeightStatsRef {
  _WeightStatsProviderElement(super.provider);

  @override
  PeriodFilter get period => (origin as WeightStatsProvider).period;
}

String _$weightRecordsHash() => r'53231f7a1e9dcaa6f32b15db3b4e2371c2a30732';

abstract class _$WeightRecords
    extends BuildlessAutoDisposeAsyncNotifier<List<WeightRecord>> {
  late final PeriodFilter period;

  FutureOr<List<WeightRecord>> build({
    PeriodFilter period = PeriodFilter.month,
  });
}

/// 体重記録リストを取得するProvider
///
/// Copied from [WeightRecords].
@ProviderFor(WeightRecords)
const weightRecordsProvider = WeightRecordsFamily();

/// 体重記録リストを取得するProvider
///
/// Copied from [WeightRecords].
class WeightRecordsFamily extends Family<AsyncValue<List<WeightRecord>>> {
  /// 体重記録リストを取得するProvider
  ///
  /// Copied from [WeightRecords].
  const WeightRecordsFamily();

  /// 体重記録リストを取得するProvider
  ///
  /// Copied from [WeightRecords].
  WeightRecordsProvider call({
    PeriodFilter period = PeriodFilter.month,
  }) {
    return WeightRecordsProvider(
      period: period,
    );
  }

  @override
  WeightRecordsProvider getProviderOverride(
    covariant WeightRecordsProvider provider,
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
  String? get name => r'weightRecordsProvider';
}

/// 体重記録リストを取得するProvider
///
/// Copied from [WeightRecords].
class WeightRecordsProvider extends AutoDisposeAsyncNotifierProviderImpl<
    WeightRecords, List<WeightRecord>> {
  /// 体重記録リストを取得するProvider
  ///
  /// Copied from [WeightRecords].
  WeightRecordsProvider({
    PeriodFilter period = PeriodFilter.month,
  }) : this._internal(
          () => WeightRecords()..period = period,
          from: weightRecordsProvider,
          name: r'weightRecordsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$weightRecordsHash,
          dependencies: WeightRecordsFamily._dependencies,
          allTransitiveDependencies:
              WeightRecordsFamily._allTransitiveDependencies,
          period: period,
        );

  WeightRecordsProvider._internal(
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
  FutureOr<List<WeightRecord>> runNotifierBuild(
    covariant WeightRecords notifier,
  ) {
    return notifier.build(
      period: period,
    );
  }

  @override
  Override overrideWith(WeightRecords Function() create) {
    return ProviderOverride(
      origin: this,
      override: WeightRecordsProvider._internal(
        () => create()..period = period,
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
  AutoDisposeAsyncNotifierProviderElement<WeightRecords, List<WeightRecord>>
      createElement() {
    return _WeightRecordsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is WeightRecordsProvider && other.period == period;
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
mixin WeightRecordsRef
    on AutoDisposeAsyncNotifierProviderRef<List<WeightRecord>> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;
}

class _WeightRecordsProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<WeightRecords,
        List<WeightRecord>> with WeightRecordsRef {
  _WeightRecordsProviderElement(super.provider);

  @override
  PeriodFilter get period => (origin as WeightRecordsProvider).period;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
