# プッシュ通知セットアップ手順

FIT-CONNECT Mobile アプリのプッシュ通知を有効にするための手動セットアップ手順です。
コード実装は完了済みのため、以下の外部サービス設定を順番に行ってください。

---

## 1. Firebaseサービスアカウントキーの設定

Edge Function（parse-message-tags）がFCM HTTP v1 APIで通知を送信するために、Firebaseのサービスアカウントキーが必要です。

### 1-1. サービスアカウントキーの生成

1. [Firebase Console](https://console.firebase.google.com/) を開く
2. 対象プロジェクトを選択
3. 左上の **歯車アイコン** → **「プロジェクトの設定」** をクリック
4. **「サービスアカウント」** タブを選択
5. **「新しい秘密鍵の生成」** ボタンをクリック
6. 確認ダイアログで **「キーを生成」** をクリック
7. JSONファイルが自動ダウンロードされる

> **注意**: このJSONファイルには秘密鍵が含まれます。Gitにコミットしたり、他者に共有しないでください。

### 1-2. Supabase Secretsへの登録

1. [Supabase Dashboard](https://supabase.com/dashboard) を開く
2. 対象プロジェクト（`viribpvnpgtgtmeulcmx`）を選択
3. 左メニュー → **「Edge Functions」** をクリック
4. **「Secrets」** タブを選択（もしくは Settings → Edge Functions → Secrets）
5. **「Add new secret」** をクリック
6. 以下を入力:
   - **Name**: `FIREBASE_SERVICE_ACCOUNT_KEY`
   - **Value**: ダウンロードしたJSONファイルの **内容をそのまま貼り付け**
7. **「Save」** をクリック

### 確認方法

登録後、Edge Function のログで以下のメッセージが出なければ設定成功です:

```
[FCM] FIREBASE_SERVICE_ACCOUNT_KEY not set, skipping notification
```

---

## 2. Edge Functionのデプロイ

FCM通知送信機能が追加された Edge Function をデプロイします。

### 2-1. デプロイ実行

プロジェクトルートで以下を実行:

```bash
supabase functions deploy parse-message-tags
```

### 2-2. デプロイ確認

```bash
supabase functions list
```

`parse-message-tags` が一覧に表示され、ステータスが正常であることを確認してください。

### 2-3. ログ確認（任意）

デプロイ後にメッセージを送信し、ログを確認:

```bash
supabase functions logs parse-message-tags
```

正常時のログ例:

```
Received payload: {...}
Processing message: INSERT ...
[FCM] Notification sent successfully: {...}
```

---

## 3. iOS APNs設定

iOSでプッシュ通知を受信するには、Apple Push Notification service (APNs) の設定が必要です。

### 3-1. APNs認証キー(.p8)の作成

1. [Apple Developer Portal](https://developer.apple.com/account) にサインイン
2. **「Certificates, Identifiers & Profiles」** をクリック
3. 左メニュー → **「Keys」** をクリック
4. **「+」** ボタンをクリックして新しいキーを作成
5. 以下を設定:
   - **Key Name**: `FIT-CONNECT APNs Key`（任意の名前）
   - **Apple Push Notifications service (APNs)** にチェックを入れる
6. **「Continue」** → **「Register」** をクリック
7. **Key ID** をメモしておく（後で使用）
8. **「Download」** をクリックして `.p8` ファイルを保存

> **注意**: .p8ファイルは一度しかダウンロードできません。安全な場所に保管してください。

### 3-2. FirebaseにAPNsキーを登録

1. [Firebase Console](https://console.firebase.google.com/) → 対象プロジェクト
2. **歯車アイコン** → **「プロジェクトの設定」**
3. **「Cloud Messaging」** タブを選択
4. **「Apple アプリの構成」** セクションを探す
5. **「APNs認証キー」** の **「アップロード」** をクリック
6. 以下を入力:
   - **APNs認証キー**: ダウンロードした `.p8` ファイルを選択
   - **キーID**: Apple Developer Portalでメモした Key ID
   - **チームID**: Apple Developer アカウントのチームID
     - 確認方法: Apple Developer Portal → 右上の「Account」→ **「Membership details」** → Team ID
7. **「アップロード」** をクリック

### 3-3. Xcodeでの設定

1. Xcodeで `ios/Runner.xcodeproj` を開く

2. **Push Notifications Capability の追加**:
   - 左のナビゲーターで **「Runner」** プロジェクトを選択
   - **「Signing & Capabilities」** タブを選択
   - **「+ Capability」** ボタンをクリック
   - **「Push Notifications」** を検索して追加

3. **Entitlementsファイルの紐付け**:
   - **「Build Settings」** タブを選択
   - 検索バーに **「Code Signing Entitlements」** と入力
   - 以下を設定:
     - **Debug**: `Runner/Runner.entitlements`
     - **Release**: `Runner/RunnerRelease.entitlements`
     - **Profile**: `Runner/RunnerRelease.entitlements`

4. **Background Modes の確認**（必要に応じて）:
   - **「Signing & Capabilities」** タブ
   - **「+ Capability」** → **「Background Modes」** を追加
   - **「Remote notifications」** にチェックを入れる

---

## 4. 動作確認

### 4-1. プラットフォーム別の注意事項

| プラットフォーム | 通知テスト | 備考 |
|----------------|-----------|------|
| iOS 実機 | 可能 | Apple Developer Programへの登録が必要 |
| iOS Simulator | **不可** | APNsに対応していないため |
| Android 実機 | 可能 | Google Play Servicesが必要 |
| Android Emulator | 条件付き | Google Play Services搭載イメージが必要 |
| macOS | **不可** | Firebase初期化をスキップする設計 |

### 4-2. FCMトークン保存の確認

1. iOS/Android実機でアプリを起動
2. ログインする
3. コンソールログで以下を確認:
   ```
   [NotificationService] FCM Token: xxxxx...
   [App] FCMトークン保存完了
   ```
4. **Supabase Studio** → `clients` テーブル → 該当ユーザーの `fcm_token` カラムに値が入っていることを確認

### 4-3. メッセージ通知の確認

1. テスト用に2つのアカウントを用意（トレーナーとクライアント）
2. トレーナーからクライアントにメッセージを送信
3. 確認ポイント:
   - **フォアグラウンド**: アプリ使用中 → ローカル通知バナーが表示される
   - **バックグラウンド**: アプリをバックグラウンドに移動 → システム通知が表示される
   - **通知タップ**: 通知をタップ → アプリが開く
4. Edge Functionログを確認:
   ```bash
   supabase functions logs parse-message-tags
   ```
   ```
   [FCM] Notification sent successfully: {...}
   ```

### 4-4. 目標達成通知の確認

1. クライアントに目標体重を設定
2. 目標体重に到達するメッセージを送信（例: `#体重 60.0kg`）
3. 目標達成通知が届くことを確認
4. Edge Functionログ:
   ```
   🎉 Goal achieved! Client: xxxxx
   [FCM] Notification sent successfully: {...}
   ```

### 4-5. ログアウト時のトークン削除確認

1. アプリからログアウト
2. **Supabase Studio** → `clients` テーブル → 該当ユーザーの `fcm_token` が `null` になっていることを確認
3. コンソールログ:
   ```
   [AuthNotifier] FCMトークン削除完了
   ```

---

## トラブルシューティング

### 通知が届かない場合

1. **FCMトークンがDBに保存されているか確認**
   - Supabase Studio で `clients` テーブルの `fcm_token` を確認

2. **Edge Functionのログを確認**
   ```bash
   supabase functions logs parse-message-tags
   ```
   - `FIREBASE_SERVICE_ACCOUNT_KEY not set` → Secret未登録
   - `Failed to get access token` → サービスアカウントキーが不正
   - `No FCM token for receiver` → 受信者のFCMトークンが未保存

3. **iOS固有の問題**
   - APNs認証キーがFirebaseに正しく登録されているか
   - Xcodeで Push Notifications capability が追加されているか
   - 実機でテストしているか（Simulatorでは不可）

4. **Android固有の問題**
   - `google-services.json` が `android/app/` に配置されているか
   - Google Play Servicesが端末にインストールされているか

### FCMトークンが無効になった場合

Edge Functionのログに以下が表示される場合、トークンが無効です:

```
[FCM] Token is invalid, should be cleared from DB
```

ユーザーが再ログインすれば新しいトークンが自動的に保存されます。
