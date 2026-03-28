import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

class AuthRepository {
  final SupabaseClient _client = SupabaseService.client;
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '',
  );

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signInWithEmail(String email) async {
    await _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: 'fitconnectmobile://login-callback',
    );
  }

  /// Google Sign-Inでログイン
  /// google_sign_in パッケージでネイティブダイアログを表示し、
  /// 取得したIDトークンをSupabase Authに渡す。
  /// ユーザーがキャンセルした場合はnullを返す。
  Future<AuthResponse?> signInWithGoogle() async {
    assert(
      (dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '').isNotEmpty,
      'GOOGLE_WEB_CLIENT_ID must be set in assets/.env',
    );

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // ユーザーがキャンセル
      return null;
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw Exception('Google認証でIDトークンを取得できませんでした');
    }

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );

    return response;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
