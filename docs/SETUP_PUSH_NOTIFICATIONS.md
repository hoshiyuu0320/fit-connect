# Web Push通知 セットアップ手順

## 概要

クライアントからトレーナーへのメッセージ受信時に、ブラウザがバックグラウンドでも通知を届けるWeb Push通知の設定手順です。

### 通知フロー

```
クライアントがメッセージ送信
  → messages テーブルに INSERT
  → Supabase Database Webhook → Edge Function (parse-message-tags)
  → Edge Function が push_subscriptions テーブルから購読情報を取得
  → Next.js API Route (POST /api/push-notify) を呼び出し
  → web-push ライブラリがブラウザのプッシュサーバーに送信
  → Service Worker (sw.js) が受信して通知を表示
  → トレーナーが通知をクリック → /message?clientId=XXX に遷移
```

---

## 1. VAPIDキーの生成

VAPIDキーはWeb Push通知の認証に使用するキーペアです。**一度生成したら変更しないでください**（変更すると既存の購読が全て無効になります）。

```bash
npx web-push generate-vapid-keys
```

出力例：
```
Public Key:
BH4ih9V8TFKz4dsaNXbmmDIvYS0BKbA7NFJNhuDDfCPhoWCcLNLUvSfeE2f--l77Z84PnspFTnHDVH49uSNhYFQ

Private Key:
RaxcJDG01jKndroQGFFvn0fZFCdaKTNiChvkStOTw3c
```

生成されたキーは安全な場所にバックアップしてください。

---

## 2. Next.js 環境変数の設定

`.env.local` に以下を追加：

```env
# Web Push通知 (VAPID)
NEXT_PUBLIC_VAPID_PUBLIC_KEY=（生成した公開鍵）
VAPID_PRIVATE_KEY=（生成した秘密鍵）
VAPID_SUBJECT=mailto:admin@fit-connect.com

# Push通知API認証キー（省略可、設定推奨）
PUSH_API_KEY=（任意のシークレット文字列）
```

### PUSH_API_KEY の生成方法（推奨）

```bash
openssl rand -hex 32
```

出力された文字列を `PUSH_API_KEY` に設定してください。

### Vercel（本番）の場合

Vercel Dashboard → Settings → Environment Variables に同じ変数を設定してください。

| 変数名 | Environment |
|--------|-------------|
| `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | Production, Preview, Development |
| `VAPID_PRIVATE_KEY` | Production, Preview |
| `VAPID_SUBJECT` | Production, Preview |
| `PUSH_API_KEY` | Production, Preview |

---

## 3. Supabase Edge Function Secrets の設定

Supabase Dashboard → Edge Functions → Secrets に以下を追加：

| 変数名 | 値 | 説明 |
|--------|-----|------|
| `APP_URL` | `https://your-app.vercel.app` | Next.jsアプリのデプロイURL |
| `PUSH_API_KEY` | `.env.local` と同じ値 | API Route認証キー（省略可） |

### APP_URL について

Edge Function がメッセージ受信時に `${APP_URL}/api/push-notify` を呼び出します。

- **本番**: Vercel等のデプロイURL（例: `https://fit-connect.vercel.app`）
- **ローカル開発**: Edge Function はSupabaseクラウド上で動作するため `localhost` は使用不可。ローカルでテストするには ngrok 等でトンネルを作成し、そのURLを設定してください。

---

## 4. Edge Function のデプロイ

Edge Function を更新した場合は再デプロイが必要です。

```bash
supabase functions deploy parse-message-tags
```

---

## 5. 動作確認

### トレーナー側（ブラウザ）

1. 開発サーバーを起動（`npm run dev`）
2. ログインして設定画面（`/settings`）を開く
3. 「通知設定」セクションで「プッシュ通知を有効にする」をクリック
4. ブラウザの通知許可ダイアログで「許可」を選択
5. 緑のインジケーター「通知は有効です」が表示されることを確認

### DB確認

Supabase Dashboard → Table Editor → `push_subscriptions` テーブルにレコードが作成されていることを確認。

### 通知テスト

1. クライアント（モバイルアプリ）からトレーナーにメッセージを送信
2. ブラウザのタブを別のページに切り替える or 最小化
3. ブラウザ通知が表示されることを確認
4. 通知をクリックしてメッセージ画面に遷移することを確認

---

## トラブルシューティング

### 「VAPID public key is not configured」エラー

`.env.local` に `NEXT_PUBLIC_VAPID_PUBLIC_KEY` が設定されていないか、開発サーバーの再起動が必要です。

```bash
# 開発サーバーを再起動
npm run dev
```

### 通知許可ボタンを押しても何も起きない

- ブラウザの開発者ツール → Console でエラーを確認
- HTTPS環境でないと Service Worker は登録できません（`localhost` は例外として許可）

### 通知がブロックされている

ブラウザで一度「拒否」すると、再度許可ダイアログは表示されません。
ブラウザのアドレスバー横の鍵アイコン → サイトの設定 → 通知 → 「許可」に変更してください。

### Edge Function から通知が送信されない

Supabase Dashboard → Edge Functions → Logs で以下を確認：

- `[WebPush] APP_URL not set` → Secrets に `APP_URL` を設定してください
- `[WebPush] No web push subscriptions for trainer` → トレーナーが通知を許可していません
- `[WebPush] API Route error: 401` → `PUSH_API_KEY` が一致していません

### ブラウザを閉じると通知が届かない

- **Chrome/Edge**: ブラウザのプロセスがバックグラウンドで動いていれば届きます（macOSではメニューバーにアイコンが残っている状態）
- **完全にブラウザを終了した場合**: 届きません
- **Firefox**: ブラウザが起動中のみ通知を受信します

---

## 環境変数一覧

| 変数名 | 設定場所 | 必須 | 説明 |
|--------|---------|------|------|
| `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | Next.js .env.local | 必須 | VAPID公開鍵（ブラウザで購読時に使用） |
| `VAPID_PRIVATE_KEY` | Next.js .env.local | 必須 | VAPID秘密鍵（通知送信時の署名に使用） |
| `VAPID_SUBJECT` | Next.js .env.local | 必須 | 連絡先（`mailto:` 形式） |
| `PUSH_API_KEY` | Next.js .env.local + Supabase Secrets | 推奨 | API Route認証キー |
| `APP_URL` | Supabase Edge Function Secrets | 必須 | Next.jsアプリのURL |

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `public/sw.js` | Service Worker（通知受信・クリック処理） |
| `src/components/settings/NotificationSection.tsx` | 通知許可/解除UI |
| `src/app/api/push-subscriptions/route.ts` | 購読登録・解除API |
| `src/app/api/push-notify/route.ts` | 通知送信API（web-push使用） |
| `src/lib/supabase/savePushSubscription.ts` | 購読情報保存 |
| `src/lib/supabase/deletePushSubscription.ts` | 購読情報削除 |
| `supabase/functions/parse-message-tags/index.ts` | Edge Function（sendWebPushToTrainer） |
