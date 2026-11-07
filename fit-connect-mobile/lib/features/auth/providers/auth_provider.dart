import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;
import 'package:fit_connect_mobile/features/auth/data/account_deletion_repository.dart';
import 'package:fit_connect_mobile/features/home/providers/notification_navigation_provider.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/record_reminder_sync.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';
import 'package:fit_connect_mobile/shared/storage/signed_url_cache.dart';

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
        // ログアウトのたびに片付ける（signOut() を通らない自動のログアウトを含む）
        if (data.event == AuthChangeEvent.signedOut) _onSignedOut();

        // tokenRefreshedは除外
        if (data.event != AuthChangeEvent.signedIn &&
            data.event != AuthChangeEvent.signedOut) {
          return;
        }

        // ユーザーIDが実際に変わった場合のみ再評価
        final newUserId = data.session?.user.id;
        if (newUserId != _lastUserId) {
          debugPrint(
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

  /// auth の signedOut のたびに呼ぶ（片付けは待たない。例外は投げない）。
  ///
  /// gotrue は [signOut] を通らずに signedOut を出すことがある（リフレッシュトークンが使えず、
  /// 更新をやり直さないときなど）。そのときも、ログアウトした端末で記録のリマインダーが鳴り続けたり、
  /// 押された通知が次のログインへ持ち越されたりしないよう、[clearSignedOutState] で片付ける
  /// （[signOut] からのログアウトでも呼ばれる。片付けは何度してもよい）
  void _onSignedOut() {
    try {
      final reminderSync = ref.read(recordReminderSyncProvider);
      // 片付けの終わりはこの Notifier の作り直しの後になることがあるので、container で捨てる
      final container = ref.container;
      unawaited(clearSignedOutState(
        reminderSync: reminderSync,
        invalidateNotificationNavigation: () =>
            container.invalidate(notificationNavigationProvider),
      ));
    } catch (e) {
      debugPrint('[AuthNotifier] ログアウトの後片付けエラー: $e');
    }
  }

  /// メールアドレスでマジックリンク認証
  Future<void> signInWithEmail(String email) async {
    await SupabaseService.client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: 'fitconnectmobile://login-callback',
    );
  }

  /// サインアウト
  ///
  /// FCM トークンを消し（ログインしている間でないと消せない）、auth のサインアウトをしてから、
  /// 記録のリマインダーなどを片付ける（[signOutAndClearState]。サインアウトに失敗しても片付ける）
  Future<void> signOut() async {
    // 片付けで使うものは、サインアウトの前に読んでおく（サインアウトすると、この Notifier は
    // signedOut を受けて作り直し・破棄される）
    final reminderSync = ref.read(recordReminderSyncProvider);
    final container = ref.container;

    // iOS/Androidのみ: ログアウト前にFCMトークンをDBから削除
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await NotificationService.clearTokenFromSupabase(userId, 'client');
          debugPrint('[AuthNotifier] FCMトークン削除完了');
        } catch (e) {
          debugPrint('[AuthNotifier] FCMトークン削除エラー: $e');
        }
      }
    }
    // サインアウトしてから、記録のリマインダーの予約・表示中の通知、取っておいた通知のタップ、
    // 通知を押したときの「開く先」を片付ける（次のアカウントへ持ち越さない）
    await signOutAndClearState(
      signOut: () => SupabaseService.client.auth.signOut(),
      reminderSync: reminderSync,
      invalidateNotificationNavigation: () =>
          container.invalidate(notificationNavigationProvider),
    );
    // 署名URLキャッシュを破棄（別アカウントで再ログインした際に持ち越さない）
    SignedUrlCache.instance.clear();
  }

  /// アカウント削除（App Store Guideline 5.1.1(v) 対応）
  ///
  /// delete-account Edge Function がバックエンドの全データ
  /// （clients + CASCADE / messages / Storage / auth.users）を削除する。
  /// 成功後は signOut() でローカルセッションを破棄し、
  /// app.dart の認証 StreamBuilder がウェルカム画面へ遷移させる。
  /// 注: FCMトークンは auth.users ごと消えるため掃除は本来不要だが、
  /// signOut 内の clearTokenFromSupabase は対象行が無くても
  /// エラーにならない（0行更新 + try-catch 済み）ためそのまま呼んでよい。
  Future<void> deleteAccount() async {
    await ref.read(accountDeletionRepositoryProvider).deleteAccount();
    await signOut();
  }
}

/// ログアウトした後の片付け（設計 §4.1「ログアウト・アカウント削除」）。何度呼んでもよく、例外は投げない。
///
/// 1. 記録のリマインダーの予約と表示中の通知をすべて消す（[RecordReminderSync.cancelAll]。終わるまで待つ）
/// 2. 受け口が無い間に取っておいた通知のタップを捨てる（[NotificationService.clearPendingTap]）
/// 3. 通知を押したときの「開く先」を捨てる（[invalidateNotificationNavigation]。
///    notificationNavigationProvider を作り直す）
///
/// 2・3 は 1 の後に行う（取り消している間に押された通知の分も、次のログインへ持ち越さない）
Future<void> clearSignedOutState({
  required RecordReminderSync reminderSync,
  required void Function() invalidateNotificationNavigation,
}) async {
  try {
    await reminderSync.cancelAll();
  } catch (e) {
    debugPrint('[Auth] 記録のリマインダーの取り消しエラー: $e');
  }
  try {
    NotificationService.clearPendingTap();
  } catch (e) {
    debugPrint('[Auth] 取っておいた通知のタップを捨てられませんでした: $e');
  }
  try {
    invalidateNotificationNavigation();
  } catch (e) {
    debugPrint('[Auth] 通知を押したときの「開く先」を捨てられませんでした: $e');
  }
}

/// auth のサインアウト（[signOut]）をしてから、[clearSignedOutState] で片付ける
/// （ログアウト・アカウント削除・app.dart の残ったセッションのサインアウト）。
///
/// サインアウトを先にする。gotrue（2.18.0）の signOut は最初の await の前にセッションを消すので、
/// [signOut] を呼んだ時点で currentUser は null になる。走っている予約し直しは次の確認（stopped）で止まり、
/// 後から始まる予約し直しは「ログインしていない」としてすべて消すだけになる。逆の順では、取り消している間に
/// 始まった予約し直しがまだログインしているユーザーを見て、取り消しの後に予約してしまう。
///
/// [signOut] が例外を投げても（オフラインで /logout に届かないなど。端末のセッションはもう消えている）
/// 片付けてから、その例外を投げ直す
Future<void> signOutAndClearState({
  required Future<void> Function() signOut,
  required RecordReminderSync reminderSync,
  required void Function() invalidateNotificationNavigation,
}) async {
  try {
    await signOut();
  } finally {
    await clearSignedOutState(
      reminderSync: reminderSync,
      invalidateNotificationNavigation: invalidateNotificationNavigation,
    );
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
