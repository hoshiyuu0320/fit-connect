// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nutrition_trend_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$nutritionTrendHash() => r'0000000000000000000000000000000000000000';

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

/// 体重 + 食事の日次集計（栄養トレンド）を返す Provider。
///
/// 既存の [weightRecordsProvider] / [mealRecordsProvider] を watch し、
/// `period` の範囲 (startDate 〜 today) の連続した日付配列に対して
/// 日単位の体重 / カロリー / PFC を集計する。
///
/// Copied from [nutritionTrend].
@ProviderFor(nutritionTrend)
const nutritionTrendProvider = NutritionTrendFamily();

/// 体重 + 食事の日次集計（栄養トレンド）を返す Provider。
///
/// Copied from [nutritionTrend].
class NutritionTrendFamily extends Family<AsyncValue<List<DailyNutritionStat>>> {
  /// 体重 + 食事の日次集計（栄養トレンド）を返す Provider。
  ///
  /// Copied from [nutritionTrend].
  const NutritionTrendFamily();

  /// 体重 + 食事の日次集計（栄養トレンド）を返す Provider。
  ///
  /// Copied from [nutritionTrend].
  NutritionTrendProvider call({
    PeriodFilter period = PeriodFilter.month,
  }) {
    return NutritionTrendProvider(
      period: period,
    );
  }

  @override
  NutritionTrendProvider getProviderOverride(
    covariant NutritionTrendProvider provider,
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
  String? get name => r'nutritionTrendProvider';
}

/// 体重 + 食事の日次集計（栄養トレンド）を返す Provider。
///
/// Copied from [nutritionTrend].
class NutritionTrendProvider
    extends AutoDisposeFutureProvider<List<DailyNutritionStat>> {
  /// 体重 + 食事の日次集計（栄養トレンド）を返す Provider。
  ///
  /// Copied from [nutritionTrend].
  NutritionTrendProvider({
    PeriodFilter period = PeriodFilter.month,
  }) : this._internal(
          (ref) => nutritionTrend(
            ref as NutritionTrendRef,
            period: period,
          ),
          from: nutritionTrendProvider,
          name: r'nutritionTrendProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$nutritionTrendHash,
          dependencies: NutritionTrendFamily._dependencies,
          allTransitiveDependencies:
              NutritionTrendFamily._allTransitiveDependencies,
          period: period,
        );

  NutritionTrendProvider._internal(
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
    FutureOr<List<DailyNutritionStat>> Function(NutritionTrendRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: NutritionTrendProvider._internal(
        (ref) => create(ref as NutritionTrendRef),
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
  AutoDisposeFutureProviderElement<List<DailyNutritionStat>> createElement() {
    return _NutritionTrendProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is NutritionTrendProvider && other.period == period;
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
mixin NutritionTrendRef
    on AutoDisposeFutureProviderRef<List<DailyNutritionStat>> {
  /// The parameter `period` of this provider.
  PeriodFilter get period;
}

class _NutritionTrendProviderElement
    extends AutoDisposeFutureProviderElement<List<DailyNutritionStat>>
    with NutritionTrendRef {
  _NutritionTrendProviderElement(super.provider);

  @override
  PeriodFilter get period => (origin as NutritionTrendProvider).period;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
