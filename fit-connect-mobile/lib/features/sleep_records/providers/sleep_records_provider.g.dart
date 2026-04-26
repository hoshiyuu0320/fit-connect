// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sleep_records_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$todaySleepRecordHash() => r'f1b4b694b513f87f7ac7c7113ceeabcc0a56cc91';

/// 今日の睡眠レコード（1件のみ）
///
/// Copied from [todaySleepRecord].
@ProviderFor(todaySleepRecord)
final todaySleepRecordProvider =
    AutoDisposeFutureProvider<SleepRecord?>.internal(
  todaySleepRecord,
  name: r'todaySleepRecordProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$todaySleepRecordHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TodaySleepRecordRef = AutoDisposeFutureProviderRef<SleepRecord?>;
String _$recentSleepRecordsHash() =>
    r'4ba18e075dfcfa274912f90e4dfc4ce0939b4c5f';

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

/// 直近 N 日間の睡眠レコード（週間グラフ用）
///
/// Copied from [recentSleepRecords].
@ProviderFor(recentSleepRecords)
const recentSleepRecordsProvider = RecentSleepRecordsFamily();

/// 直近 N 日間の睡眠レコード（週間グラフ用）
///
/// Copied from [recentSleepRecords].
class RecentSleepRecordsFamily extends Family<AsyncValue<List<SleepRecord>>> {
  /// 直近 N 日間の睡眠レコード（週間グラフ用）
  ///
  /// Copied from [recentSleepRecords].
  const RecentSleepRecordsFamily();

  /// 直近 N 日間の睡眠レコード（週間グラフ用）
  ///
  /// Copied from [recentSleepRecords].
  RecentSleepRecordsProvider call({
    int days = 7,
  }) {
    return RecentSleepRecordsProvider(
      days: days,
    );
  }

  @override
  RecentSleepRecordsProvider getProviderOverride(
    covariant RecentSleepRecordsProvider provider,
  ) {
    return call(
      days: provider.days,
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
  String? get name => r'recentSleepRecordsProvider';
}

/// 直近 N 日間の睡眠レコード（週間グラフ用）
///
/// Copied from [recentSleepRecords].
class RecentSleepRecordsProvider
    extends AutoDisposeFutureProvider<List<SleepRecord>> {
  /// 直近 N 日間の睡眠レコード（週間グラフ用）
  ///
  /// Copied from [recentSleepRecords].
  RecentSleepRecordsProvider({
    int days = 7,
  }) : this._internal(
          (ref) => recentSleepRecords(
            ref as RecentSleepRecordsRef,
            days: days,
          ),
          from: recentSleepRecordsProvider,
          name: r'recentSleepRecordsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$recentSleepRecordsHash,
          dependencies: RecentSleepRecordsFamily._dependencies,
          allTransitiveDependencies:
              RecentSleepRecordsFamily._allTransitiveDependencies,
          days: days,
        );

  RecentSleepRecordsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.days,
  }) : super.internal();

  final int days;

  @override
  Override overrideWith(
    FutureOr<List<SleepRecord>> Function(RecentSleepRecordsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: RecentSleepRecordsProvider._internal(
        (ref) => create(ref as RecentSleepRecordsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        days: days,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<SleepRecord>> createElement() {
    return _RecentSleepRecordsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is RecentSleepRecordsProvider && other.days == days;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, days.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin RecentSleepRecordsRef on AutoDisposeFutureProviderRef<List<SleepRecord>> {
  /// The parameter `days` of this provider.
  int get days;
}

class _RecentSleepRecordsProviderElement
    extends AutoDisposeFutureProviderElement<List<SleepRecord>>
    with RecentSleepRecordsRef {
  _RecentSleepRecordsProviderElement(super.provider);

  @override
  int get days => (origin as RecentSleepRecordsProvider).days;
}

String _$sleepRecordsHash() => r'75964f70337914deb614f5b32bdc31c340cc86c4';

abstract class _$SleepRecords
    extends BuildlessAutoDisposeAsyncNotifier<List<SleepRecord>> {
  late final int limit;

  FutureOr<List<SleepRecord>> build({
    int limit = 30,
  });
}

/// 睡眠レコードリスト
///
/// Copied from [SleepRecords].
@ProviderFor(SleepRecords)
const sleepRecordsProvider = SleepRecordsFamily();

/// 睡眠レコードリスト
///
/// Copied from [SleepRecords].
class SleepRecordsFamily extends Family<AsyncValue<List<SleepRecord>>> {
  /// 睡眠レコードリスト
  ///
  /// Copied from [SleepRecords].
  const SleepRecordsFamily();

  /// 睡眠レコードリスト
  ///
  /// Copied from [SleepRecords].
  SleepRecordsProvider call({
    int limit = 30,
  }) {
    return SleepRecordsProvider(
      limit: limit,
    );
  }

  @override
  SleepRecordsProvider getProviderOverride(
    covariant SleepRecordsProvider provider,
  ) {
    return call(
      limit: provider.limit,
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
  String? get name => r'sleepRecordsProvider';
}

/// 睡眠レコードリスト
///
/// Copied from [SleepRecords].
class SleepRecordsProvider extends AutoDisposeAsyncNotifierProviderImpl<
    SleepRecords, List<SleepRecord>> {
  /// 睡眠レコードリスト
  ///
  /// Copied from [SleepRecords].
  SleepRecordsProvider({
    int limit = 30,
  }) : this._internal(
          () => SleepRecords()..limit = limit,
          from: sleepRecordsProvider,
          name: r'sleepRecordsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$sleepRecordsHash,
          dependencies: SleepRecordsFamily._dependencies,
          allTransitiveDependencies:
              SleepRecordsFamily._allTransitiveDependencies,
          limit: limit,
        );

  SleepRecordsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.limit,
  }) : super.internal();

  final int limit;

  @override
  FutureOr<List<SleepRecord>> runNotifierBuild(
    covariant SleepRecords notifier,
  ) {
    return notifier.build(
      limit: limit,
    );
  }

  @override
  Override overrideWith(SleepRecords Function() create) {
    return ProviderOverride(
      origin: this,
      override: SleepRecordsProvider._internal(
        () => create()..limit = limit,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        limit: limit,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<SleepRecords, List<SleepRecord>>
      createElement() {
    return _SleepRecordsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SleepRecordsProvider && other.limit == limit;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, limit.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin SleepRecordsRef
    on AutoDisposeAsyncNotifierProviderRef<List<SleepRecord>> {
  /// The parameter `limit` of this provider.
  int get limit;
}

class _SleepRecordsProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<SleepRecords,
        List<SleepRecord>> with SleepRecordsRef {
  _SleepRecordsProviderElement(super.provider);

  @override
  int get limit => (origin as SleepRecordsProvider).limit;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
