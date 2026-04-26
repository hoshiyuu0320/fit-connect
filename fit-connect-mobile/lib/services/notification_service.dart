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
    } catch (e) {
      print('[NotificationService] トークン削除エラー: $e');
    }
  }

  /// トークンリフレッシュハンドラ
  static Future<void> _handleTokenRefresh(String newToken) async {
    try {
      print('[NotificationService] トークンリフレッシュ: $newToken');

      // 保持しているユーザー情報がある場合のみ更新
      if (_currentUserId != null && _currentUserType != null) {
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
