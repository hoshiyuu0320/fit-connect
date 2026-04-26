# Google認証 Mobile 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** fit-connect-mobile に Google ネイティブ認証を追加し、既存のマジックリンク認証と併存させる

**Architecture:** `google_sign_in` パッケージでネイティブ Google ダイアログを表示 → IDトークン取得 → `supabase.auth.signInWithIdToken()` で Supabase Auth にセッション作成。既存の `app.dart` の AuthState stream ルーティングはそのまま利用。

**Tech Stack:** Flutter, google_sign_in, supabase_flutter, Riverpod

**Spec:** `docs/superpowers/specs/2026-03-24-google-auth-mobile-design.md`

---

## 設計判断メモ

- **`auth_provider.dart` は変更しない**: スペックでは変更対象に含まれていたが、既存の `login_screen.dart` は `AuthRepository` を直接使用するパターン（Riverpod未使用）。一貫性のため、Google認証も同パターンで `AuthRepository` 経由で呼ぶ。
- **`registration_provider.dart` を変更する**: スペックでは「変更なし」としていたが、Google アバターURL を DB に保存するために `googleAvatarUrl` フィールドと保存ロジックが必要。スペックのプリフィル方針を拡張した形。

## ファイル構成

| ファイル | 操作 | 責務 |
|----------|------|------|
| `pubspec.yaml` | 修正 | `google_sign_in` パッケージ追加 |
| `ios/Runner/Info.plist` | 修正 | Google Sign-In URL Scheme + GIDClientID |
| `lib/features/auth/data/auth_repository.dart` | 修正 | `signInWithGoogle()` メソッド追加 |
| `lib/features/auth/providers/registration_provider.dart` | 修正 | `googleAvatarUrl` フィールド + 保存ロジック追加 |
| `lib/features/auth/presentation/screens/login_screen.dart` | 修正 | Googleボタン + 区切り線UI + 相互排他ローディング |
| `lib/features/auth/presentation/screens/profile_setup_screen.dart` | 修正 | Google userMetadata からのプリフィル |

---

## Task 1: google_sign_in パッケージ追加

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: pubspec.yaml に google_sign_in を追加**

`pubspec.yaml` の dependencies セクション、`# QRコード` の前に追加:

```yaml
  # Google認証
  google_sign_in: ^6.2.2
```

- [ ] **Step 2: flutter pub get を実行**

Run: `cd fit_connect_mobile && flutter pub get`
Expected: パッケージが正常にダウンロードされる

- [ ] **Step 3: コミット**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: google_sign_in パッケージを追加"
```

---

## Task 2: iOS プラットフォーム設定

**Files:**
- Modify: `ios/Runner/Info.plist`

**注意:** この手順にはGoogle Cloud ConsoleからのiOS Client IDが必要。`YOUR_IOS_CLIENT_ID` プレースホルダは実際のClient IDに置き換えること。Reversed Client ID は iOS Client ID を逆順にしたもの（例: `com.googleusercontent.apps.123456` → そのまま URL Scheme に使用）。

- [ ] **Step 1: Info.plist に Google Sign-In 設定を追加**

`ios/Runner/Info.plist` の既存の `CFBundleURLTypes` 配列内に、Google Sign-In用のURL Schemeを追加する。既存の `fitconnectmobile` スキームの `dict` の後に新しい `dict` を追加:

```xml
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>YOUR_REVERSED_IOS_CLIENT_ID</string>
			</array>
		</dict>
```

さらに、`Info.plist` の `dict` 直下（`CFBundleURLTypes` と同レベル）に `GIDClientID` を追加:

```xml
	<key>GIDClientID</key>
	<string>YOUR_IOS_CLIENT_ID</string>
