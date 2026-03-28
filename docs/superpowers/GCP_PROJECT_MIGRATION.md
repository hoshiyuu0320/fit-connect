# GCPプロジェクト統一 移行手順書

Google OAuth のクライアントIDを Firebase プロジェクト側の GCP に統一する。
現在、Web版（fit-connect）の Google OAuth が別の GCP プロジェクトに作成されているため、
Firebase 側のプロジェクトに移行して Web / iOS / Android を統一管理する。

---

## 現状

```
GCPプロジェクトA（旧・Web用）
└── Web Client ID ← fit-connect の Google認証で使用中
    └── Supabase Dashboard に設定済み

GCPプロジェクトB（Firebase用）
└── Firebase 設定（FCM、google-services.json 等）
    └── fit-connect-mobile で使用中
```

## 目標

```
GCPプロジェクトB（Firebase用）に統一
├── Web Client ID      ← 新規作成
├── iOS Client ID      ← 新規作成
├── Android Client ID  ← 新規作成
└── Firebase 設定      ← 既存のまま
```

---

## 影響範囲

| アプリ | 影響 |
|--------|------|
| fit-connect（Web） | Supabase の Google Provider 設定を更新するだけ。**コード変更なし** |
| fit-connect-mobile | 新しい Client ID で設定。Info.plist / google-services.json を更新 |

**Web版のコード変更が不要な理由:**
Web版は `supabase.auth.signInWithOAuth({ provider: 'google' })` を使っており、
Client ID はSupabase側が管理する。GCPプロジェクトを変えてもSupabase Dashboardの設定を更新すれば動く。

---

## 手順

### Step 1: Firebase側のGCPプロジェクトでOAuth同意画面を設定

> 既に設定済みの場合はスキップ

1. https://console.cloud.google.com を開く
2. **Firebase で使用しているプロジェクト**を選択
3. 左メニュー → **APIとサービス** → **OAuth 同意画面**
4. 以下を設定:
   - ユーザータイプ: **外部**
   - アプリ名: `FIT-CONNECT`
   - サポートメール: 自分のメールアドレス
   - 承認済みドメイン: `supabase.co` を追加（Supabase の callback URL 用）
   - デベロッパー連絡先: 自分のメールアドレス
5. スコープ: `email`, `profile`, `openid`（デフォルトでOK）
6. テストユーザー: 本番公開前は自分のGoogleアカウントを追加

### Step 2: Web用 OAuth クライアントIDを作成

1. 左メニュー → **APIとサービス** → **認証情報**
2. **+ 認証情報を作成** → **OAuth クライアント ID**
3. 設定:
   - アプリケーションの種類: **ウェブ アプリケーション**
   - 名前: `FIT-CONNECT Web`
   - 承認済みの JavaScript 生成元:
     ```
     http://localhost:3000
     ```
     ※ 本番ドメインがあれば追加
   - 承認済みのリダイレクト URI:
     ```
     https://<supabase-project-ref>.supabase.co/auth/v1/callback
     ```
     ※ `<supabase-project-ref>` は Supabase Dashboard → Settings → General → Reference ID
4. **作成** をクリック
5. **クライアントID** と **クライアントシークレット** をメモ

```
📝 メモ:
新 Web Client ID:     ____________________________________
新 Web Client Secret: ____________________________________
```

### Step 3: iOS用 OAuth クライアントIDを作成

1. **+ 認証情報を作成** → **OAuth クライアント ID**
2. 設定:
   - アプリケーションの種類: **iOS**
   - 名前: `FIT-CONNECT iOS`
   - バンドルID: `com.fitconnect.fitConnectMobile`
3. **作成** をクリック
4. **クライアントID** をメモ

```
📝 メモ:
iOS Client ID:      ____________________________________
Reversed Client ID: ____________________________________
（形式: com.googleusercontent.apps.XXXX — iOS Client ID を逆順にしたもの）
```

### Step 4: Android用 OAuth クライアントIDを作成

