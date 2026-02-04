// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registration_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$registrationNotifierHash() =>
    r'6ec2b5fdb9b9689bb4dcd20911784423233a6b75';

/// 登録フロー中の状態を管理するProvider
/// keepAlive: true で画面遷移時も状態を保持
///
/// Copied from [RegistrationNotifier].
@ProviderFor(RegistrationNotifier)
final registrationNotifierProvider =
    NotifierProvider<RegistrationNotifier, RegistrationState>.internal(
  RegistrationNotifier.new,
  name: r'registrationNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$registrationNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$RegistrationNotifier = Notifier<RegistrationState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
