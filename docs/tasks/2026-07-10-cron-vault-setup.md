# cron / Vault 初回セットアップ手順（ユーザー作業）

**作成日**: 2026-07-10
**対象**: プロジェクトオーナー（1回きりの手動作業）
**関連 migration**: `supabase/migrations/20260710020000_codify_cron_jobs.sql` / `20260829000300_cleanup_ai_images.sql` / `20260912000000_cron_use_secret_key.sql`

`auto-skip-workouts` / `cleanup-ai-images` の cron ジョブは migration で「無効(inactive)状態」で登録済みです。
実際に動かすには、以下の **(1) Vault シークレット登録** と **(2) ジョブの有効化** が必要です。
どちらも Supabase Dashboard の SQL Editor から実行します。

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

## 3. 動作確認方法

### 登録済みジョブの一覧

```sql
select * from cron.job;
```

- `issue-recurring-tickets`（active = true、既存）と
  `auto-skip-workouts` / `cleanup-ai-images`（有効化前は active = false）の3本が見えること
- `cleanup-ai-images` の有効化・dry run も同じ要領（関数名を差し替える。こちらは body を省略すると dry run）

### 実行履歴の確認（有効化後）

```sql
select * from cron.job_run_details order by start_time desc limit 10;
```

- `status = 'succeeded'` であること
- `auto-skip-workouts` は pg_net 経由の HTTP POST のため、cron 側が succeeded でも
  Edge Function 側の失敗はここに出ない。Dashboard → **Edge Functions → auto-skip-workouts → Logs**
  も合わせて確認すること

> 補足: `cron.job_run_details` の失敗を自動検知する監視ジョブは未実装
> （フェーズ7の通知ディスパッチャ完成後に配線予定。フェーズ5.3の残タスク）。
