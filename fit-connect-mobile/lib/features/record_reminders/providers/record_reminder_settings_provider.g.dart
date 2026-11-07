// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record_reminder_settings_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reminderNotificationPermissionGatewayHash() =>
    r'ec8fa17b13a028fa7da8d70a979737943ec2ae4d';

/// 通知の許可を読む・求める部品（テストでは差し替える）
///
/// Copied from [reminderNotificationPermissionGateway].
@ProviderFor(reminderNotificationPermissionGateway)
final reminderNotificationPermissionGatewayProvider =
    Provider<ReminderNotificationPermissionGateway>.internal(
  reminderNotificationPermissionGateway,
  name: r'reminderNotificationPermissionGatewayProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$reminderNotificationPermissionGatewayHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ReminderNotificationPermissionGatewayRef
    = ProviderRef<ReminderNotificationPermissionGateway>;
String _$reminderNotificationPermissionHash() =>
    r'd0eddc41eef0146fefff3a8856a141f800ebb487';

/// 今の通知の許可の状態（リマインダーの画面の案内用）。
///
/// 画面を開いたとき・前面に戻ったときに読み直すこと（`ref.invalidate`）。
/// [RecordReminderSettingsNotifier.setEnabled] で許可を求めたときは、そこで読み直す
///
/// Copied from [reminderNotificationPermission].
@ProviderFor(reminderNotificationPermission)
final reminderNotificationPermissionProvider =
    AutoDisposeFutureProvider<ReminderNotificationPermission>.internal(
  reminderNotificationPermission,
  name: r'reminderNotificationPermissionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$reminderNotificationPermissionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ReminderNotificationPermissionRef
    = AutoDisposeFutureProviderRef<ReminderNotificationPermission>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
