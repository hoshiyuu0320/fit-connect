# cron / Vault 初回セットアップ手順（ユーザー作業）

**作成日**: 2026-07-10
**対象**: プロジェクトオーナー（1回きりの手動作業）
**関連 migration**: `supabase/migrations/20260710020000_codify_cron_jobs.sql` / `20260829000300_cleanup_ai_images.sql` / `20260912000000_cron_use_secret_key.sql` / `20260913000000_session_reminder.sql` / `20260913000100_session_reminder_cron_target_date.sql`

`auto-skip-workouts` / `cleanup-ai-images` / `send-session-reminders` の cron ジョブは migration で「無効(inactive)状態」で登録されます。
実際に動かすには、以下の **(1) Vault シークレット登録** と **(2) ジョブの有効化** が必要です。
どちらも Supabase Dashboard の SQL Editor から実行します。

> **2026-09-12 時点の状態**: (1) Vault 登録は完了（`project_url` / `secret_key`）。
> `auto-skip-workouts` / `cleanup-ai-images` は本番 dry run 確認後に**有効化済み**（active = true）。
> 残るは **`send-session-reminders` のみ inactive**（§3 の手順で有効化する）。

> **2026-09-12 変更: 認証を新しい secret キー（`sb_secret_...`）の `apikey` ヘッダー方式に移行。**
> 旧 service_role キーを `Authorization: Bearer` で送る方式は、本番の関数側の値と一致せず 401 になっていた
> （旧キーは 2026 年末で廃止予定でもある）。cron は Vault の `secret_key` を `apikey` ヘッダーで送り、
> 関数は `supabase/functions/_shared/service_auth.ts` で `SUPABASE_SECRET_KEYS` と照合する（verify_jwt = false）。

---

## 1. Vault シークレットの登録（2件）

Supabase Dashboard → 対象プロジェクト → **SQL Editor** で以下を実行します。

### 1-1. `project_url`

```sql
select vault.create_secret('https://viribpvnpgtgtmeulcmx.supabase.co', 'project_url');
```

### 1-2. `secret_key`

Dashboard → **Settings → API Keys** →「Publishable and secret API keys」タブから
**secret キー（`default`、`sb_secret_...`）** の値をコピーし、`<secretキー>` 部分を置き換えて実行します。

```sql
select vault.create_secret('<secretキー>', 'secret_key');
```

> ⚠️ **secret キーは RLS を完全にバイパスする最高権限キーです。**
> - キーの値は **絶対にリポジトリ・チャット・ドキュメントに貼らない**こと
> - 上記 SQL は Dashboard の SQL Editor 上でのみ組み立てて実行すること
> - 実行後、SQL Editor の履歴に残したくない場合はクエリ履歴を削除すること

登録確認（値は表示されず、名前のみ確認）:

```sql
select name, created_at from vault.secrets order by created_at;
-- 'project_url' と 'secret_key' の2行が出ればOK
-- （旧方式の 'service_role_key' が残っていても動作に影響はない。不要なら削除してよい）
```

---

## 2. `auto-skip-workouts` ジョブの有効化

> 2026-09-12 に有効化済み（`cleanup-ai-images` も同日）。以下は有効化時に踏んだ手順の記録。

### ⚠️ 有効化前に必ず確認

- 初回実行時、**期限切れ（3日超）の pending 課題が一括で「スキップ」に変更されます**
  - 対象は `plan_type = 'self_guided'` のプランのみ（2026-09-12 修正。session 型はトレーナーが記録するため対象外）
  - 2026-09-12 時点の対象: self_guided 9件（session 型 19件は対象外で pending のまま）
- 対象限定の修正（ブランチ `fix/auto-skip-session-plans`）を**リモートにデプロイしてから**有効化すること。
  旧版のまま有効化すると session 型も skipped になる
- 有効化のタイミングはユーザー判断です（migration では意図的に無効状態で登録しています）

### 有効化前の dry run（推奨）

