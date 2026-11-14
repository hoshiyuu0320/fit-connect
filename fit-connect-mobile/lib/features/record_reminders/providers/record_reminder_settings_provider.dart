import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/record_reminder_sync.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';

part 'record_reminder_settings_provider.g.dart';

/// 通知の許可の状態（記録のリマインダーの画面の案内に使う。設計 §7）
enum ReminderNotificationPermission {
  /// 許可されている（仮の許可 provisional を含む）
  granted,

  /// 拒否されている（設定アプリでしか変えられない）
  denied,

  /// まだ聞いていない
  notDetermined,

  /// 分からない（Firebase が初期化されていない・iOS/Android 以外・読めなかった）
  unknown,
}

/// 項目をオンにしたときの通知の許可（画面が「通知がオフになっています」の案内を出すか決める）
enum ReminderPermissionOutcome {
  /// 許可されている（求めて許可された場合を含む）
  granted,

  /// 拒否されている（求めて断られた場合を含む）。設定はオンのまま保存してある
  denied,

  /// 分からない（Firebase が初期化されていない・iOS/Android 以外・オフにしたとき）
  unknown,
}

/// Firebase Messaging の許可の状態を [ReminderNotificationPermission] に直す
ReminderNotificationPermission reminderNotificationPermissionOf(
  AuthorizationStatus status,
) {
  switch (status) {
    case AuthorizationStatus.authorized:
    case AuthorizationStatus.provisional:
      return ReminderNotificationPermission.granted;
    case AuthorizationStatus.denied:
      return ReminderNotificationPermission.denied;
    case AuthorizationStatus.notDetermined:
      return ReminderNotificationPermission.notDetermined;
  }
}

/// 通知の許可を読む・求める（Firebase Messaging と NotificationService の薄い包み）。
///
/// 許可の状態はオンボーディングと同じく Firebase Messaging で読む。Firebase の呼び出しは
/// 引数で差し替えられる（テスト用。省略時は本物）
class ReminderNotificationPermissionGateway {
  ReminderNotificationPermissionGateway({
    bool Function()? isFirebaseInitialized,
    Future<AuthorizationStatus> Function()? authorizationStatus,
    Future<NotificationSetupResult> Function(String userId)? requestPermission,
  })  : _isFirebaseInitialized =
            isFirebaseInitialized ?? _defaultIsFirebaseInitialized,
        _authorizationStatus =
            authorizationStatus ?? _defaultAuthorizationStatus,
        _requestPermission = requestPermission ?? _defaultRequestPermission;

  final bool Function() _isFirebaseInitialized;
  final Future<AuthorizationStatus> Function() _authorizationStatus;
  final Future<NotificationSetupResult> Function(String userId)
      _requestPermission;

  static bool _defaultIsFirebaseInitialized() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<AuthorizationStatus> _defaultAuthorizationStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// オンボーディングと同じ（OS の許可を求め、許可されたら push のトークンも登録する）
  static Future<NotificationSetupResult> _defaultRequestPermission(
    String userId,
  ) =>
      NotificationService.requestPermissionAndRegister(
        userId: userId,
        userType: 'client',
      );

  /// 許可を確かめられる状態か（iOS/Android で、Firebase が初期化されている）
  bool get _isAvailable =>
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android) &&
      _isFirebaseInitialized();

  /// 今の許可の状態（ダイアログは出さない）。確かめられない・読めないときは unknown
  Future<ReminderNotificationPermission> read() async {
    if (!_isAvailable) return ReminderNotificationPermission.unknown;
    try {
      return reminderNotificationPermissionOf(await _authorizationStatus());
    } catch (e) {
      debugPrint('[RecordReminderSettings] 通知の許可の取得エラー: $e');
      return ReminderNotificationPermission.unknown;
    }
  }

  /// [permission]（[read] の結果）のときに、オンにする操作で許可を求めるか。
  ///
  /// 未決定なら求める。Android は Firebase Messaging が「未決定」を返さず、一度も聞いていない
  /// Android 13 以降の端末も denied になるので、Android では denied でも求める
  /// （断り続けた後なら、OS はダイアログを出さずに denied を返す）。
  /// iOS の denied は設定アプリでしか変えられないので求めない
  bool shouldRequest(ReminderNotificationPermission permission) {
    switch (permission) {
      case ReminderNotificationPermission.notDetermined:
        return true;
      case ReminderNotificationPermission.denied:
        return defaultTargetPlatform == TargetPlatform.android;
      case ReminderNotificationPermission.granted:
      case ReminderNotificationPermission.unknown:
        return false;
    }
  }

  /// OS の許可を求める（[shouldRequest] が true のときだけ呼ぶこと）
  Future<NotificationSetupResult> request(String userId) =>
      _requestPermission(userId);
}

/// 通知の許可を読む・求める部品（テストでは差し替える）
@Riverpod(keepAlive: true)
ReminderNotificationPermissionGateway reminderNotificationPermissionGateway(
    ReminderNotificationPermissionGatewayRef ref) {
  return ReminderNotificationPermissionGateway();
}

/// 今の通知の許可の状態（リマインダーの画面の案内用）。
///
/// 画面を開いたとき・前面に戻ったときに読み直すこと（`ref.invalidate`）。
/// [RecordReminderSettingsNotifier.setEnabled] で許可を求めたときは、そこで読み直す
@riverpod
Future<ReminderNotificationPermission> reminderNotificationPermission(
    ReminderNotificationPermissionRef ref) {
  return ref.watch(reminderNotificationPermissionGatewayProvider).read();
}

