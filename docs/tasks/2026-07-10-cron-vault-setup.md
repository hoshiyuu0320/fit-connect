# cron / Vault 初回セットアップ手順（ユーザー作業）

**作成日**: 2026-07-10
**対象**: プロジェクトオーナー（1回きりの手動作業）
**関連 migration**: `supabase/migrations/20260710020000_codify_cron_jobs.sql`

`auto-skip-workouts` の cron ジョブは migration で「無効(inactive)状態」で登録済みです。
実際に動かすには、以下の **(1) Vault シークレット登録** と **(2) ジョブの有効化** が必要です。
どちらも Supabase Dashboard の SQL Editor から実行します。

---

## 1. Vault シークレットの登録（2件）

Supabase Dashboard → 対象プロジェクト → **SQL Editor** で以下を実行します。

### 1-1. `project_url`

```sql
select vault.create_secret('https://viribpvnpgtgtmeulcmx.supabase.co', 'project_url');
```

### 1-2. `service_role_key`

Dashboard → **Settings → API** から **service_role** キーの値をコピーし、
`<service_roleキー>` 部分を置き換えて実行します。

```sql
select vault.create_secret('<service_roleキー>', 'service_role_key');
```

> ⚠️ **service_role キーは RLS を完全にバイパスする最高権限キーです。**
> - キーの値は **絶対にリポジトリ・チャット・ドキュメントに貼らない**こと
> - 上記 SQL は Dashboard の SQL Editor 上でのみ組み立てて実行すること
> - 実行後、SQL Editor の履歴に残したくない場合はクエリ履歴を削除すること

登録確認（値は表示されず、名前のみ確認）:

```sql
select name, created_at from vault.secrets order by created_at;
-- 'project_url' と 'service_role_key' の2行が出ればOK
```

---

## 2. `auto-skip-workouts` ジョブの有効化

### ⚠️ 有効化前に必ず確認

- 初回実行時、**現存25件（2026-07-10時点）の期限切れ pending 課題が一括で「スキップ」に変更されます**
- ワークアウト繰越の不具合（リスケ時にプランが消える問題、カタログ cat2 8-A / フェーズ8.1）の
  **修正後に有効化することを推奨**します
- 有効化のタイミングはユーザー判断です（migration では意図的に無効状態で登録しています）

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
  `auto-skip-workouts`（有効化前は active = false）の2本が見えること

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
