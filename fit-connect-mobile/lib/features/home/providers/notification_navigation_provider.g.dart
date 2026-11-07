// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_navigation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$notificationNavigationHash() =>
    r'2b950592fe1166d3cfbfc4c3bdb55f024b2d97b4';

/// 通知を押したときの「開く先」の要求
///
/// 通知タップの受け口が [request] で置き、MainScreen が監視して実行し、[consume] で消す。
/// MainScreen がまだ無い（起動中・認証待ち）ときは要求が残り、MainScreen が現れたときに実行される。
/// 監視する画面が無い間も消えないよう keepAlive にする
///
/// Copied from [NotificationNavigation].
@ProviderFor(NotificationNavigation)
final notificationNavigationProvider = NotifierProvider<NotificationNavigation,
    NotificationNavigationRequest?>.internal(
  NotificationNavigation.new,
  name: r'notificationNavigationProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$notificationNavigationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$NotificationNavigation = Notifier<NotificationNavigationRequest?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
