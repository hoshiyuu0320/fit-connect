# Web Push 通知の仕組みと確認

**更新日**: 2026/10/04（フェーズ9.1 拡張 トレーナー向け push の PR1。削除済みの `/api/push-notify` 前提を今の経路に直した）

## 概要

トレーナーのブラウザに通知（Web Push）を届ける仕組みです。今はクライアントからのメッセージ受信を通知します。
鍵（VAPID）の設定と、設定後の確認の手順は `docs/tasks/2026-07-19-webpush-vapid-setup.md`（オーナー作業）にあります。

### 通知の流れ

```
クライアントがメッセージ送信
  → messages テーブルに INSERT
  → トリガー → Edge Function (parse-message-tags)
  → _shared/push.ts の sendNotification
      - notification_logs に記録（dedup_key で二重送信を防ぐ）
      - notification_preferences（種別のオン・オフ、静かな時間帯）を確認
      - device_tokens から宛先を読む（user_type = 'trainer' の web_push 行）
      - npm:web-push で、Edge Functions の secrets の VAPID 鍵で署名して送信
  → ブラウザの Service Worker (public/sw.js) が受信して通知を表示
  → 通知をクリック → /message
```

### 購読の登録

1. 設定画面（`/settings`）の「プッシュ通知」をオンにする
2. ブラウザの許可 → Service Worker（`/sw.js`）の登録 → `pushManager.subscribe`（`NEXT_PUBLIC_VAPID_PUBLIC_KEY` を使う）
3. `POST /api/push-subscriptions` で `device_tokens`（`user_type = 'trainer'`・`platform = 'web_push'`）に保存する。同じブラウザ（endpoint）を他のトレーナーが登録していれば、その行は消える（購読は最後に登録したトレーナー1人のもの）。旧 `push_subscriptions` にも両書きする（段階移行。送信側は読まない）

設定画面を開くたびに、ブラウザに購読があれば次のどちらかを自動で行います。
- 購読の鍵が今の公開鍵と同じ（または比べられない）: サーバーへ送り直す（ブラウザでは購読済みなのにサーバーに行が無い状態が直る）
- 購読の鍵が今の公開鍵と違う（鍵を変えた後の古い購読）: サーバーの行とブラウザの購読を消し、「もう一度オンにしてください」と案内する

---

## 環境変数

| 変数名 | 設定場所 | 必須 | 説明 |
|--------|---------|------|------|
| `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | Vercel（ローカルは `.env.local`） | 必須 | VAPID 公開鍵（ブラウザで購読するときに使う。ビルド時に埋め込まれる） |
| `VAPID_PUBLIC_KEY` | Supabase Edge Functions の secrets | 必須 | 上と同じ公開鍵 |
| `VAPID_PRIVATE_KEY` | Supabase Edge Functions の secrets | 必須 | VAPID 秘密鍵（送信時の署名） |
| `VAPID_SUBJECT` | Supabase Edge Functions の secrets | 必須 | 連絡先（`mailto:` か `https:`） |

- Vercel に `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` / `PUSH_API_KEY`、Edge Functions に `APP_URL` / `PUSH_API_KEY` は要りません（削除済みの `/api/push-notify` 用でした）
- 鍵の値はリポジトリ・ドキュメントに書かないこと
- 鍵を生成するときは `npx web-push generate-vapid-keys`。一度使い始めた鍵を変えると、既存の購読には届かなくなります（変える順序は手順書）

---

## 動作確認

### 購読の登録

1. ログインして設定画面（`/settings`）を開き、「プッシュ通知」をオンにする
2. ブラウザの通知許可ダイアログで「許可」を選ぶ
3. トグルがオンになることを確かめる

DB では、`device_tokens` に `user_type = 'trainer'`・`platform = 'web_push'` の行ができていることを確かめる。

### 通知

1. クライアント（モバイルアプリ）から、本文のあるテキストのメッセージを担当トレーナーに送る
2. ブラウザ通知が表示されることを確かめる
3. `notification_logs` のそのメッセージの行（`dedup_key = 'message:<メッセージID>'`）が `sent` になっていることを確かめる

---

## トラブルシューティング

### 「現在プッシュ通知を有効にできません」と表示される

`NEXT_PUBLIC_VAPID_PUBLIC_KEY` が設定されていません。Vercel に設定して再デプロイする（ローカルは `.env.local` に設定して開発サーバーを再起動する）。

### 「通知の設定が変わりました。もう一度オンにしてください。」と表示される

鍵が変わったため、古い購読を解除しました。「プッシュ通知」をもう一度オンにしてください。

### 通知がブロックされている

ブラウザで一度「拒否」すると、再度許可ダイアログは表示されません。
ブラウザのアドレスバー横の鍵アイコン → サイトの設定 → 通知 → 「許可」に変更してください。

### 通知が届かない

`notification_logs` のその通知の行の `status` / `detail` を見る。

| `status` / `detail` | 対処 |
|---|---|
| `skipped` / `no_tokens` | `device_tokens` に購読が無い。設定画面でオンにする |
| `skipped` / `disabled` | 通知設定で種別がオフ |
| `skipped` / `quiet_hours` | 静かな時間帯 |
| `skipped`（`web_push:skipped(vapid_not_configured)`） | Edge Functions の secrets に VAPID 鍵が無い |
| `failed`（`detail` に `invalid_cleaned=1`） | 購読の失効（push サービスが 404 / 410）。Logs には `[WebPush] Subscription expired` が出る。`device_tokens` の行は自動で消え、次からは `no_tokens` になる。設定画面でオンにし直す |
| `failed`（それ以外） | Edge Functions の Logs の `[WebPush] Error sending notification` の `statusCode`。`403` は鍵の不一致（Vercel の公開鍵と Edge Functions の鍵が対になっていない） |

### ブラウザを閉じると通知が届かない

- **Chrome / Edge**: ブラウザのプロセスがバックグラウンドで動いていれば届きます（macOS ではメニューバー・Dock にアイコンが残っている状態）
- **完全にブラウザを終了した場合**: その場では届きません。push サービスが通知を預かっている間（有効期限内）にブラウザを起動すると、そのときに届きます
- **Firefox**: ブラウザが起動している間に受信します

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `public/sw.js` | Service Worker（通知受信・クリック処理） |
| `src/components/settings/NotificationSection.tsx` | 通知の許可・解除・種別の設定、設定画面を開いたときの購読の登録し直し |
| `src/lib/notifications/pushSubscriptionKey.ts` | 購読の鍵と公開鍵の比較 |
| `src/lib/notifications/syncPushSubscription.ts` | 購読の登録し直し・古い鍵の購読の解除の分岐 |
| `src/app/api/push-subscriptions/route.ts` | 購読の登録・解除 API |
| `src/lib/supabase/savePushSubscription.ts` | 購読の保存（`device_tokens` が主。同じ endpoint の他のトレーナーの行を消す） |
| `src/lib/supabase/deletePushSubscription.ts` | 購読の削除 |
| `supabase/functions/_shared/push.ts` | 統一ディスパッチャ（`sendNotification`） |
| `supabase/functions/parse-message-tags/index.ts` | メッセージ受信時に `sendNotification` を呼ぶ |
