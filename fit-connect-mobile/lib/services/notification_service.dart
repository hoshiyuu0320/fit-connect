import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// バックグラウンドハンドラ（トップレベル関数）
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('[NotificationService] バックグラウンドメッセージ: ${message.notification?.title}');
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // トークンリフレッシュ時に使用
  static String? _currentUserId;
  static String? _currentUserType;

  // 直近に保存したFCMトークン（リフレッシュ時の旧 device_tokens 行削除に使用）
  static String? _currentToken;

  // 通知タップコールバック
  static void Function(String type, String? id)? onNotificationTap;

  /// 初期化
  static Future<void> initialize() async {
    try {
      // 権限リクエスト
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      print('[NotificationService] 通知権限: ${settings.authorizationStatus}');

      // iOS フォアグラウンド通知設定
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // FCMトークン取得
      final token = await _messaging.getToken();
      print('[NotificationService] FCM Token: $token');

      // ローカル通知プラグイン初期化
      await _initializeLocalNotifications();

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

      print('[NotificationService] 初期化完了');
    } catch (e) {
      print('[NotificationService] 初期化エラー: $e');
    }
  }

  /// ローカル通知プラグイン初期化
  static Future<void> _initializeLocalNotifications() async {
    try {
      // Android通知チャンネル作成
      const androidChannel = AndroidNotificationChannel(
        'high_importance_channel',
        '重要な通知',
        description: 'このチャンネルは重要な通知に使用されます',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      // 初期化設定
      const initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initializationSettingsIOS = DarwinInitializationSettings();
      const initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          if (details.payload != null) {
            _handleLocalNotificationTap(details.payload!);
          }
        },
      );

      print('[NotificationService] ローカル通知初期化完了');
    } catch (e) {
      print('[NotificationService] ローカル通知初期化エラー: $e');
    }
  }

  /// フォアグラウンドメッセージハンドラ
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    try {
      print(
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
      print('[NotificationService] フォアグラウンドメッセージエラー: $e');
    }
  }

  /// 通知タップハンドラ（リモートメッセージから）
  static void _handleNotificationTap(RemoteMessage message) {
    try {
      print('[NotificationService] 通知タップ: ${message.data}');

      final type = message.data['type'] as String?;
      final id = message.data['id'] as String?;

      if (type != null && onNotificationTap != null) {
        onNotificationTap!(type, id);
      }
    } catch (e) {
      print('[NotificationService] 通知タップエラー: $e');
    }
  }

  /// ローカル通知タップハンドラ
  static void _handleLocalNotificationTap(String payload) {
    try {
      print('[NotificationService] ローカル通知タップ: $payload');

      // 簡易的なペイロード解析（type:id形式）
      final parts = payload.split(':');
      if (parts.length >= 1) {
        final type = parts[0];
        final id = parts.length >= 2 ? parts[1] : null;

        if (onNotificationTap != null) {
          onNotificationTap!(type, id);
        }
      }
    } catch (e) {
      print('[NotificationService] ローカル通知タップエラー: $e');
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

  /// FCMトークンをSupabaseに保存
  static Future<void> saveTokenToSupabase(
      String userId, String userType) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        print('[NotificationService] トークン取得失敗');
        return;
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
        print('[NotificationService] クライアントトークン保存: $userId');
      } else if (userType == 'trainer') {
        await client
            .from('trainers')
            .update({'fcm_token': token}).eq('id', userId);
        print('[NotificationService] トレーナートークン保存: $userId');
      } else {
        print('[NotificationService] 不明なユーザータイプ: $userType');
      }
    } catch (e) {
      print('[NotificationService] トークン保存エラー: $e');
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
        print('[NotificationService] クライアントトークン削除: $userId');
      } else if (userType == 'trainer') {
        await client
            .from('trainers')
            .update({'fcm_token': null}).eq('id', userId);
        print('[NotificationService] トレーナートークン削除: $userId');
      } else {
        print('[NotificationService] 不明なユーザータイプ: $userType');
      }

      // 保持している情報をクリア
      _currentUserId = null;
      _currentUserType = null;
      _currentToken = null;
    } catch (e) {
      print('[NotificationService] トークン削除エラー: $e');
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

      final body = message.length > 120
          ? '${message.substring(0, 120)}…'
          : message;

      await _localNotifications.show(
        9001, // 固定ID（同期エラー専用、上書きされる）
        'ヘルスケア同期に失敗しました',
        body,
        details,
        payload: 'health_sync_error',
      );
    } catch (e) {
      print('[NotificationService] 同期エラー通知エラー: $e');
    }
  }

  /// トークンリフレッシュハンドラ
  static Future<void> _handleTokenRefresh(String newToken) async {
    try {
      print('[NotificationService] トークンリフレッシュ: $newToken');

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
          print('[NotificationService] クライアントトークン更新: $_currentUserId');
        } else if (_currentUserType == 'trainer') {
          await client
              .from('trainers')
              .update({'fcm_token': newToken}).eq('id', _currentUserId!);
          print('[NotificationService] トレーナートークン更新: $_currentUserId');
        }
      } else {
        print('[NotificationService] ユーザー情報未設定のためトークン更新スキップ');
      }
    } catch (e) {
      print('[NotificationService] トークンリフレッシュエラー: $e');
    }
  }
}
