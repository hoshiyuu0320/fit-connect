# Google認証 — fit-connect-mobile 設計書

**日付:** 2026-03-24
**ステータス:** 承認済み

## 概要

fit-connect-mobile（Flutter）にGoogle認証を追加する。既存のマジックリンク認証と併存し、login_screen上でユーザーが選択できる構成とする。

## 方式

`google_sign_in`パッケージでネイティブGoogle Sign-Inダイアログを表示し、取得したIDトークンを`supabase.auth.signInWithIdToken()`に渡す。

## アーキテクチャ

```
google_sign_in パッケージ
    ↓ IDトークン取得
supabase.auth.signInWithIdToken(provider: Provider.google, idToken: ...)
    ↓ Supabase Authユーザー作成/ログイン
app.dart の AuthState stream が検知
    ↓
clients テーブルにレコードあり? → MainScreen
    ↓ なし
既存の登録フロー（QR/招待コード → トレーナー確認 → プロフィール設定）
※ Google の name / avatar_url をプロフィール設定画面にプリフィル
```

## フロー詳細

### 既存ユーザー（clientsレコードあり）の再ログイン

1. Welcome → ログイン選択 → login_screen
2. 「Googleでログイン」タップ
3. `google_sign_in`のネイティブUI表示
4. IDトークン取得 → `supabase.auth.signInWithIdToken()`
5. `app.dart`の`AuthState` streamがsession検知 → `currentClientProvider`でclient取得 → MainScreen

### 新規ユーザー

1. Welcome → 新規登録 → QRスキャン/招待コード → トレーナー確認 → login_screen
2. 「Googleでログイン」タップ → 上記3-4と同じ
3. `app.dart`でsession検知 → clientsレコードなし → 登録フロー継続（ProfileSetupScreen）
4. ProfileSetupScreenでGoogle userMetadata（`full_name`, `avatar_url`）をプリフィル

## 変更対象ファイル

| ファイル | 変更内容 |
|----------|----------|
| `pubspec.yaml` | `google_sign_in` パッケージ追加 |
| iOS `Info.plist` | Google Sign-In用のURL Scheme設定 + `GIDClientID`キー追加 |
| Android `build.gradle.kts` | Google Sign-In用の設定（SHA-1等） |
| `auth_repository.dart` | `signInWithGoogle()` メソッド追加 |
| `auth_provider.dart` | `signInWithGoogle()` アクション追加 |
| `login_screen.dart` | 「Googleでログイン」ボタン追加 + `_isGoogleLoading`状態追加。現在`AuthRepository`を直接使用しているパターンを維持し、`signInWithGoogle()`も同様に`AuthRepository`経由で呼ぶ |
| `profile_setup_screen.dart` | `initState`でSupabase `user.userMetadata`から`full_name`を`_nameController`にプリフィル。`avatar_url`はURLなので`NetworkImage`で表示（`File?`との共存: URLがある場合はネットワーク画像表示、ユーザーが画像を選択したら`File`で上書き） |
| `registration_provider.dart` | 変更なし（プリフィルは`profile_setup_screen`のinitStateで直接Supabase userMetadataを読むため） |

### app.dart について

`app.dart`の`_AuthLoadingScreen`ルーティングロジックは**変更不要**。理由:
- Google認証後、`AuthState` streamがsession検知 → `currentClientProvider`を`watch` → clientsレコードの有無で分岐する既存フローがそのまま機能する
- 新規ユーザー（clientsレコードなし）で`registrationState.hasTrainer`が`false`の場合 → `WelcomeScreen`に戻るが、これは登録フロー中にトレーナー紐付けが完了していないケースなので正しい動作

## login_screen UI

```
┌─────────────────────────┐
│  メールアドレス入力欄     │
│  [認証メールを送信]       │
│                          │
│  ──── または ────         │
│                          │
│  [G Googleでログイン]     │  ← _isGoogleLoading中はCircularProgressIndicator表示
└─────────────────────────┘
```

Web版と同様に「または」の区切り線 + Googleボタンの構成。Googleボタンにもローディング状態を実装。

## エラーハンドリング

- Google Sign-Inキャンセル → 何もせず元の画面に戻る（`_isGoogleLoading`をfalseに）
- IDトークン取得失敗 → エラーSnackBar表示
- Supabase認証失敗 → エラーSnackBar表示
- 既にマジックリンクで登録済みのメールでGoogle認証 → Supabaseがアカウントリンク（同一メールなら同一ユーザーに紐付く設定前提）

### エッジケース: メールアドレス不一致

マジックリンクで`alice@gmail.com`で登録済みのユーザーが、別のGoogleアカウント（`alice-work@gmail.com`）でログインした場合:
- Supabaseは別ユーザーとして新規作成する
- `clients`テーブルにレコードがないため、新規登録フローに入る
- これは想定通りの動作であり、特別な対応は不要（別アカウント = 別ユーザー）

## プラットフォーム設定

### Google Cloud Console

- OAuth 2.0クライアントID作成（iOS用、Android用、**Web用** — Supabase側の設定に必要）
- Supabase Dashboard → Authentication → Providers → Google を有効化
  - Web Client IDとClient Secretを設定
  - **`Skip nonce check`を有効にする**（iOS の `google_sign_in` + Supabase で必須）

### iOS

- `Info.plist`にReversed Client IDをURL Schemeとして追加
- `Info.plist`に`GIDClientID`キーでiOS Client IDを設定
- `GoogleService-Info.plist`は既にFirebase用に存在する。Google Cloud ConsoleでGoogle Sign-Inを有効にした場合、既存ファイルを再ダウンロードして更新する

### Android

- `android/app/build.gradle.kts` にSHA-1フィンガープリント設定
- `google-services.json`は既にFirebase用に存在する。Google Cloud ConsoleでGoogle Sign-Inを有効にした場合、既存ファイルを再ダウンロードして更新する

## テスト方針

- `auth_repository.dart`のユニットテスト（google_sign_inをモック）
- login_screenのWidgetテスト（Googleボタン表示・タップ確認、ローディング状態）
- profile_setup_screenのWidgetテスト（Google userMetadataからのプリフィル確認）
