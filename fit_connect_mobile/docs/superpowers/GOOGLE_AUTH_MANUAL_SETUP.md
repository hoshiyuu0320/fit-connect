# Google認証 手動セットアップ手順書

この手順書は、コード実装（`feature/google-auth`ブランチ）完了後に必要な手動設定をまとめたものです。

**前提条件:**
- Google Cloud Console へのアクセス権限
- Supabase Dashboard へのアクセス権限
- Xcode がインストール済み（iOS設定用）
- Firebase プロジェクトが既に設定済み

**プロジェクト情報:**
| 項目                  | 値                                                   |
| --------------------- | ---------------------------------------------------- |
| iOS Bundle ID         | `com.fitconnect.fitConnectMobile`                    |
| Android Package Name  | `com.fitconnect.fit_connect_mobile`                  |
| Supabase Callback URL | `https://<project-ref>.supabase.co/auth/v1/callback` |

---

## Step 1: Google Cloud Console — OAuth クライアントID 作成

### 1-1. Google Cloud Console にアクセス

1. https://console.cloud.google.com を開く
2. Firebase で使用しているプロジェクトを選択
3. 左メニュー → **APIとサービス** → **認証情報**

### 1-2. Web 用クライアントID を作成

> Supabase が Google のトークンを検証するために必要

1. **+ 認証情報を作成** → **OAuth クライアント ID**
2. アプリケーションの種類: **ウェブ アプリケーション**
3. 名前: `FIT-CONNECT Supabase`（任意）
4. **承認済みのリダイレクト URI** に追加:
   ```
   https://<your-project-ref>.supabase.co/auth/v1/callback
   ```
   ※ `<your-project-ref>` は Supabase Dashboard の Settings → General → Reference ID で確認
5. **作成** をクリック
6. 表示された **クライアントID** と **クライアントシークレット** をメモ

```
📝 メモ:
Web Client ID:     ____________________________________
Web Client Secret: ____________________________________
```

### 1-3. iOS 用クライアントID を作成

1. **+ 認証情報を作成** → **OAuth クライアント ID**
2. アプリケーションの種類: **iOS**
3. 名前: `FIT-CONNECT iOS`（任意）
4. バンドルID: `com.fitconnect.fitConnectMobile`
5. **作成** をクリック
6. 表示された **クライアントID** をメモ

```
📝 メモ:
iOS Client ID:          ____________________________________
Reversed Client ID:     ____________________________________
（iOS Client IDをそのまま逆順にしたもの。
  例: 123456.apps.googleusercontent.com → com.googleusercontent.apps.123456）
```

### 1-4. Android 用クライアントID を作成

1. まず SHA-1 フィンガープリントを取得:
   ```bash
   cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/fit_connect_mobile/android
   ./gradlew signingReport
   ```
   出力から `SHA1:` の行をコピー（debug用）

2. **+ 認証情報を作成** → **OAuth クライアント ID**
3. アプリケーションの種類: **Android**
4. 名前: `FIT-CONNECT Android`（任意）
5. パッケージ名: `com.fitconnect.fit_connect_mobile`
6. SHA-1 証明書フィンガープリント: 上で取得した値を貼り付け
7. **作成** をクリック

```
📝 メモ:
Android SHA-1: ____________________________________
```

> **本番用**: リリース時は本番署名キーの SHA-1 も追加する必要があります

---

## Step 2: Supabase Dashboard — Google Provider 有効化

1. https://supabase.com/dashboard でプロジェクトを開く
2. 左メニュー → **Authentication** → **Providers**
3. **Google** を見つけてクリック
4. **Enable Sign in with Google** をオンにする
5. 以下を入力:

| 項目          | 入力値                                    |
| ------------- | ----------------------------------------- |
| Client ID     | Step 1-2 でメモした **Web Client ID**     |
| Client Secret | Step 1-2 でメモした **Web Client Secret** |

6. **Skip nonce check** を **有効にする（トグルをオン）**

> ⚠️ **重要**: `Skip nonce check` を有効にしないと、iOS の `google_sign_in` パッケージでエラーが発生します

7. **Save** をクリック

---

## Step 3: iOS — Info.plist 設定

### 3-1. Info.plist に URL Scheme を追加

ファイル: `ios/Runner/Info.plist`

`CFBundleURLTypes` の配列内に、既存の `fitconnectmobile` の dict の後に追加:

```xml
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>ここにReversed Client IDを貼り付け</string>
			</array>
		</dict>
```

