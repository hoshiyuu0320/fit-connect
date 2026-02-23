import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';

part 'auth_provider.g.dart';

/// 認証状態を管理するProvider
/// 注意: プロフィール情報はcurrentClientProvider/trainerProfileProviderを使用
@riverpod
class AuthNotifier extends _$AuthNotifier {
  String? _lastUserId;

  @override
  Future<supabase.User?> build() async {
    // 現在のユーザーIDを記録（変更検知用）
    final currentUserId = SupabaseService.client.auth.currentUser?.id;
    _lastUserId = currentUserId;

    // 認証状態の変更を監視
    final subscription = SupabaseService.client.auth.onAuthStateChange.listen(
      (data) {
        // tokenRefreshedは除外
        if (data.event != AuthChangeEvent.signedIn &&
            data.event != AuthChangeEvent.signedOut) {
          return;
        }

        // ユーザーIDが実際に変わった場合のみ再評価
        final newUserId = data.session?.user.id;
        if (newUserId != _lastUserId) {
          print(
              '[DEBUG] AuthNotifier: user changed from $_lastUserId to $newUserId, invalidating...');
          ref.invalidateSelf();
        }
      },
    );

    // Provider破棄時にサブスクリプションをキャンセル
    ref.onDispose(() {
      subscription.cancel();
    });

    // Supabase認証ユーザーを返す（プロフィール情報は別Providerで取得）
    return SupabaseService.client.auth.currentUser;
  }

  /// メールアドレスでマジックリンク認証
  Future<void> signInWithEmail(String email) async {
    await SupabaseService.client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: 'fitconnectmobile://login-callback',
    );
  }

  /// サインアウト
  Future<void> signOut() async {
    // iOS/Androidのみ: ログアウト前にFCMトークンをDBから削除
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await NotificationService.clearTokenFromSupabase(userId, 'client');
          print('[AuthNotifier] FCMトークン削除完了');
        } catch (e) {
          print('[AuthNotifier] FCMトークン削除エラー: $e');
        }
      }
    }
    await SupabaseService.client.auth.signOut();
  }
}

/// 現在のセッションを取得するProvider
@riverpod
Session? currentSession(CurrentSessionRef ref) {
  return SupabaseService.client.auth.currentSession;
}

/// 認証済みかどうかを返すProvider
@riverpod
bool isAuthenticated(IsAuthenticatedRef ref) {
  final session = ref.watch(currentSessionProvider);
  return session != null;
}
