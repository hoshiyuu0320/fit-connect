import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/login_screen.dart';

/// テスト用のダミーセッションを生成する（ネットワーク接続なし）
Session _fakeSession() {
  return Session(
    accessToken: 'fake-access-token',
    tokenType: 'bearer',
    user: const User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );
}

void main() {
  group('shouldPopOnAuthEvent (LoginScreen 認証リスナーの判定ロジック)', () {
    test('signedIn + セッション有り → pop する（新規サインイン成功）', () {
      expect(
        shouldPopOnAuthEvent(AuthChangeEvent.signedIn, _fakeSession()),
        isTrue,
      );
    });

    test('initialSession + セッション有り → pop しない（BehaviorSubject の再送）', () {
      // 不具合の再現ケース: 残存セッションがあると、onAuthStateChange の購読
      // 開始時に initialSession イベントが再送される。これに反応すると
      // LoginScreen が push 直後に自動 pop してしまう。
      expect(
        shouldPopOnAuthEvent(AuthChangeEvent.initialSession, _fakeSession()),
        isFalse,
      );
    });

    test('tokenRefreshed + セッション有り → pop しない（残存セッションの更新）', () {
      expect(
        shouldPopOnAuthEvent(AuthChangeEvent.tokenRefreshed, _fakeSession()),
        isFalse,
      );
    });

    test('userUpdated + セッション有り → pop しない', () {
      expect(
        shouldPopOnAuthEvent(AuthChangeEvent.userUpdated, _fakeSession()),
        isFalse,
      );
    });

    test('signedIn + セッション無し → pop しない', () {
      expect(
        shouldPopOnAuthEvent(AuthChangeEvent.signedIn, null),
        isFalse,
      );
    });

    test('signedOut + セッション無し → pop しない', () {
      expect(
        shouldPopOnAuthEvent(AuthChangeEvent.signedOut, null),
        isFalse,
      );
    });
  });
}