```

- [ ] **Step 2: コミット**

```bash
git add ios/Runner/Info.plist
git commit -m "config(ios): Google Sign-In URL Scheme と GIDClientID を追加"
```

---

## Task 3: Android プラットフォーム設定

**Files:**
- Modify: `android/app/build.gradle.kts`（必要に応じて）

**注意:** Android では `google_sign_in` パッケージが `google-services.json` から自動的に設定を読む。追加のコード変更は通常不要だが、以下の準備が必要。

- [ ] **Step 1: SHA-1 フィンガープリントを取得**

Run:
```bash
cd fit_connect_mobile/android && ./gradlew signingReport
```
Expected: `SHA1:` の行にフィンガープリントが表示される（debug用）

- [ ] **Step 2: Google Cloud Console で Android クライアントIDに SHA-1 を登録**

1. Google Cloud Console → APIとサービス → 認証情報
2. Android 用 OAuth 2.0 クライアントID を作成（または既存を更新）
3. パッケージ名とSHA-1フィンガープリントを設定

- [ ] **Step 3: google-services.json を更新**

Google Cloud Console から最新の `google-services.json` をダウンロードし、`android/app/google-services.json` を上書き。

- [ ] **Step 4: コミット**

```bash
git add android/app/google-services.json
git commit -m "config(android): Google Sign-In 用に google-services.json を更新"
```

---

## Task 4: auth_repository に signInWithGoogle を追加

**Files:**
- Modify: `lib/features/auth/data/auth_repository.dart`

- [ ] **Step 1: import 追加と signInWithGoogle メソッドを実装**

`auth_repository.dart` を以下のように変更:

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

class AuthRepository {
  final SupabaseClient _client = SupabaseService.client;

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
    final googleSignIn = GoogleSignIn(
      serverClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    );

    final googleUser = await googleSignIn.signIn();
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
```

**ポイント:**
- `serverClientId` には **Web Client ID**（Supabase Dashboard に設定したもの）を使用。`--dart-define=GOOGLE_WEB_CLIENT_ID=xxx` で起動時に渡す
- iOS では `GIDClientID`（Info.plist）から iOS Client ID を自動読み込み
- `signIn()` が null → ユーザーキャンセル
- `idToken` が null → エラー

- [ ] **Step 2: ビルド確認**

Run: `cd fit_connect_mobile && flutter analyze lib/features/auth/data/auth_repository.dart`
Expected: エラーなし

- [ ] **Step 3: コミット**

```bash
git add lib/features/auth/data/auth_repository.dart
git commit -m "feat: auth_repository に signInWithGoogle メソッドを追加"
```

---

## Task 5: login_screen に Google ログインボタンを追加

**Files:**
- Modify: `lib/features/auth/presentation/screens/login_screen.dart`

- [ ] **Step 1: _isGoogleLoading 状態変数を追加**

`_LoginScreenState` クラスに以下を追加（`_isLoading` の下、line 23 の後）:

```dart
  bool _isGoogleLoading = false;
```

- [ ] **Step 2: _handleGoogleLogin メソッドを追加**

`_handleLogin` メソッドの後（line 87 の後）に追加:

```dart
  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      final response = await _authRepository.signInWithGoogle();
      if (response == null) {
        // ユーザーがキャンセル — 何もしない
        return;
      }
      // 認証成功 → _authSubscription が検知してナビゲーション
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google認証エラー: ${e.toString()}'),
            backgroundColor: AppColors.rose800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }
```

- [ ] **Step 3: 認証中の相互排他ローディングを実装**

既存のメール送信ボタンの `onPressed` を変更（line 245）:

置き換え前:
```dart
                            onPressed: _isLoading ? null : _handleLogin,
```

置き換え後:
```dart
                            onPressed: (_isLoading || _isGoogleLoading) ? null : _handleLogin,
```

- [ ] **Step 4: UIに区切り線とGoogleボタンを追加**

`login_screen.dart` の `build` メソッド内、ログインボタン（`ElevatedButton`）の閉じ `)` の直後（line 273の後）、既存の `],`（else ブロックの閉じ）の直前に以下を追加:

