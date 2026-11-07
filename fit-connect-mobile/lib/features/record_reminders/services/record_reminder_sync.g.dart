// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record_reminder_sync.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$recordReminderSettingsStorageHash() =>
    r'e3dd6a42d669be840d442be9e56228b286510a45';

/// 記録のリマインダーの設定の保存先（端末の SharedPreferences。アカウントごと）
///
/// Copied from [recordReminderSettingsStorage].
@ProviderFor(recordReminderSettingsStorage)
final recordReminderSettingsStorageProvider =
    Provider<RecordReminderSettingsStorage>.internal(
  recordReminderSettingsStorage,
  name: r'recordReminderSettingsStorageProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$recordReminderSettingsStorageHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RecordReminderSettingsStorageRef
    = ProviderRef<RecordReminderSettingsStorage>;
String _$recordReminderSyncHash() =>
    r'fbd816596196d4950c3c4e92c58878ebaa074c77';

/// 記録のリマインダーの予約し直し（アプリで1つ。送ったタグからの推定と読めた結果をメモリに持つ）
///
/// Copied from [recordReminderSync].
@ProviderFor(recordReminderSync)
final recordReminderSyncProvider = Provider<RecordReminderSync>.internal(
  recordReminderSync,
  name: r'recordReminderSyncProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$recordReminderSyncHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RecordReminderSyncRef = ProviderRef<RecordReminderSync>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
