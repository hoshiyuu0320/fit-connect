// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_preferences_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$notificationPreferencesHash() =>
    r'4b0a467094482ff23dbd194d3c96c6f598f90f60';

/// 通知設定の状態管理
///
/// notification_preferences テーブルを RLS 経由（本人行のみ）で select/upsert する
///
/// Copied from [NotificationPreferences].
@ProviderFor(NotificationPreferences)
final notificationPreferencesProvider = AutoDisposeAsyncNotifierProvider<
    NotificationPreferences, NotificationPreferencesState>.internal(
  NotificationPreferences.new,
  name: r'notificationPreferencesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$notificationPreferencesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$NotificationPreferences
    = AutoDisposeAsyncNotifier<NotificationPreferencesState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