```dart
                          const SizedBox(height: 24),

                          // 区切り線「または」
                          Row(
                            children: [
                              Expanded(
                                child: Divider(color: colors.border),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'または',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textHint,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: colors.border),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Googleでログインボタン
                          OutlinedButton(
                            onPressed:
                                (_isGoogleLoading || _isLoading) ? null : _handleGoogleLogin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.textPrimary,
                              side: BorderSide(color: colors.border),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isGoogleLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: colors.textSecondary,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Google "G" ロゴ（テキストで代用）
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            'G',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF4285F4),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Googleでログイン',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
```

- [ ] **Step 5: ビルド確認**

Run: `cd fit_connect_mobile && flutter analyze lib/features/auth/presentation/screens/login_screen.dart`
Expected: エラーなし

- [ ] **Step 6: コミット**

```bash
git add lib/features/auth/presentation/screens/login_screen.dart
git commit -m "feat: login_screen に Google ログインボタンを追加"
```

---

## Task 6: profile_setup_screen に Google メタデータのプリフィルを追加

**Files:**
- Modify: `lib/features/auth/presentation/screens/profile_setup_screen.dart`
- Modify: `lib/features/auth/providers/registration_provider.dart`

- [ ] **Step 1: registration_provider に googleAvatarUrl フィールドを追加**

`lib/features/auth/providers/registration_provider.dart` の `RegistrationState` クラスに `googleAvatarUrl` フィールドを追加:

```dart
class RegistrationState {
  final String? trainerId;
  final String? trainerName;
  final String? trainerImageUrl;
  final String? clientName;
  final int? clientAge;
  final String? clientGender;
  final File? profileImageFile;
  final String? googleAvatarUrl;  // ← 追加
  final bool isRegistrationComplete;

  const RegistrationState({
    this.trainerId,
    this.trainerName,
    this.trainerImageUrl,
    this.clientName,
    this.clientAge,
    this.clientGender,
    this.profileImageFile,
    this.googleAvatarUrl,  // ← 追加
    this.isRegistrationComplete = false,
  });
```

`copyWith` メソッドにも追加:
```dart
  RegistrationState copyWith({
    String? trainerId,
    String? trainerName,
    String? trainerImageUrl,
    String? clientName,
    int? clientAge,
    String? clientGender,
    File? Function()? profileImageFile,
    String? Function()? googleAvatarUrl,  // ← 追加（nullable対応のためFunction型）
    bool? isRegistrationComplete,
  }) {
    return RegistrationState(
      trainerId: trainerId ?? this.trainerId,
      trainerName: trainerName ?? this.trainerName,
      trainerImageUrl: trainerImageUrl ?? this.trainerImageUrl,
      clientName: clientName ?? this.clientName,
      clientAge: clientAge ?? this.clientAge,
      clientGender: clientGender ?? this.clientGender,
      profileImageFile:
          profileImageFile != null ? profileImageFile() : this.profileImageFile,
      googleAvatarUrl:
          googleAvatarUrl != null ? googleAvatarUrl() : this.googleAvatarUrl,  // ← 追加
      isRegistrationComplete:
          isRegistrationComplete ?? this.isRegistrationComplete,
    );
  }
```

`RegistrationNotifier` に `setGoogleAvatarUrl` メソッドを追加（`setProfileImage` の後）:
```dart
  /// Google アバターURLをセット
  void setGoogleAvatarUrl(String? url) {
    state = state.copyWith(googleAvatarUrl: () => url);
  }
```

`completeRegistration` メソッド内、プロフィール画像アップロードの `}` の後に追加:
```dart
    // Google アバターURLの保存（ローカル画像が未選択の場合のみ）
    if (state.profileImageFile == null && state.googleAvatarUrl != null) {
      await SupabaseService.client
          .from('clients')
          .update({'profile_image_url': state.googleAvatarUrl}).eq('client_id', userId);
    }
```

