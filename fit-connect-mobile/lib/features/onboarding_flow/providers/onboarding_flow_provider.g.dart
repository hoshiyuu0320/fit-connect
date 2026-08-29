// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_flow_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$onboardingRepositoryHash() =>
    r'0ccf64c4fecf9eff6d5babe7137761768f9504dd';

/// OnboardingRepository のプロバイダ
///
/// Copied from [onboardingRepository].
@ProviderFor(onboardingRepository)
final onboardingRepositoryProvider =
    AutoDisposeProvider<OnboardingRepository>.internal(
  onboardingRepository,
  name: r'onboardingRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$onboardingRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OnboardingRepositoryRef = AutoDisposeProviderRef<OnboardingRepository>;
String _$hasSentFirstMessageHash() =>
    r'812a822b927e631803a1a8b63dc3badf152e382e';

/// トレーナーへメッセージを送信したことがあるか（はじめの3ステップ判定用）
///
/// Copied from [hasSentFirstMessage].
@ProviderFor(hasSentFirstMessage)
final hasSentFirstMessageProvider = AutoDisposeFutureProvider<bool>.internal(
  hasSentFirstMessage,
  name: r'hasSentFirstMessageProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$hasSentFirstMessageHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HasSentFirstMessageRef = AutoDisposeFutureProviderRef<bool>;
String _$gettingStartedCardDismissedHash() =>
    r'c4f04481ef148e848b7636d9dca4dd0c6fb5c005';

/// はじめの3ステップカードを手動で閉じたかどうか
///
/// Copied from [GettingStartedCardDismissed].
@ProviderFor(GettingStartedCardDismissed)
final gettingStartedCardDismissedProvider = AutoDisposeAsyncNotifierProvider<
    GettingStartedCardDismissed, bool>.internal(
  GettingStartedCardDismissed.new,
  name: r'gettingStartedCardDismissedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$gettingStartedCardDismissedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$GettingStartedCardDismissed = AutoDisposeAsyncNotifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
