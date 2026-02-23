import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    // 環境変数読み込み
    await dotenv.load(fileName: "assets/.env");

    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }

  /// セッション復元を待つ
  /// onAuthStateChangeの最初のイベントを待つことで、セッション復元完了を検知
  static Future<void> waitForSessionRestore() async {
    final completer = Completer<void>();

    // 既にセッションがある場合はすぐに完了
    if (client.auth.currentSession != null) {
      return;
    }

    // onAuthStateChangeの最初のイベントを待つ
    late final StreamSubscription subscription;
    subscription = client.auth.onAuthStateChange.listen((data) {
      if (!completer.isCompleted) {
        completer.complete();
      }
      subscription.cancel();
    });

    // タイムアウト（3秒）
    await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        subscription.cancel();
      },
    );
  }
}
