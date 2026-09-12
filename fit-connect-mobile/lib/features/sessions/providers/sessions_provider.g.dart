// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sessions_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sessionRepositoryHash() => r'bc62a5d272a12a7ca16598ab38ff078bf8e1e656';

/// SessionRepositoryのProvider
///
/// Copied from [sessionRepository].
@ProviderFor(sessionRepository)
final sessionRepositoryProvider =
    AutoDisposeProvider<SessionRepository>.internal(
  sessionRepository,
  name: r'sessionRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sessionRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SessionRepositoryRef = AutoDisposeProviderRef<SessionRepository>;
String _$upcomingSessionsHash() => r'3273cac768663660809640b70e50449bca55a58e';

/// 今後のセッション一覧を取得するProvider（開始時刻の昇順）。
/// 「今後」＝終了時刻が未来（SessionRepository の仕分け規則を参照）
///
/// Copied from [upcomingSessions].
@ProviderFor(upcomingSessions)
final upcomingSessionsProvider =
    AutoDisposeFutureProvider<List<SessionModel>>.internal(
  upcomingSessions,
  name: r'upcomingSessionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$upcomingSessionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpcomingSessionsRef = AutoDisposeFutureProviderRef<List<SessionModel>>;
String _$pastSessionsHash() => r'292ea8c99f51b7dd31377fcbac9762b70918f064';

/// 過去のセッション一覧を取得するProvider（開始時刻の降順・最大50件）。
/// 「過去」＝終了時刻が過去（SessionRepository の仕分け規則を参照）
///
/// Copied from [pastSessions].
@ProviderFor(pastSessions)
final pastSessionsProvider =
    AutoDisposeFutureProvider<List<SessionModel>>.internal(
  pastSessions,
  name: r'pastSessionsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$pastSessionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PastSessionsRef = AutoDisposeFutureProviderRef<List<SessionModel>>;
String _$nextSessionHash() => r'3472df5b466a57a05dd1ec3f02954dec84910851';

/// 直近の次回セッションを取得するProvider（予定が無ければnull）。
///
/// 「今後」にはキャンセル/完了済みも時系列どおり含まれるが、ホームの
/// 「次回のセッション」としては予定として生きているものを指したいので、
/// 終了扱いのステータスは読み飛ばす（一覧の「今後」には残り続ける）。
///
/// Copied from [nextSession].
@ProviderFor(nextSession)
final nextSessionProvider = AutoDisposeFutureProvider<SessionModel?>.internal(
  nextSession,
  name: r'nextSessionProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$nextSessionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NextSessionRef = AutoDisposeFutureProviderRef<SessionModel?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