Edge Function に `{"dry_run": true}` を送ると、更新せずに候補一覧だけ返します。
SQL Editor から pg_net 経由で呼び出し、結果を確認します。

```sql
select net.http_post(
  url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/auto-skip-workouts',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'secret_key')
  ),
  body := '{"dry_run": true}'::jsonb
);
-- 数秒後、上の戻り値の request_id で結果を確認
select status_code, content from net._http_response where id = <request_id>;
```

`candidateCount` と `candidateIds` が self_guided の課題だけになっていれば OK です。

### 有効化 SQL

```sql
select cron.alter_job((select jobid from cron.job where jobname='auto-skip-workouts'), active := true);
```

（再度無効化したい場合は `active := false` で同じ SQL を実行）

実行スケジュール: `0 18 * * *`（UTC 18:00 = **JST 毎日 03:00**）

---

## 3. `send-session-reminders` ジョブの有効化

### ⚠️ 有効化前に必ず確認

- 有効化すると、**毎日 JST 20:00 に「翌日にセッション（scheduled / confirmed）がある実顧客」へ push 通知が飛びます**
  （通知種別 `session_reminder`。顧客は Mobile の通知設定でこの種別だけ OFF にできる）
- Edge Function `send-session-reminders` のデプロイと migration `20260913000000_session_reminder.sql` /
  `20260913000100_session_reminder_cron_target_date.sql` のリモート適用を**済ませてから**有効化すること
- **未反映のまま有効化しても cron 側はエラーにならない**。pg_net は HTTP リクエストを enqueue するだけなので
  `cron.job_run_details` は `succeeded` になり、関数側の 404 / 401 / 400 は `net._http_response` にしか残らない。
  有効化後の初回実行は必ず「4. 動作確認方法」の `net._http_response` と `notification_logs` で結果を確認すること
- 送信は `notification_logs.dedup_key`（`session_reminder:<session_id>:<対象日 YYYY-MM-DD>`）で冪等化される。
  **同じ `target_date` なら**手動で再実行しても二重送信にはならない（`target_date` が違えば別キーになり送られる）。
  逆に、通知設定 OFF や quiet hours で `skipped` になった分も同じキーで記録されるため、
  **同一セッション・同一対象日の再送はできない**
- 別日へリスケされたセッションは、**新しい対象日の前日 20:00 JST より前に変更した場合に限り**、新しいキーで再送される
- 既知の制約: cron は 20:00 JST に「その時点で翌日に予定されているセッション」を 1 回だけ拾う。
  **20:00 以降に翌日へ作成・移動したセッションにはリマインダーは送られない**（当日中の再実行は無い）
- 有効化のタイミングはオーナー判断です（migration では意図的に無効状態で登録しています）

### 呼び出し契約（body）

| body | 挙動 |
| --- | --- |
| 省略 / `{"dry_run": true}` | dry run（候補一覧のみ返し、送信しない）。`target_date` 省略時は JST の明日 |
| `{"dry_run": false, "target_date": "YYYY-MM-DD"}` | 本送信。**`target_date` は必須**（省略・不正な形式は 400 で拒否。候補 0 件でも 200） |

cron（`0 11 * * *` = JST 20:00）は実行時点の JST の明日を SQL で計算し、
`{"dry_run": false, "target_date": "<JST の明日>"}` を送る（`20260913000100`。関数側の既定日には依存しない）。
pg_net のタイムアウトは 60 秒に延長済み（候補ごとに OAuth + FCM + DB の往復があり、既定の 5 秒では切れる）。

### 有効化前の dry run（必須）

`send-session-reminders` は body の `dry_run` を**省略すると dry run**（候補一覧のみ返し、送信しない）。
初回から実顧客に push が飛ぶため、必ず候補を確認してから有効化すること。

```sql
select net.http_post(
  url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-session-reminders',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'secret_key')
  ),
  body := '{"dry_run": true}'::jsonb
);
-- 数秒後、上の戻り値の request_id で結果を確認
select status_code, timed_out, error_msg, content from net._http_response where id = <request_id>;
```

