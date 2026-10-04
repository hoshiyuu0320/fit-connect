# Web Push（VAPID）の鍵の設定と確認（オーナー作業）

**作成日**: 2026/07/19（フェーズ7.3 通知基盤統一）
**更新日**: 2026/10/04（フェーズ9.1 拡張 トレーナー向け push の PR1。鍵の置き場所・変える順序・確認の判定を追記）
**所要時間**: 設定 5分 / 確認 10分

> **⚠️ 2026-10-04 時点で、Edge Functions に登録されている鍵は作り直しが必要です。**
> 登録された鍵の組が、以前このリポジトリ（PUBLIC）の `fit-connect/docs/SETUP_PUSH_NOTIFICATIONS.md` に「出力例」として載っていたものと同じでした（git の履歴と、PR1 より前の develop / main に残っています）。
> トレーナーのブラウザの購読がまだ0件のうちに、下の「鍵を変えるときの順序」で作り直してください。**PR1（Web Push の土台）の Web のリリースと手順0 より前**に済ませると、誰にも影響しません。Vercel に残っている `VAPID_PRIVATE_KEY` も消してください。

## 背景

通知は Edge Functions の統一ディスパッチャ（`supabase/functions/_shared/push.ts`）から送ります。
トレーナー向けのブラウザ通知（Web Push）は、ブラウザが購読するときに使う **公開鍵** と、
Edge Functions が送るときに署名する **秘密鍵** の組（VAPID の鍵）で動きます。

| 置き場所 | 名前 | 使うところ |
|---|---|---|
| Vercel（Web） | `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | 設定画面でブラウザが購読するとき（ビルド時に埋め込まれる。変えたら再デプロイ） |
| Edge Functions の secrets | `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` | 通知を送るときの署名 |

- Vercel に `VAPID_PRIVATE_KEY` は要りません（`fit-connect/src` に参照がありません。以前の `/api/push-notify` はフェーズ7.3 で削除済み）。残っていれば消して構いません
- 秘密鍵の正本は、Edge Functions の secrets と、それとは別の安全な保管先（パスワードマネージャーなど）に置きます。リポジトリ・このファイル・チャットには書きません
- **未設定の間の挙動**: Web Push は自動的にスキップされます（`notification_logs.detail` に `web_push:skipped(vapid_not_configured)`。エラーにはなりません）

## 手順（初回の設定）

ルート `FIT-CONNECT/` ディレクトリから以下を実行します。

```bash
supabase secrets set \
  VAPID_PUBLIC_KEY=<公開鍵> \
  VAPID_PRIVATE_KEY=<秘密鍵> \
  VAPID_SUBJECT=mailto:<連絡先メールアドレス>
```

- `VAPID_PUBLIC_KEY` は Vercel の `NEXT_PUBLIC_VAPID_PUBLIC_KEY` と同じ値、`VAPID_PRIVATE_KEY` はその対になる秘密鍵
- `VAPID_SUBJECT` は `mailto:` か `https:` の形（例: `mailto:admin@example.com`）
- `supabase secrets list` で3つの名前が表示されれば設定済み（値は表示されません）。Edge Functions の再デプロイは不要です

設定したら、下の「確認（手順0）」を行います。

## 鍵を変えるときの順序

0. 新しい鍵を手元で作る: `npx web-push generate-vapid-keys`。秘密鍵はパスワードマネージャーなど、リポジトリの外の安全な場所に控える（リポジトリ・チャット・このファイルには書かない）
1. Edge Functions の secrets（`VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY`）を新しい鍵に変える（`supabase secrets set VAPID_PUBLIC_KEY=<新しい公開鍵> VAPID_PRIVATE_KEY=<新しい秘密鍵>`。`VAPID_SUBJECT` は変えなくてよい）
2. Vercel の `NEXT_PUBLIC_VAPID_PUBLIC_KEY` を変えて再デプロイ
3. 再デプロイが終わったら、開いている fit-connect のタブをすべて再読み込みする（デプロイ前から開いている設定画面は古い公開鍵のまま購読し、送信が 403 になる）
4. `supabase secrets list` で、`VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` の DIGEST が変わったことを確かめる（値は表示されない）
5. 下の「確認（手順0）」を行う

- Vercel だけ先に変わると、その間に設定画面を開いた人の、動いていた購読が自動で解除されます（設定画面は、ブラウザの購読の鍵が今の公開鍵と違うとき、購読を解除して「もう一度オンにしてください」と案内します）
- 鍵を変えると、古い鍵で作った購読には届かなくなります（push サービスが 403 で拒否）。各トレーナーが設定画面を開くと解除され、もう一度オンにすると新しい鍵で購読し直せます

## 確認（手順0。鍵を設定・変更するたびに行う）

1. Vercel を再デプロイした場合は、デプロイが終わってから、開いている fit-connect のタブをすべて再読み込みして進める
2. 本番の Web の「設定」→「プッシュ通知」をオンにする。すでにオンなら一度オフにしてからオン（鍵を変えた後は、設定画面を開くと古い購読が自動で解除されてオフになっているので、そのままオン）。ブラウザに許可を求められたら許可
3. テスト用の顧客アプリから、**本文のあるテキスト**のメッセージを1通送る。その顧客の担当トレーナーが、手順2でブラウザを登録したトレーナーであること（画像だけのメッセージは通知されない。担当が違うと届かない）
4. 判定は `notification_logs` の、そのメッセージの行で行う（ブラウザに通知が出たかは補助。OS の集中モードなどでも出ない）

```sql
-- 直近のメッセージ通知（そのメッセージの行は dedup_key = 'message:<メッセージID>'）
select dedup_key, status, detail, created_at
from public.notification_logs
where kind = 'message'
order by created_at desc
limit 3;

-- ブラウザの購読の登録数（トレーナーの web_push）
select count(*) from public.device_tokens where user_type = 'trainer' and platform = 'web_push';
```

| `status` / `detail` | 意味 |
|---|---|
| `sent`（`sent=1/1`） | 鍵が一致している（push サービスが署名を受け付けた） |
| `failed` | Edge Functions の Logs の `[WebPush] Error sending notification` の `statusCode` を見る。`403` なら鍵の不一致 |
| `skipped` / `no_tokens` | `device_tokens`（トレーナーの `web_push`）に行が無い。手順2をやり直す |
| `skipped`（`web_push:skipped(vapid_not_configured)`） | Edge Functions の secrets に VAPID の鍵が無い（3つの名前を `supabase secrets list` で確かめる） |
| `partial` | 複数のブラウザのうち一部だけに届いた。届かなかったものは、Logs の `[WebPush] Subscription expired`（失効。行は自動で消える）か `[WebPush] Error sending notification` の `statusCode` で見分ける |
| `skipped` / `disabled`・`quiet_hours` | 通知設定（メッセージ受信がオフ・静かな時間帯）のため |

## 注意

- **鍵の値をリポジトリにコミットしないこと**（このファイルにも値を書かない）
- 同じブラウザを複数のトレーナーで使うと、購読は最後に登録したトレーナーのものになります（前のトレーナーの行は登録時に消えます）
