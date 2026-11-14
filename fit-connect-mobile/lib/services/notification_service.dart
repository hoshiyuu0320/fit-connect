import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, visibleForTesting;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:fit_connect_mobile/services/notification_tap_dispatcher.dart';

// バックグラウンドハンドラ（トップレベル関数）
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
      '[NotificationService] バックグラウンドメッセージ: ${message.notification?.title}');
}

/// 通知セットアップの結果
///
/// [denied] は OS 権限の拒否、[registrationFailed] は権限は取れたが
/// トークン登録に失敗（APNs トークン未着・ネットワークエラーなど）。
/// UI の文言を出し分けるために区別する。
enum NotificationSetupResult { granted, denied, registrationFailed }

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// 記録のリマインダー（予約するローカル通知）の Android 通知チャンネル
  static const AndroidNotificationChannel recordReminderChannel =
      AndroidNotificationChannel(
    'record_reminder',
    '記録のリマインダー',
    description: '記録を忘れないためのお知らせ',
    importance: Importance.defaultImportance,
  );

  // トークンリフレッシュ時に使用
  static String? _currentUserId;
  static String? _currentUserType;

  // 直近に保存したFCMトークン（リフレッシュ時の旧 device_tokens 行削除に使用）
  static String? _currentToken;

  // ローカル通知の初期化（ensureLocalNotificationsInitialized。起動ごとに1回）
  static Future<void>? _localNotificationsInitialization;

  // 通知タップの受け渡し（FCM・ローカル通知とも。受け口が無い間は最後の1件を取っておく）
  static final NotificationTapDispatcher _tapDispatcher =
      NotificationTapDispatcher(
    onError: (e) => debugPrint('[NotificationService] 通知タップエラー: $e'),
  );

  /// 通知タップの受け口を設定する（null で外す）
  ///
  /// 受け口が無い間に来たタップ（FCM・ローカル通知とも、最後の1件）は取っておき、
  /// ここで受け口が設定されたときに渡す（設定の直後の microtask で。build の中で設定してもよい）。
  /// 受け口がある間に来たタップは、来たときにそのまま渡す
  static void setNotificationTapHandler(
      void Function(String type, String? id)? handler) {
    _tapDispatcher.setHandler(handler);
  }

  /// 受け口が無い間に取っておいたタップ（FCM・ローカル通知とも）を捨てる。
  ///
  /// ログアウトしたときに呼ぶ（ログアウトした端末で押された通知を、次のログインへ持ち越さない）。
  /// 受け口・起動時の通知の重複の判定はそのまま
  static void clearPendingTap() => _tapDispatcher.clearPendingTap();

  /// 通知タップの受け口（[setNotificationTapHandler] と同じ。代入しても取っておいたタップを渡す）
  static void Function(String type, String? id)? get onNotificationTap =>
      _tapDispatcher.handler;

  static set onNotificationTap(
          void Function(String type, String? id)? handler) =>
      setNotificationTapHandler(handler);

  /// ローカル通知のプラグイン（記録のリマインダーの予約に使う）。
  /// 使う前に [ensureLocalNotificationsInitialized] を await すること
  static FlutterLocalNotificationsPlugin get localNotifications =>
      _localNotifications;

  /// テスト用: 通知タップの受け渡し
  @visibleForTesting
  static NotificationTapDispatcher get tapDispatcherForTesting =>
      _tapDispatcher;

  /// 初期化
  ///
  /// 注意: ここでは OS の通知権限リクエストを行わない（オンボーディングの
  /// プライミング画面から [requestPermissionAndRegister] を呼ぶ設計）。
  /// 既に権限が許可済みの場合のみ、従来どおりトークン取得までを実行する
  /// （既存ユーザーの通知を壊さないため）。
  static Future<void> initialize() async {
    try {
      // APNs 登録要求を明示的に発火させる（iOS 実機で FCM トークンが取れない
      // 問題の修正）。firebase_messaging 16.x は scene 接続時のネイティブ
      // セットアップで registerForRemoteNotifications を
      // `[FIRMessaging messaging].isAutoInitEnabled` でガードしているが、
      // 本アプリは Firebase を Dart 側で初期化するためその時点では
      // FIRMessaging が nil で常にスキップされる（flutter/flutter#185048 の亜種）。
      // setAutoInitEnabled(true) はネイティブ側で
      // registerForRemoteNotifications + ensureAPNSTokenSetting を呼ぶため、
      // Firebase 初期化後のここで毎起動時に呼び出して登録を保証する。
      // （APNs 登録は通知権限が未許可でも可能・冪等）
      await _messaging.setAutoInitEnabled(true);

      // 現在の権限状態を確認（ダイアログは表示されない）
      final settings = await _messaging.getNotificationSettings();
      final isAuthorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;

      debugPrint('[NotificationService] 通知権限: ${settings.authorizationStatus}');

      if (isAuthorized) {
        // iOS フォアグラウンド通知設定
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // FCMトークン取得（iOS は APNs トークンの到着を待ってから）
        if (await _waitForApnsToken()) {
          final token = await _messaging.getToken();
          debugPrint('[NotificationService] FCM Token: $token');
        } else {
          debugPrint('[NotificationService] APNsトークン未取得のため取得をスキップ');
        }
      }

      // ローカル通知プラグイン初期化（済んでいれば何もしない）
      await ensureLocalNotificationsInitialized();

      // フォアグラウンド通知リスナー
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // バックグラウンド通知
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // 通知タップハンドリング（アプリがバックグラウンドから開かれた場合）
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // 通知タップハンドリング（アプリが終了状態から開かれた場合）
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      // トークンリフレッシュリスナー
      _messaging.onTokenRefresh.listen(_handleTokenRefresh);

      debugPrint('[NotificationService] 初期化完了');
    } catch (e) {
      debugPrint('[NotificationService] 初期化エラー: $e');
    }
  }

  /// OS の通知権限をリクエストし、許可された場合はトークン登録まで行う
  ///
  /// オンボーディングの通知プライミング画面など、ユーザーに価値を説明した後の
  /// 明示的なタイミングで呼び出すこと（起動時に自動で呼ばない）。
  static Future<NotificationSetupResult> requestPermissionAndRegister({
    required String userId,
    required String userType,
  }) async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint(
          '[NotificationService] 権限リクエスト結果: ${settings.authorizationStatus}');

      final isAuthorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!isAuthorized) return NotificationSetupResult.denied;

      // iOS フォアグラウンド通知設定
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 許可された場合のみトークンを登録。
      // 権限は取れたが登録に失敗した場合（APNs トークン未着など）は
      // denied と区別して返す（誤って「許可されていません」と表示しないため）
      return await saveTokenToSupabase(userId, userType)
          ? NotificationSetupResult.granted
          : NotificationSetupResult.registrationFailed;
    } catch (e) {
      debugPrint('[NotificationService] 権限リクエストエラー: $e');
      return NotificationSetupResult.registrationFailed;
    }
  }

  /// ローカル通知の初期化（何度・同時に呼んでもよい。初期化は起動ごとに1回）
  ///
  /// - 時間帯を `Asia/Tokyo` に固定する（記録のリマインダーは日本時間で予約する）
  /// - iOS/Android: 通知チャンネル（重要な通知・記録のリマインダー）を作り、プラグインを初期化する。
  ///   アプリがローカル通知のタップで起動していれば、そのタップを通知タップの受け口へ渡す
  ///
  /// Firebase は使わない（Firebase の初期化に失敗した端末でも使える）。
  /// 失敗はログに出すだけで、例外は投げない
  static Future<void> ensureLocalNotificationsInitialized() =>
      _localNotificationsInitialization ??= _initializeLocalNotifications();

  /// ローカル通知プラグイン初期化
  static Future<void> _initializeLocalNotifications() async {
    // 時間帯（記録のリマインダーの予約・「今日」の判定は日本時間）
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
    } catch (e) {
      debugPrint('[NotificationService] 時間帯の初期化エラー: $e');
    }

    // iOS/Androidのみ
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      // Android通知チャンネル作成
      const androidChannel = AndroidNotificationChannel(
        'high_importance_channel',
        '重要な通知',
        description: 'このチャンネルは重要な通知に使用されます',
        importance: Importance.high,
      );

      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(androidChannel);
      // 記録のリマインダー（予約するローカル通知）
      await androidPlugin?.createNotificationChannel(recordReminderChannel);

      // 初期化設定
      // iOS: requestXxxPermission はデフォルト true で初期化時に OS の許可
      // ダイアログが出てしまうため明示的に false にする（権限リクエストは
      // requestPermissionAndRegister に一本化）
      // Android の小アイコンは透明背景の単色 drawable を使う。
      const initializationSettingsAndroid =
          AndroidInitializationSettings('ic_stat_fit_connect');
      const initializationSettingsIOS = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
      );

      debugPrint('[NotificationService] ローカル通知初期化完了');
    } catch (e) {
      debugPrint('[NotificationService] ローカル通知初期化エラー: $e');
    }

    // 通知タップハンドリング（アプリがローカル通知のタップで終了状態から開かれた場合）
    await _handleLocalNotificationLaunch();
  }

  /// フォアグラウンドメッセージハンドラ
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    try {
      debugPrint(
          '[NotificationService] フォアグラウンドメッセージ受信: ${message.notification?.title}');

      // ローカル通知を表示
      final notification = message.notification;
      if (notification != null) {
        final androidDetails = AndroidNotificationDetails(
          'high_importance_channel',
          '重要な通知',
          channelDescription: 'このチャンネルは重要な通知に使用されます',
          importance: Importance.high,
          priority: Priority.high,
        );

        const iosDetails = DarwinNotificationDetails();

        final notificationDetails = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        // ペイロードをJSON文字列として保存
        final payload = _createPayloadFromMessage(message);

        await _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          notificationDetails,
          payload: payload,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] フォアグラウンドメッセージエラー: $e');
    }
  }

  /// 通知タップハンドラ（リモートメッセージから）
  static void _handleNotificationTap(RemoteMessage message) {
    try {
      debugPrint('[NotificationService] 通知タップ: ${message.data}');

      // data の type / id を受け口へ（ローカル通知と同じ経路。受け口が無い間は取っておく）
      _tapDispatcher.dispatchRemoteData(message.data);
    } catch (e) {
      debugPrint('[NotificationService] 通知タップエラー: $e');
    }
  }

  /// ローカル通知タップハンドラ（onDidReceiveNotificationResponse）
  static void _handleLocalNotificationResponse(NotificationResponse details) {
    final payload = details.payload;
    if (payload == null) return;
    try {
      debugPrint('[NotificationService] ローカル通知タップ: $payload');

      // payload（type:id形式）を受け口へ。起動時の通知として渡し済みのタップは渡さない
      _tapDispatcher.dispatchLocalResponse(
        notificationId: details.id,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NotificationService] ローカル通知タップエラー: $e');
    }
  }

  /// アプリを起動したローカル通知のタップを、通知タップと同じ経路で渡す
  ///
  /// ローカル通知の初期化の後に1回だけ呼ぶ。同じタップが onDidReceiveNotificationResponse
  /// からも届いた場合は、どちらか一方だけを渡す（[NotificationTapDispatcher]）
  static Future<void> _handleLocalNotificationLaunch() async {
    NotificationResponse? response;
    try {
      final details =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp) {
        response = details.notificationResponse;
      }
    } catch (e) {
      debugPrint('[NotificationService] 起動時の通知の取得エラー: $e');
    }

    try {
      final payload = response?.payload;
      if (payload != null) {
        debugPrint('[NotificationService] ローカル通知のタップで起動: $payload');
      }
      // 通知で起動していなくても呼ぶ（起動前後に届いたタップとの重複の判定を終えるため）
      _tapDispatcher.dispatchLaunchResponse(
        notificationId: response?.id,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NotificationService] ローカル通知タップエラー: $e');
    }
  }

  /// メッセージからペイロード文字列を作成
  static String _createPayloadFromMessage(RemoteMessage message) {
    final type = message.data['type'] as String? ?? 'unknown';
    final id = message.data['id'] as String?;
    return id != null ? '$type:$id' : type;
  }

  /// device_tokens テーブルへ upsert（段階移行 stage1 の両書き先）
  ///
  /// RLS は user_id = auth.uid() の本人のみ許可のため、user_id には
  /// 引数の userId ではなく現在の認証ユーザーIDを使用する。
  /// 失敗しても既存の fcm_token 書き込みを壊さない（ログのみで握りつぶす）。
  static Future<void> _upsertDeviceToken(String token, String userType) async {
    try {
      if (userType != 'client' && userType != 'trainer') {
        debugPrint(
            '[NotificationService] device_tokens: 不明なユーザータイプ: $userType');
        return;
      }

      final client = Supabase.instance.client;
      final authUserId = client.auth.currentUser?.id;
      if (authUserId == null) {
        debugPrint('[NotificationService] device_tokens: 未認証のためスキップ');
        return;
      }

      // 同一 (user_id, token) の再登録時は last_seen_at のみ更新
      await client.from('device_tokens').upsert(
        {
          'user_id': authUserId,
          'user_type': userType,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'token': token,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
      debugPrint('[NotificationService] device_tokens 保存完了');
    } catch (e) {
      debugPrint('[NotificationService] device_tokens 保存エラー（無視）: $e');
    }
  }

  /// device_tokens から自分の行を削除
  ///
  /// [token] を指定した場合はそのトークン行のみ削除。
  /// null の場合はトークン不明時のフォールバックとして、
  /// 自分のモバイル行（platform in ('ios','android')）をまとめて削除する。
  /// 失敗しても既存動作を壊さない（ログのみで握りつぶす）。
  static Future<void> _deleteDeviceTokens({String? token}) async {
    try {
      final client = Supabase.instance.client;
      final authUserId = client.auth.currentUser?.id;
      if (authUserId == null) {
        debugPrint('[NotificationService] device_tokens: 未認証のため削除スキップ');
        return;
      }

      if (token != null) {
        await client
            .from('device_tokens')
            .delete()
            .eq('user_id', authUserId)
            .eq('token', token);
      } else {
        await client
            .from('device_tokens')
            .delete()
            .eq('user_id', authUserId)
            .inFilter('platform', ['ios', 'android']);
      }
      debugPrint('[NotificationService] device_tokens 削除完了');
    } catch (e) {
      debugPrint('[NotificationService] device_tokens 削除エラー（無視）: $e');
    }
  }

  /// iOS で FCM トークンを取得する前に APNs トークンの到着を待つ
  ///
  /// `getToken()` は APNs トークンが FIRMessaging にセットされていないと
  /// `[firebase_messaging/apns-token-not-set]` で失敗する。権限を許可した
  /// 直後は APNs 登録の往復が完了していないため、短時間ポーリングして待つ。
  ///
  /// 戻り値: APNs トークンが利用可能になったか（iOS 以外は常に true）。
  static Future<bool> _waitForApnsToken({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!Platform.isIOS) return true;

    var waited = Duration.zero;
    var interval = const Duration(milliseconds: 300);
    while (waited < timeout) {
      try {
        if (await _messaging.getAPNSToken() != null) return true;
      } catch (e) {
        debugPrint('[NotificationService] APNsトークン取得エラー: $e');
      }
      await Future<void>.delayed(interval);
      waited += interval;
      if (interval < const Duration(seconds: 2)) interval *= 2;
    }
    return false;
  }

  /// FCMトークンをSupabaseに保存
  ///
  /// 戻り値: 保存まで到達したかどうか。
  static Future<bool> saveTokenToSupabase(
      String userId, String userType) async {
    try {
      if (!await _waitForApnsToken()) {
        debugPrint('[NotificationService] APNsトークン未取得のため保存を中止');
        return false;
      }

      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('[NotificationService] トークン取得失敗');
        return false;
      }

      // 現在のユーザー情報を保持（トークンリフレッシュ時に使用）
      _currentUserId = userId;
      _currentUserType = userType;
      _currentToken = token;

      // 両書き stage1: device_tokens へも保存
      // （内部で try-catch 済み。fcm_token 書き込みの成否と独立させるため先に実行）
      await _upsertDeviceToken(token, userType);

      final client = Supabase.instance.client;

      if (userType == 'client') {
        await client
            .from('clients')
            .update({'fcm_token': token}).eq('client_id', userId);
        debugPrint('[NotificationService] クライアントトークン保存: $userId');
      } else if (userType == 'trainer') {
        await client
            .from('trainers')
            .update({'fcm_token': token}).eq('id', userId);
        debugPrint('[NotificationService] トレーナートークン保存: $userId');
      } else {
        debugPrint('[NotificationService] 不明なユーザータイプ: $userType');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[NotificationService] トークン保存エラー: $e');
      return false;
    }
  }

  /// FCMトークンをSupabaseから削除（ログアウト時）
  static Future<void> clearTokenFromSupabase(
      String userId, String userType) async {
    try {
      // 両書き stage1: device_tokens からも削除
      // 保持しているトークンがあればその行のみ、不明なら自分のモバイル行を削除
      // （内部で try-catch 済み。fcm_token null 化の成否と独立させるため先に実行）
      await _deleteDeviceTokens(token: _currentToken);

      final client = Supabase.instance.client;

      if (userType == 'client') {
        await client
            .from('clients')
            .update({'fcm_token': null}).eq('client_id', userId);
        debugPrint('[NotificationService] クライアントトークン削除: $userId');
      } else if (userType == 'trainer') {
        await client
            .from('trainers')
            .update({'fcm_token': null}).eq('id', userId);
        debugPrint('[NotificationService] トレーナートークン削除: $userId');
      } else {
        debugPrint('[NotificationService] 不明なユーザータイプ: $userType');
      }

      // 保持している情報をクリア
      _currentUserId = null;
      _currentUserType = null;
      _currentToken = null;
    } catch (e) {
      debugPrint('[NotificationService] トークン削除エラー: $e');
    }
  }

  /// バックグラウンド同期失敗時のローカル通知
  ///
  /// 同期エラー専用の固定 ID (9001) を使うため、連続して呼ばれた場合は
  /// 既存の通知を上書きする（通知トレイに溜まらない）。
  static Future<void> showSyncErrorNotification(String message) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'high_importance_channel',
        '重要な通知',
        channelDescription: 'このチャンネルは重要な通知に使用されます',
        importance: Importance.high,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final body =
          message.length > 120 ? '${message.substring(0, 120)}…' : message;

      await _localNotifications.show(
        9001, // 固定ID（同期エラー専用、上書きされる）
        'ヘルスケア同期に失敗しました',
        body,
        details,
        payload: 'health_sync_error',
      );
    } catch (e) {
      debugPrint('[NotificationService] 同期エラー通知エラー: $e');
    }
  }

  /// トークンリフレッシュハンドラ
  static Future<void> _handleTokenRefresh(String newToken) async {
    try {
      debugPrint('[NotificationService] トークンリフレッシュ: $newToken');

      // 保持しているユーザー情報がある場合のみ更新
      if (_currentUserId != null && _currentUserType != null) {
        // 両書き stage1: device_tokens も更新
        // 掃除方針: saveTokenToSupabase で保持した旧トークン（_currentToken）の
        // 行を削除してから新トークンを upsert する。旧トークン未保持の場合は
        // 特定できないため削除せず upsert のみ（古い行は last_seen_at ベースの
        // サーバー側掃除に委ねる。過剰な推測削除はしない）。
        final oldToken = _currentToken;
        if (oldToken != null && oldToken != newToken) {
          await _deleteDeviceTokens(token: oldToken);
        }
        await _upsertDeviceToken(newToken, _currentUserType!);
        _currentToken = newToken;

        final client = Supabase.instance.client;

        if (_currentUserType == 'client') {
          await client
              .from('clients')
              .update({'fcm_token': newToken}).eq('client_id', _currentUserId!);
          debugPrint('[NotificationService] クライアントトークン更新: $_currentUserId');
        } else if (_currentUserType == 'trainer') {
          await client
              .from('trainers')
              .update({'fcm_token': newToken}).eq('id', _currentUserId!);
          debugPrint('[NotificationService] トレーナートークン更新: $_currentUserId');
        }
      } else {
        debugPrint('[NotificationService] ユーザー情報未設定のためトークン更新スキップ');
      }
    } catch (e) {
      debugPrint('[NotificationService] トークンリフレッシュエラー: $e');
    }
  }
}