1. SHA-1 フィンガープリントを取得（まだの場合）:
   ```bash
   cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/fit_connect_mobile/android
   ./gradlew signingReport
   ```
2. **+ 認証情報を作成** → **OAuth クライアント ID**
3. 設定:
   - アプリケーションの種類: **Android**
   - 名前: `FIT-CONNECT Android`
   - パッケージ名: `com.fitconnect.fit_connect_mobile`
   - SHA-1 証明書フィンガープリント: 上で取得した値
4. **作成** をクリック

### Step 5: Supabase Dashboard を更新

> ⚠️ この手順を実行すると、新しい設定が反映されるまで一時的にWeb版のGoogle認証が使えなくなります。
> 数分で完了するので影響は最小限です。

1. https://supabase.com/dashboard → プロジェクトを開く
2. **Authentication** → **Providers** → **Google**
3. 以下を更新:

| 項目 | 変更内容 |
|------|----------|
| **Client ID (for oauth)** | Step 2 の新 Web Client ID に変更 |
| **Client Secret (for oauth)** | Step 2 の新 Web Client Secret に変更 |
| **Authorized Client IDs** | iOS Client ID をカンマ区切りで追加（IDトークン検証用） |
| **Skip nonce check** | **有効にする**（まだの場合） |

**Authorized Client IDs の入力例:**
```
123456789-web.apps.googleusercontent.com,123456789-ios.apps.googleusercontent.com
```

> **なぜ iOS Client ID を追加するのか:**
> iOS の `google_sign_in` は IDトークンの `aud`（audience）に iOS Client ID を設定する。
> Supabase がこのトークンを受け入れるには、Authorized Client IDs にその iOS Client ID が含まれている必要がある。

4. **Save** をクリック

### Step 6: iOS — Info.plist 設定

ファイル: `fit_connect_mobile/ios/Runner/Info.plist`

#### 6-1. CFBundleURLTypes に Reversed Client ID を追加

既存の `CFBundleURLTypes` 配列内、`fitconnectmobile` の dict の後に追加:

```xml
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>（Step 3 の Reversed Client ID）</string>
			</array>
		</dict>
```

#### 6-2. GIDClientID を追加

`Info.plist` の `<dict>` 直下に追加:

```xml
	<key>GIDClientID</key>
	<string>（Step 3 の iOS Client ID）</string>
```

#### 6-3. GoogleService-Info.plist の更新（任意）

Google Sign-In を Firebase プロジェクト側で有効にした場合は、Firebase Console から最新の `GoogleService-Info.plist` を再ダウンロードして上書き:

```
ios/Runner/GoogleService-Info.plist
```

### Step 7: Android — google-services.json 更新（任意）

Firebase Console から最新の `google-services.json` をダウンロードして上書き:

```
android/app/google-services.json
```

> Android では `google_sign_in` は `serverClientId`（Web Client ID）を使ってIDトークンを取得するため、
> `google-services.json` の更新は必須ではないが、GCPプロジェクトの整合性のために推奨。

### Step 8: 設定をコミット

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/fit_connect_mobile