`fetchTrainerInfo` メソッド内の `RegistrationState` 再構築にも `googleAvatarUrl` を追加:
```dart
      state = RegistrationState(
        trainerId: trainerId,
        trainerName: response['name'] as String?,
        trainerImageUrl: response['profile_image_url'] as String?,
        clientName: state.clientName,
        clientAge: state.clientAge,
        clientGender: state.clientGender,
        profileImageFile: state.profileImageFile,
        googleAvatarUrl: state.googleAvatarUrl,  // ← 追加
      );
```

- [ ] **Step 2: profile_setup_screen に import 追加**

ファイル先頭の import セクションに追加:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
```

- [ ] **Step 3: _googleAvatarUrl 状態変数を追加**

`_ProfileSetupScreenState` クラスの `File? _selectedImage;` の後（line 27 の後）に追加:

```dart
  String? _googleAvatarUrl; // Google認証時のアバターURL
```

- [ ] **Step 4: initState でプリフィルロジックを追加**

`_ProfileSetupScreenState` に `initState` メソッドを追加（`dispose` の前、line 31 の前）:

```dart
  @override
  void initState() {
    super.initState();
    _prefillFromGoogleMetadata();
  }

  /// Google認証時のuserMetadataから名前・画像URLをプリフィル
  void _prefillFromGoogleMetadata() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata;
    if (metadata == null) return;

    // 名前のプリフィル
    final fullName = metadata['full_name'] as String?;
    if (fullName != null && fullName.isNotEmpty) {
      _nameController.text = fullName;
    }

    // Google アバターURLの取得
    final avatarUrl = metadata['avatar_url'] as String?;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      setState(() {
        _googleAvatarUrl = avatarUrl;
      });
    }
  }
```

- [ ] **Step 5: プロフィール画像表示部分を更新**

`profile_setup_screen.dart` の build メソッド内、プロフィール画像表示の `Container`（line 179-198付近）を以下に置き換え:

置き換え前（`_selectedImage` のみ対応）:
```dart
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary50,
                                      shape: BoxShape.circle,
                                      image: _selectedImage != null
                                          ? DecorationImage(
                                              image: FileImage(_selectedImage!),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: _selectedImage == null
                                        ? const Icon(
                                            LucideIcons.user,
                                            size: 40,
                                            color: AppColors.primary600,
                                          )
                                        : null,
                                  ),
```

置き換え後（`_selectedImage` + `_googleAvatarUrl` 対応）:
```dart
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary50,
                                      shape: BoxShape.circle,
                                      image: _selectedImage != null
                                          ? DecorationImage(
                                              image: FileImage(_selectedImage!),
                                              fit: BoxFit.cover,
                                            )
                                          : _googleAvatarUrl != null
                                              ? DecorationImage(
                                                  image:
                                                      CachedNetworkImageProvider(
                                                          _googleAvatarUrl!),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                    ),
                                    child: _selectedImage == null &&
                                            _googleAvatarUrl == null
                                        ? const Icon(
                                            LucideIcons.user,
                                            size: 40,
                                            color: AppColors.primary600,
                                          )
                                        : null,
                                  ),
```

- [ ] **Step 6: _handleSubmit で Google アバターURL の保存対応**

`_handleSubmit` メソッド内の該当部分を置き換え:

置き換え前:
```dart
      // プロフィール画像をセット（選択されている場合）
      if (_selectedImage != null) {
        registrationNotifier.setProfileImage(_selectedImage);
      }
```

置き換え後:
```dart
      // プロフィール画像をセット（選択されている場合）
      if (_selectedImage != null) {
        registrationNotifier.setProfileImage(_selectedImage);
      }

      // Google アバターURLを保存（ユーザーが画像を選択していない場合のみ）
      if (_selectedImage == null && _googleAvatarUrl != null) {
        registrationNotifier.setGoogleAvatarUrl(_googleAvatarUrl);
      }
```

- [ ] **Step 7: コード生成を実行**

Run: `cd fit_connect_mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `registration_provider.g.dart` が再生成される