/// 今ログインしているアカウントの、記録のリマインダーの設定（端末に保存。設計 §3）。
///
/// ログインしているユーザーが変わると読み直す（ログインしていなければ既定 = すべてオフ）。
/// 設定を変えるとすぐ保存し、端末の予約をし直す（RecordReminderSync.refresh）。
///
/// 設定のモデルが `RecordReminderSettings` という名前を持つので、コード生成（クラス名から
/// `recordReminderSettingsNotifierProvider` になる）ではなく、この名前で宣言する
final recordReminderSettingsProvider = AsyncNotifierProvider<
    RecordReminderSettingsNotifier, RecordReminderSettings>(
  RecordReminderSettingsNotifier.new,
  name: 'recordReminderSettingsProvider',
);

/// [recordReminderSettingsProvider] の中身
class RecordReminderSettingsNotifier
    extends AsyncNotifier<RecordReminderSettings> {
  /// 今の設定の持ち主（auth のユーザー ID。ログインしていなければ null）
  String? _userId;

  @override
  Future<RecordReminderSettings> build() async {
    final storage = ref.watch(recordReminderSettingsStorageProvider);
    final user = await ref.watch(authNotifierProvider.future);
    _userId = user?.id;
    if (user == null) return RecordReminderSettings.defaults();
    return storage.load(user.id);
  }

  /// [kind] のオン・オフを変えて保存し、予約し直す。
  ///
  /// オンにするとき、通知の許可がまだ未決定なら許可を求める（オンボーディングと同じ。
  /// Android は未決定を区別できないので拒否でも求める。[ReminderNotificationPermissionGateway.shouldRequest]）。
  /// 拒否されていてもオンのまま保存する（画面が設定アプリへの案内を出す。設計 §7）。
  /// 返す値は、オンにしたときの許可（オフにしたときは確かめないので unknown）。
  /// 保存に失敗したら元の設定に戻して例外を投げる
  Future<ReminderPermissionOutcome> setEnabled(
    ReminderKind kind,
    bool enabled,
  ) async {
    final current = await future;
    final userId = _requireUserId();
    await _save(
      userId,
      current.withSetting(
        kind,
        current.settingOf(kind).copyWith(enabled: enabled),
      ),
    );
    final outcome = enabled
        ? await _ensurePermission(userId)
        : ReminderPermissionOutcome.unknown;
    _refreshReminders();
    return outcome;
  }

  /// [kind] の時刻を変えて保存し、予約し直す。保存に失敗したら元の設定に戻して例外を投げる
  Future<void> setTime(ReminderKind kind, ReminderTime time) async {
    final current = await future;
    final userId = _requireUserId();
    await _save(
      userId,
      current.withSetting(kind, current.settingOf(kind).copyWith(time: time)),
    );
    _refreshReminders();
  }

  String _requireUserId() {
    final userId = _userId;
    if (userId == null) {
      throw StateError('ログインしていないため、記録のリマインダーの設定を保存できません');
    }
    return userId;
  }

  /// 画面にすぐ反映してから保存する（失敗したら元に戻す）
  Future<void> _save(String userId, RecordReminderSettings settings) async {
    final previous = state;
    state = AsyncData(settings);
    try {
      await ref.read(recordReminderSettingsStorageProvider).save(
            userId,
            settings,
          );
    } catch (e) {
      debugPrint('[RecordReminderSettings] 設定の保存エラー: $e');
      state = previous;
      rethrow;
    }
  }

  /// オンにしたときの通知の許可。未決定（Android は拒否も）なら求める（求めたら許可の状態を読み直させる）
  Future<ReminderPermissionOutcome> _ensurePermission(String userId) async {
    final gateway = ref.read(reminderNotificationPermissionGatewayProvider);
    final permission = await gateway.read();
    if (!gateway.shouldRequest(permission)) return _outcomeOf(permission);

    final result = await gateway.request(userId);
    ref.invalidate(reminderNotificationPermissionProvider);
    switch (result) {
      case NotificationSetupResult.granted:
        return ReminderPermissionOutcome.granted;
      case NotificationSetupResult.denied:
        return ReminderPermissionOutcome.denied;
      case NotificationSetupResult.registrationFailed:
        // push のトークンの登録だけが失敗したのか、許可を求めること自体が失敗したのかを
        // 区別できないので、許可の状態を読み直して決める
        return _outcomeOf(await gateway.read());
    }
  }

  static ReminderPermissionOutcome _outcomeOf(
    ReminderNotificationPermission permission,
  ) {
    switch (permission) {
      case ReminderNotificationPermission.granted:
        return ReminderPermissionOutcome.granted;
      case ReminderNotificationPermission.denied:
        return ReminderPermissionOutcome.denied;
      case ReminderNotificationPermission.notDetermined:
      case ReminderNotificationPermission.unknown:
        return ReminderPermissionOutcome.unknown;
    }
  }

  /// 端末の予約をし直す（待たない。失敗はログだけ）
  void _refreshReminders() {
    unawaited(
      ref.read(recordReminderSyncProvider).refresh(reason: 'settings_changed'),
    );
  }
}

/// 設定画面の「記録のリマインダー」の行の値。
/// オンの項目が無ければ「オフ」、あれば表示名を項目の並びで「・」でつなぐ（例「体重・夕食」）
String reminderSummaryLabel(RecordReminderSettings settings) {
  final kinds = settings.enabledKinds;
  if (kinds.isEmpty) return 'オフ';
  return kinds.map((kind) => kind.label).join('・');
}
