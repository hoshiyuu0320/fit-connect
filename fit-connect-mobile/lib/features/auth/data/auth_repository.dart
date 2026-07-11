import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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

  /// Sign in with Appleでログイン
  /// sign_in_with_apple パッケージでネイティブダイアログを表示し、
  /// 取得したIDトークンをSupabase Authに渡す。
  /// ユーザーがキャンセルした場合はnullを返す。
  Future<AuthResponse?> signInWithApple() async {
    // リプレイ攻撃対策のnonce。
    // Appleにはsha256ハッシュを渡し、Supabaseには生のnonceを渡して検証する。
    final rawNonce = _generateRandomNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // ユーザーがキャンセル
        return null;
      }
      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw Exception('Apple認証でIDトークンを取得できませんでした');
    }

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Appleは初回サインイン時のみ氏名を返す。
    // Google認証で自動設定される user_metadata の full_name と同じキーに保存し、
    // プロフィール設定画面のプリフィル（profile_setup_screen.dart）に流用する。
    final fullName = _buildAppleFullName(credential);
    if (fullName != null) {
      try {
        await _client.auth.updateUser(
          UserAttributes(data: {'full_name': fullName}),
        );
      } catch (_) {
        // 氏名保存はベストエフォート。失敗してもサインイン自体は成功している。
      }
    }

    return response;
  }

  /// Appleから取得した氏名を結合する（日本語アプリのため姓→名の順）。
  /// 取得できなかった場合はnull。
  String? _buildAppleFullName(AuthorizationCredentialAppleID credential) {
    final parts = [credential.familyName, credential.givenName]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  /// nonce用の暗号学的に安全なランダム文字列を生成する
  String _generateRandomNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