- [ ] **Step 8: ビルド確認**

Run: `cd fit_connect_mobile && flutter analyze`
Expected: エラーなし

- [ ] **Step 9: コミット**

```bash
git add lib/features/auth/presentation/screens/profile_setup_screen.dart lib/features/auth/providers/registration_provider.dart lib/features/auth/providers/registration_provider.g.dart
git commit -m "feat: Google メタデータ（名前・画像）のプリフィル対応"
```

---

## Task 7: Supabase Dashboard 設定（手動）

これはコード変更ではなく、Google Cloud Console と Supabase Dashboard での手動設定。

- [ ] **Step 1: Google Cloud Console で OAuth クライアントID を作成**

1. [Google Cloud Console](https://console.cloud.google.com) → APIとサービス → 認証情報
2. OAuth 2.0クライアントIDを作成:
   - **Web アプリケーション**: Supabase の callback URL（`https://<project-ref>.supabase.co/auth/v1/callback`）を承認済みリダイレクト URI に追加
   - **iOS**: バンドルID を指定
   - **Android**: パッケージ名 + SHA-1 フィンガープリントを指定

- [ ] **Step 2: Supabase Dashboard で Google Provider を有効化**

1. Supabase Dashboard → Authentication → Providers → Google
2. **Client ID**: Web Client ID を入力
3. **Client Secret**: Web Client Secret を入力
4. **Skip nonce check**: **有効にする**（iOS の google_sign_in で必須）

- [ ] **Step 3: iOS 設定の実値を反映**

Task 2 で設定したプレースホルダを実際の値に更新:
- `YOUR_IOS_CLIENT_ID` → Google Cloud Console から取得した iOS Client ID
- `YOUR_REVERSED_IOS_CLIENT_ID` → iOS Client ID の逆順

- [ ] **Step 4: Firebase 設定ファイルの更新**

Google Sign-In を有効にした場合、`GoogleService-Info.plist`（iOS）と `google-services.json`（Android）を Google Cloud Console から再ダウンロードして更新する。

- [ ] **Step 5: 起動コマンドの確認**

Google Sign-In を使うには、起動時に Web Client ID を渡す必要がある:

```bash
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

---

## Task 8: 動作確認

- [ ] **Step 1: iOS シミュレータで起動**

Run: `cd fit_connect_mobile && flutter run -d ios --dart-define=GOOGLE_WEB_CLIENT_ID=<your-web-client-id>`

- [ ] **Step 2: ログイン画面の確認**

1. Welcome画面 → 「ログイン」タップ → login_screen表示
2. 「または」区切り線と「Googleでログイン」ボタンが表示されることを確認
3. マジックリンク送信中はGoogleボタンも無効化されることを確認

- [ ] **Step 3: Google認証フロー（既存ユーザー）の確認**

1. 「Googleでログイン」タップ
2. Google のネイティブ認証ダイアログが表示される
3. アカウント選択 → ログイン成功
4. MainScreen に遷移することを確認

- [ ] **Step 4: Google認証フロー（新規ユーザー）の確認**

1. Welcome → 新規登録 → QRスキャン/招待コード → トレーナー確認 → login_screen
2. 「Googleでログイン」タップ
3. 認証成功後、ProfileSetupScreen に遷移
4. 名前がGoogleアカウント名でプリフィルされていることを確認
5. アバター画像がGoogleプロフィール画像で表示されていることを確認

- [ ] **Step 5: キャンセルとエラーの確認**

1. 「Googleでログイン」タップ → Google ダイアログでキャンセル → login_screen に戻ることを確認
2. ネットワーク切断状態でタップ → エラー SnackBar が表示されることを確認

- [ ] **Step 6: Android で起動確認**

Run: `cd fit_connect_mobile && flutter run -d android --dart-define=GOOGLE_WEB_CLIENT_ID=<your-web-client-id>`
Expected: iOS と同じ動作
