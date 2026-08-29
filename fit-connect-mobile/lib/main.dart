import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('🚀 アプリ起動開始');

  // 環境変数読み込み
  await dotenv.load(fileName: "assets/.env");
  print('✅ 環境変数読み込み完了');

  // Supabase初期化
  await SupabaseService.initialize();
  print('✅ Supabase初期化完了');
  print('📡 Supabase URL: ${dotenv.env['SUPABASE_URL']}');

  // セッション復元を待つ（onAuthStateChangeの最初のイベントを待つ）
  await SupabaseService.waitForSessionRestore();
  print('✅ セッション復元完了');

  // Firebase & プッシュ通知初期化（iOS/Androidのみ、macOS開発環境では実行しない）
  // 注意: initialize() は OS の通知権限リクエストを行わない。
  // 権限はオンボーディングのプライミング画面で
  // NotificationService.requestPermissionAndRegister() から取得する。
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ Firebase初期化完了');

      // NotificationService.initialize() は await しない。
      // 内部の getInitialMessage() は APNs トークンの到着を待つため、
      // APNs が使えない環境（iOS シミュレータなど）では解決せず、
      // await すると runApp() まで到達せず画面が真っ白になる。
      // リスナー登録のみで初回フレームに必要な処理は無く、例外は
      // initialize() 内で捕捉されるため、バックグラウンドで進行させる。
      unawaited(NotificationService.initialize());
      print('✅ プッシュ通知初期化を開始');
    } catch (e) {
      print('⚠️ Firebase/通知初期化エラー: $e');
    }
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