git add ios/Runner/Info.plist
git commit -m "config: Google Sign-In iOS 設定を追加"
```

※ `GoogleService-Info.plist` と `google-services.json` を更新した場合はそれも含める

---

## 動作確認

### 確認1: Web版（fit-connect）のGoogle認証

> Supabase の設定を変更した直後に確認すること

1. fit-connect の開発サーバーを起動:
   ```bash
   cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
   npm run dev
   ```
2. http://localhost:3000 にアクセス
3. **「Googleでログイン」をクリック**
4. 確認項目:
   - [ ] Google の OAuth 同意画面が表示される
   - [ ] アカウント選択後、ダッシュボードにリダイレクトされる
   - [ ] ログイン状態が正常（ユーザー名等が表示される）
5. **ログアウト → 再度「Googleでログイン」** を試す
   - [ ] 既存ユーザーとして正常にログインできる

> ⚠️ ここで失敗する場合は Supabase Dashboard の Client ID / Secret が正しいか再確認

### 確認2: Mobile（fit-connect-mobile）のGoogle認証 — ログイン画面表示

1. モバイルアプリを起動:
   ```bash
   cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/fit_connect_mobile
   flutter run -d ios --dart-define=GOOGLE_WEB_CLIENT_ID=（Step 2 の Web Client ID）
   ```
2. 確認項目:
   - [ ] Welcome画面 → 「ログイン」→ login_screen が表示される
   - [ ] 「または」区切り線が表示される
   - [ ] 「Googleでログイン」ボタンが表示される

### 確認3: Mobile — Google認証（既存ユーザー再ログイン）

1. login_screen で **「Googleでログイン」をタップ**
2. 確認項目:
   - [ ] Google のネイティブ認証ダイアログが表示される
   - [ ] 認証中は「Googleでログイン」ボタンにスピナーが表示される
   - [ ] 認証中は「認証メールを送信」ボタンも無効化されている
   - [ ] アカウント選択 → ログイン成功 → MainScreen に遷移する

### 確認4: Mobile — Google認証（新規ユーザー登録フロー）

> 新規 Google アカウント（clients テーブルに未登録）で確認

1. Welcome → **新規登録** → QRスキャン/招待コード → トレーナー確認 → login_screen
2. **「Googleでログイン」をタップ**
3. 確認項目:
   - [ ] 認証成功後、ProfileSetupScreen に遷移する
   - [ ] 名前フィールドに Google アカウントの名前がプリフィルされている
   - [ ] プロフィール画像に Google アカウントのアバターが表示されている
   - [ ] 名前を変更しても問題なく登録完了できる
   - [ ] プロフィール画像を自分で選択したら、Google アバターが上書きされる
   - [ ] 「登録を完了する」→ 登録完了画面 → MainScreen に遷移する

### 確認5: Mobile — キャンセルとエラー処理

1. **キャンセル確認:**
   - [ ] 「Googleでログイン」→ Google ダイアログで「キャンセル」→ login_screen に戻る
   - [ ] エラー SnackBar は表示されない（キャンセルは正常動作）
   - [ ] ボタンが再度タップ可能に戻っている

2. **エラー確認:**
   - [ ] 機内モード → 「Googleでログイン」→ エラー SnackBar が表示される

### 確認6: Mobile — マジックリンク認証が引き続き動作すること

> Google認証の追加で既存フローが壊れていないか確認

1. login_screen で**メールアドレスを入力** → 「認証メールを送信」
2. 確認項目:
   - [ ] 「認証リンクをメールで送信しました」SnackBar が表示される
   - [ ] メール送信中は「Googleでログイン」ボタンも無効化されている
   - [ ] メール内リンクをタップ → 正常にログインできる

### 確認7: Android での動作確認（iOS確認後）

```bash
flutter run -d android --dart-define=GOOGLE_WEB_CLIENT_ID=（Step 2 の Web Client ID）
```

- [ ] 確認2〜6 と同じ項目を Android でも確認

---

## ロールバック手順

万が一問題が発生した場合、Supabase Dashboard で旧 Client ID / Secret に戻せば即座に復旧できる。

1. Supabase Dashboard → Authentication → Providers → Google
2. Client ID を旧 Web Client ID に戻す
3. Client Secret を旧 Web Client Secret に戻す
4. Save

```
📝 ロールバック用メモ（変更前に控えておくこと）:
旧 Web Client ID:     ____________________________________
旧 Web Client Secret: ____________________________________
```

---

## 移行完了後のクリーンアップ

全ての動作確認が完了したら:

1. **旧 GCP プロジェクト**の Web Client ID を削除（もう使わないため）
   - Google Cloud Console → 旧プロジェクト → 認証情報 → 該当のクライアントIDを削除
2. 旧プロジェクト自体が不要なら、プロジェクトのシャットダウンも検討