例（Reversed Client IDが `com.googleusercontent.apps.123456789` の場合）:
```xml
				<string>com.googleusercontent.apps.123456789</string>
```

### 3-2. GIDClientID を追加

同じ `Info.plist` の `<dict>` 直下（`CFBundleURLTypes` と同じレベル）に追加:

```xml
	<key>GIDClientID</key>
	<string>ここにiOS Client IDを貼り付け</string>
```

例:
```xml
	<key>GIDClientID</key>
	<string>123456789.apps.googleusercontent.com</string>
```

### 3-3. GoogleService-Info.plist の更新

Google Sign-In を有効にした場合、Firebase Console から最新の設定ファイルをダウンロード:

1. https://console.firebase.google.com → プロジェクト設定
2. iOS アプリの **GoogleService-Info.plist** をダウンロード
3. 以下に上書き:
   ```
   ios/Runner/GoogleService-Info.plist
   ```

---

## Step 4: Android — google-services.json 更新

### 4-1. google-services.json の更新

1. https://console.firebase.google.com → プロジェクト設定
2. Android アプリの **google-services.json** をダウンロード
3. 以下に上書き:
   ```
   android/app/google-services.json
   ```

> Android では `google_sign_in` パッケージが `google-services.json` から自動的に設定を読み込むため、`build.gradle.kts` の変更は通常不要です

---

## Step 5: 設定のコミット

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/fit_connect_mobile

git add ios/Runner/Info.plist
git add ios/Runner/GoogleService-Info.plist
git add android/app/google-services.json
git commit -m "config: Google Sign-In プラットフォーム設定"
```

---

## Step 6: 動作確認

### 6-1. 起動

Web Client ID を `--dart-define` で渡して起動:

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/fit_connect_mobile

# iOS
flutter run -d ios --dart-define=GOOGLE_WEB_CLIENT_ID=<Web Client ID>

# Android
flutter run -d android --dart-define=GOOGLE_WEB_CLIENT_ID=<Web Client ID>
```

例:
```bash
flutter run -d ios --dart-define=GOOGLE_WEB_CLIENT_ID=123456789.apps.googleusercontent.com
```

### 6-2. テスト項目チェックリスト

#### ログイン画面の表示
- [ ] Welcome画面 → 「ログイン」→ login_screen が表示される
- [ ] 「または」区切り線が表示される
- [ ] 「Googleでログイン」ボタンが表示される

#### Google認証（既存ユーザー）
- [ ] 「Googleでログイン」タップ → Google のネイティブ認証ダイアログが表示される
- [ ] アカウント選択 → ログイン成功 → MainScreen に遷移
- [ ] 認証中は両方のボタンが無効化される

#### Google認証（新規ユーザー）
- [ ] Welcome → 新規登録 → QRスキャン/招待コード → トレーナー確認 → login_screen
- [ ] 「Googleでログイン」タップ → 認証成功
- [ ] ProfileSetupScreen に遷移
- [ ] 名前が Google アカウント名でプリフィルされている
- [ ] アバター画像が Google プロフィール画像で表示されている
- [ ] そのまま登録完了できる

#### キャンセル・エラー
- [ ] Google ダイアログでキャンセル → login_screen に戻る（エラーなし）
- [ ] 機内モードで「Googleでログイン」→ エラー SnackBar が表示される

---

## トラブルシューティング

### iOS で Google ダイアログが表示されない
- `Info.plist` の `GIDClientID` が正しいか確認
- `CFBundleURLSchemes` に Reversed Client ID が設定されているか確認
- `GoogleService-Info.plist` が最新か確認

### Android で認証エラー
- `google-services.json` が最新か確認
- SHA-1 フィンガープリントが Google Cloud Console に登録されているか確認
- debug / release で SHA-1 が異なるので注意

### Supabase で「nonce mismatch」エラー
- Supabase Dashboard → Authentication → Providers → Google
- **Skip nonce check** が有効になっているか確認

### 「GOOGLE_WEB_CLIENT_ID must be set」エラー
- `--dart-define=GOOGLE_WEB_CLIENT_ID=xxx` を起動コマンドに含めているか確認
- Client ID が Web 用のものであること（iOS/Android 用ではない）

### 「IDトークンを取得できませんでした」エラー
- Google Cloud Console で Web Client ID の **承認済みのリダイレクト URI** に Supabase の callback URL が設定されているか確認
- `serverClientId`（Web Client ID）が正しいか確認
