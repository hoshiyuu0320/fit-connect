import 'dart:async';

/// 通知タップの受け口（type と id）
typedef NotificationTapHandler = void Function(String type, String? id);

/// 通知のタップ1件（type と id）
class NotificationTap {
  const NotificationTap(this.type, this.id);

  /// ローカル通知の payload（`type:id` か `type`）から作る。
  /// 例: `record_reminder:dinner@202611072000` → type = record_reminder、id = dinner@202611072000
  factory NotificationTap.fromPayload(String payload) {
    // 簡易的なペイロード解析（type:id形式）
    final parts = payload.split(':');
    return NotificationTap(parts[0], parts.length >= 2 ? parts[1] : null);
  }

  final String type;
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is NotificationTap && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => 'NotificationTap($type, $id)';
}

/// 通知タップを受け口へ渡す（[NotificationService] の中身。プラグインに依存しない）。
///
/// - FCM の通知とローカル通知のタップは、どちらも [dispatch] を通る
/// - 受け口がまだ無い間に来たタップは、最後の1件だけ取っておき、受け口が設定されたときに渡す。
///   渡すのは設定の直後の microtask（受け口を build の中で設定しても、受け口は build の外で呼ばれる）
/// - アプリを起動したローカル通知（[dispatchLaunchResponse]）と、同じ通知のタップ
///   （[dispatchLocalResponse]）が両方届いても、渡すのは1回だけ
class NotificationTapDispatcher {
  NotificationTapDispatcher({
    void Function(void Function() callback)? scheduleFlush,
    void Function(Object error)? onError,
  })  : _scheduleFlush = scheduleFlush ?? scheduleMicrotask,
        _onError = onError;

  /// 取っておいたタップを渡す時機（既定は microtask。テストでは差し替える）
  final void Function(void Function() callback) _scheduleFlush;

  /// 受け口が例外を投げたとき（ログ用）
  final void Function(Object error)? _onError;

  NotificationTapHandler? _handler;
  NotificationTap? _pendingTap;
  bool _flushScheduled = false;

  /// 起動時の通知を確かめ終えたか（[dispatchLaunchResponse] を呼んだか）
  bool _launchChecked = false;

  /// 起動時の通知を確かめる前に届いたローカル通知のタップ（通知 ID + payload）
  final Set<String> _localTapsBeforeLaunchCheck = {};

  /// 起動時の通知として渡したタップ（通知 ID + payload）。
  /// 次に届いたローカル通知のタップが同じ通知なら、重複として捨てる
  String? _launchTapKey;

  /// 今の受け口
  NotificationTapHandler? get handler => _handler;

  /// 受け口が無い間に来て、まだ渡していないタップ
  NotificationTap? get pendingTap => _pendingTap;

  /// 受け口を設定する（null で外す）。取っておいたタップがあれば渡す
  void setHandler(NotificationTapHandler? handler) {
    _handler = handler;
    if (handler != null && _pendingTap != null) _schedulePendingFlush();
  }

  /// 取っておいたタップを捨てる（ログアウトしたとき。次のログインの受け口へ渡さない）。
  ///
  /// 受け口の設定の直後に渡す予定だったタップも渡さない。受け口・起動時の通知の重複の判定
  /// （[dispatchLaunchResponse] で渡した通知と同じタップは、後から届いても渡さない）はそのまま
  void clearPendingTap() {
    _pendingTap = null;
  }

  /// タップを受け口へ渡す。受け口が無ければ最後の1件として取っておく
  void dispatch(NotificationTap tap) {
    final handler = _handler;
    if (handler == null) {
      _pendingTap = tap;
      return;
    }
    // 取っておいた古いタップは渡さない（後から来たタップを優先する）
    _pendingTap = null;
    _deliver(handler, tap);
  }

  /// FCM の通知のタップ（RemoteMessage.data の type / id）。type が無ければ何もしない
  void dispatchRemoteData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final id = data['id'] as String?;
    if (type == null) return;
    dispatch(NotificationTap(type, id));
  }

  /// ローカル通知のタップ（onDidReceiveNotificationResponse）
  void dispatchLocalResponse({int? notificationId, required String payload}) {
    final key = _localTapKey(notificationId, payload);
    final launchTapKey = _launchTapKey;
    _launchTapKey = null;
    // 起動時の通知として渡し済み
    if (launchTapKey == key) return;
    if (!_launchChecked) _localTapsBeforeLaunchCheck.add(key);
    dispatch(NotificationTap.fromPayload(payload));
  }

  /// アプリを起動したローカル通知（getNotificationAppLaunchDetails）。最初の1回だけ扱う。
  /// 通知で起動していなければ [payload] は null（起動前後のタップとの重複判定だけを終える）
  void dispatchLaunchResponse({int? notificationId, String? payload}) {
    if (_launchChecked) return;
    _launchChecked = true;
    final tapsBeforeCheck = Set<String>.of(_localTapsBeforeLaunchCheck);
    _localTapsBeforeLaunchCheck.clear();
    if (payload == null) return;

    final key = _localTapKey(notificationId, payload);
    // 同じ通知のタップとして渡し済み
    if (tapsBeforeCheck.contains(key)) return;
    _launchTapKey = key;
    dispatch(NotificationTap.fromPayload(payload));
  }

  void _schedulePendingFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    _scheduleFlush(() {
      _flushScheduled = false;
      final handler = _handler;
      final tap = _pendingTap;
      // 渡す前に受け口が外された・新しいタップを渡し済みのときは何もしない
      if (handler == null || tap == null) return;
      _pendingTap = null;
      _deliver(handler, tap);
    });
  }

  void _deliver(NotificationTapHandler handler, NotificationTap tap) {
    try {
      handler(tap.type, tap.id);
    } catch (e) {
      _onError?.call(e);
    }
  }

  static String _localTapKey(int? notificationId, String payload) =>
      '${notificationId ?? ''}|$payload';
}