`status_code = 200`、`targetDate` が JST の翌日、`candidates` が翌日に予定されている scheduled / confirmed のセッションだけになっていれば OK です。
対象日を指定して確認したい場合は body に `"target_date": "YYYY-MM-DD"` を追加します。

候補の抽出だけなら SQL 関数を直接呼んでも確認できます（push は飛ばない。service_role / SQL Editor から実行）:

```sql
select * from public.find_sessions_for_reminder();              -- JST の明日
select * from public.find_sessions_for_reminder('2026-09-13');  -- 対象日を指定
```

### 手動で本送信する場合（通常は不要）

cron を待たずに送る、または cron 実行が失敗して送り直すときは、**`target_date` を必ず明示**します
（`dry_run: false` で `target_date` を省略すると関数が 400 で拒否する）。
同じ `target_date` で既に送信済み / skipped のセッションは dedup で送られない（`notification_logs` に行が残る）。

```sql
select net.http_post(
  url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-session-reminders',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'secret_key')
  ),
  body := jsonb_build_object('dry_run', false, 'target_date', '2026-09-14'),  -- 対象日を明示
  timeout_milliseconds := 60000
);
-- 数十秒後、上の戻り値の request_id で結果を確認（content の outcome に sent / partial / skipped / failed / duplicate の件数が入る）
select status_code, timed_out, error_msg, content from net._http_response where id = <request_id>;
```

### 有効化 SQL

```sql
select cron.alter_job((select jobid from cron.job where jobname='send-session-reminders'), active := true);
```

（再度無効化したい場合は `active := false` で同じ SQL を実行）

実行スケジュール: `0 11 * * *`（UTC 11:00 = **JST 毎日 20:00**）

---

## 4. 動作確認方法

### 登録済みジョブの一覧

```sql
select * from cron.job;
```

- `issue-recurring-tickets`（既存）/ `auto-skip-workouts` / `cleanup-ai-images`（2026-09-12 有効化済み）は active = true、
  `send-session-reminders` は有効化前は active = false、の計4本が見えること
- `cleanup-ai-images` の有効化・dry run も §2 と同じ要領（関数名を差し替える。こちらは body を省略すると dry run）

### 実行履歴の確認（有効化後）

```sql
select * from cron.job_run_details order by start_time desc limit 10;
```

- `status = 'succeeded'` であること。ただし pg_net 経由の HTTP POST（`auto-skip-workouts` / `cleanup-ai-images` /
  `send-session-reminders`）は**リクエストを enqueue した時点で succeeded** になる。関数側の 4xx / 5xx・
  タイムアウト・URL 解決失敗（Vault 未登録）はここには出ない
- HTTP の結果は `net._http_response` で確認する（`status_code` / `timed_out` / `error_msg` / `content`）:

```sql
select id, created, status_code, timed_out, error_msg, left(content, 300) as content
from net._http_response
order by created desc
limit 10;
```

  - `status_code = 200` かつ `timed_out = false` であること。`timed_out = true` は pg_net 側のタイムアウト
    （関数は走り続けるので送信自体は止まらないが、結果 JSON は取れない）。`error_msg` は接続・URL 解決の失敗
  - 保持期間は `pg_net.ttl`（既定 6 時間）のため、cron 実行（JST 20:00）から時間を置かずに確認すること
  - Dashboard → **Edge Functions → 該当関数 → Logs** も合わせて確認すること
- `send-session-reminders` の送信結果（送信 / skipped / failed とその理由）は
  `notification_logs`（`kind = 'session_reminder'`）の `status` / `detail` で確認する:

```sql
select created_at, user_id, status, detail, dedup_key
from public.notification_logs
where kind = 'session_reminder'
order by created_at desc
limit 20;
```

> 補足: `cron.job_run_details` の失敗を自動検知する監視ジョブは未実装
> （フェーズ7の通知ディスパッチャ完成後に配線予定。フェーズ5.3の残タスク）。
