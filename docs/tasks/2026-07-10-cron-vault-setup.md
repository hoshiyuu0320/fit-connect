# cron / Vault 初回セットアップ手順（ユーザー作業）

**作成日**: 2026-07-10
**対象**: プロジェクトオーナー（1回きりの手動作業）
**関連 migration**: `supabase/migrations/20260710020000_codify_cron_jobs.sql` / `20260829000300_cleanup_ai_images.sql` / `20260912000000_cron_use_secret_key.sql` / `20260913000000_session_reminder.sql` / `20260913000100_session_reminder_cron_target_date.sql` / `20260914000000_client_alerts.sql` / `20260914000100_client_activity_snapshot.sql` / `20260914000200_client_alert_detection.sql` / `20260922000100_secure_parse_message_tags_webhook.sql`（messages トリガー。§冒頭の 2026-09-22 追加の注記）/ `20261004000000_client_alert_push.sql`（朝のまとめ通知。§6）

`auto-skip-workouts` / `cleanup-ai-images` / `send-session-reminders` / `notify-trainer-alerts`（§6）の cron ジョブは migration で「無効(inactive)状態」で登録されます。
実際に動かすには、以下の **(1) Vault シークレット登録** と **(2) ジョブの有効化** が必要です。
どちらも Supabase Dashboard の SQL Editor から実行します。

> `detect-client-alerts`（フェーズ9.1 の異常検知。06:00 JST）も inactive で登録されますが、Edge Function を呼ばず
> SQL 関数を直接実行するので **Vault は不要**です。有効化の手順は §5 にまとめています。

> **2026-09-12 時点の状態**: (1) Vault 登録は完了（`project_url` / `secret_key`）。
> `auto-skip-workouts` / `cleanup-ai-images` は本番 dry run 確認後に**有効化済み**（active = true）。
> 残るは **`send-session-reminders` のみ inactive**（§3 の手順で有効化する）。

> **2026-09-12 変更: 認証を新しい secret キー（`sb_secret_...`）の `apikey` ヘッダー方式に移行。**
> 旧 service_role キーを `Authorization: Bearer` で送る方式は、本番の関数側の値と一致せず 401 になっていた
> （旧キーは 2026 年末で廃止予定でもある）。cron は Vault の `secret_key` を `apikey` ヘッダーで送り、
> 関数は `supabase/functions/_shared/service_auth.ts` で `SUPABASE_SECRET_KEYS` と照合する（verify_jwt = false）。

> **2026-09-22 追加: メッセージのトリガーも同じ Vault の 2 件を使う。**
> `20260922000100_secure_parse_message_tags_webhook.sql` 以降、messages のトリガー関数 `call_parse_message_tags()` は
> 本番 URL の直書きをやめ、`project_url` + `/functions/v1/parse-message-tags` へ `secret_key` を `apikey` ヘッダーで送る。
> **どちらかが無いと送信せず WARNING（`PARSE_MESSAGE_TAGS_SKIPPED`）を出すだけ**なので、本番で `project_url` / `secret_key` を
> 削除・リネームすると、cron に加えて**メッセージのタグ解析・記録作成・メッセージ通知も黙って止まる**。
> secret キーをローテーションするときは、Vault の `secret_key` を先に新しい値へ更新してから古いキーを失効させる。
> ローカルスタックは Vault が空なので呼ばない（= Seed.sql 等のメッセージが本番へ送られない）。ローカルで動かす手順は §1-3。

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

### 1-3. ローカルスタックで parse-message-tags を動かす場合（任意・ローカル専用）

ローカルの Vault は空で、その状態ではメッセージを保存しても Edge Function は呼ばれない（WARNING のみ）。
ローカルでタグ → 記録作成まで通したいときだけ、**そのローカルスタックの DB に**次の 2 件を登録する
（2026-09-22 に隔離スタックで確認済み）。**本番の URL・キーは絶対に入れない**。

```sql
-- project_url: ローカルスタックの Docker ネットワーク内の API ゲートウェイ（kong）の別名。
--              project_id / ポートの設定によらず同じ値でよい
select vault.create_secret('http://kong:8000', 'project_url');
-- secret_key: `supabase status` の Secret（sb_secret_...。ローカル既定のキー）
select vault.create_secret('<supabase status の Secret>', 'secret_key');
```

- ローカルの CLI（v2.75）は edge runtime に `SUPABASE_SECRET_KEYS` を渡さない。代わりにローカルの kong が
  `apikey: <ローカルの sb_secret>` を `Authorization: Bearer <ローカルの service_role JWT>` に書き換えるので、
  `_shared/service_auth.ts` の互換経路（旧 Bearer service_role）で通る。互換経路を削除したら（旧キー廃止の 2026 年末予定）
  この手順も見直す
- 戻すときは `delete from vault.secrets where name in ('project_url', 'secret_key');`（ローカルの DB でのみ）

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

- `issue-recurring-tickets`（既存）/ `auto-skip-workouts` / `cleanup-ai-images`（2026-09-12 有効化済み）/
  `send-session-reminders`（2026-09-13 有効化済み）の計4本が active = true で見えること
- `detect-client-alerts`（フェーズ9.1）は §5 の手順で有効化するまで active = false（2026-09-22 に有効化済み）
- `notify-trainer-alerts`（フェーズ9.1 拡張 push）は §6 の手順で有効化するまで active = false（2026-10-12 に有効化済み。2026-10-18 に初めての朝のまとめの到達を確認）
- `cleanup-ai-images` の有効化・dry run も §2 と同じ要領（関数名を差し替える。こちらは body を省略すると dry run）

### 実行履歴の確認（有効化後）

```sql
select * from cron.job_run_details order by start_time desc limit 10;
```

- `status = 'succeeded'` であること。ただし pg_net 経由の HTTP POST（`auto-skip-workouts` / `cleanup-ai-images` /
  `send-session-reminders` / `notify-trainer-alerts`）は**リクエストを enqueue した時点で succeeded** になる。関数側の 4xx / 5xx・
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
  - HTTP の4ジョブとも pg_net のタイムアウトは60秒（`auto-skip-workouts` / `cleanup-ai-images` は migration
    `20260913000200` で既定5秒から延長。関数内の一時障害の再試行を含めて応答を待てるようにするため。
    `notify-trainer-alerts` は登録時から60秒）。SQL エディタから手で `net.http_post` を送るときも
    `timeout_milliseconds := 60000` を付ける（付けないと既定の5秒で `timed_out = true` になり、結果が取れない）
  - 保持期間は `pg_net.ttl`（既定 6 時間）のため、cron 実行（JST 20:00）から時間を置かずに確認すること
  - Dashboard → **Edge Functions → 該当関数 → Logs** も合わせて確認すること。6時間を過ぎて `net._http_response`
    が消えた後は、このログ（`POST | 500 | …/functions/v1/<関数名>` のような行）が唯一の手掛かりになる
  - 一番確実なのは**副作用を SQL で数える**こと（例: `cleanup-ai-images` なら
    `select count(*) from public.find_orphan_ai_images();` が実行後に0件になっているか）。
    2026-09-13 の初回実行では、cron は succeeded なのに関数は RPC の一時的な 504 で500終了しており、
    これで発見した（lessons.md 参照）
- `send-session-reminders` の送信結果（送信 / skipped / failed とその理由）は
  `notification_logs`（`kind = 'session_reminder'`）の `status` / `detail` で確認する。
  `status = 'failed'` かつ `detail = 'resolve_error'` は「宛先（端末）を読み取れず何も送っていない」行で、
  §3 の手動本送信を同じ `target_date` で再実行すると送り直される（送信済み・skipped の行は再実行しても送られない）:

```sql
select created_at, user_id, status, detail, dedup_key
from public.notification_logs
where kind = 'session_reminder'
order by created_at desc
limit 20;
```

> 補足: `cron.job_run_details` の失敗を自動検知する監視ジョブは未実装
> （フェーズ5.3の残タスク・判断7-3。朝のまとめ通知（§6）の直後の PR で作る。オーナー決定 2026-10-04）。

---

## 5. `detect-client-alerts`（異常検知）の有効化

**関連 migration**: `20260914000000_client_alerts.sql`（alerts / alert_detection_runs）/
`20260914000100_client_activity_snapshot.sql`（活動の定義）/ `20260914000200_client_alert_detection.sql`（評価・本実行・検知状態・cron）/
`20261003000000_alert_sleep_decline.sql`（睡眠の悪化を追加。§5-10。設計: `docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md`）
**仕様**: `docs/tasks/2026-09-13-trainer-intervention-plan.md`

毎日 06:00 JST（`0 21 * * *` = UTC 21:00）に、担当顧客の「体重の急な変化（weight_change）」「記録途絶（record_gap）」
「睡眠の悪化（sleep_decline、2026-10-03 追加）」を判定して `public.alerts` に残すジョブです。Web のダッシュボード「今日の対応」とサイドバーのバッジがこの表を読みます。
このジョブ自体は push 通知を送りません。新しく出たアラートのトレーナー向けの通知（朝のまとめ1通）は、
10分後の別のジョブ `notify-trainer-alerts`（06:10 JST）が送ります（§6。2026-10-04 設計・2026-10-12 実装）。

### 他のジョブとの違い

- **Vault・pg_net・apikey・タイムアウトの設定は不要**。cron の command は SQL 関数を直接呼ぶだけ:
  `SELECT public.run_client_alert_detection((now() AT TIME ZONE 'Asia/Tokyo')::date);`
  （`issue-recurring-tickets` と同じ形）
- 例外はそのまま **`cron.job_run_details` に `failed` として残る**。HTTP 経由のジョブのように
  「succeeded なのに中身は失敗」は起きない（§4 の `net._http_response` を見る必要も無い）
- 関数は3つに分かれている:

| 関数 | 書き込み | 用途 |
| --- | --- | --- |
| `public.evaluate_client_alerts(対象日, 締め時刻)` | しない（STABLE） | **dry run とバックテスト**。MCP の読み取りでも実行できる |
| `public.run_client_alert_detection(対象日)` | する | **本実行**（cron が呼ぶ）。対象日は必須。dry_run フラグは無く、呼んだら本実行 |
| `public.get_alert_detection_status()` | しない | Web が呼ぶ検知状態（ログイン中のトレーナー用） |

- 本実行のガード（例外になるのはこの3つだけ）: 対象日が NULL / JST の今日より未来 /
  **最後に成功した本実行の対象日より前**。同じ対象日の再実行は許す（同じ状態に収束する）
- 成功した本実行ごとに `public.alert_detection_runs` に1行（stats は件数だけ）。失敗はトランザクションごと巻き戻る

### 5-0. 前提（db push の前に確認）

- `supabase db push` は**未適用の migration をすべて**流す。フェーズ8.4 の `20260913000400`（新しい Mobile ビルドを
  確認してから当てる約束のもの）が残っていると一緒に当たってしまうので、先にリモートの適用状況を確認する:

```sql
select version from supabase_migrations.schema_migrations order by version desc limit 5;
-- 20260913000400 が入っていることを確かめてから、ルートで supabase db push（オーナーの確認後）
```

- db push の後、Dashboard → **Advisors → Security** で、新しい4関数（`client_activity_snapshot` /
  `evaluate_client_alerts` / `run_client_alert_detection` / `get_alert_detection_status`）に
  `function_search_path_mutable` などが出ていないことを確かめる
  （`get_alert_detection_status` の `authenticated_security_definer_function_executable`（WARN）は意図どおり。
  返すのは呼び出したトレーナー本人の担当顧客の人数だけ）

### 5-1. dry run（書き込まない）

`evaluate_client_alerts` は書き込めない関数なので、何度流しても状態は変わりません。
対象日と締め時刻を省略すると「JST の今日・今の時刻まで」で評価します。まず件数だけを見る:

```sql
-- 監視対象の顧客について、種別・判定・変種・重要度ごとの件数
select alert_type, state, payload->>'variant' as variant, severity, count(*)
from public.evaluate_client_alerts()
group by 1, 2, 3, 4
order by 1, 2, 3, 4;

-- 監視対象と対象外の人数（全トレーナー合算。自己登録 self は Web の人数には出ない）
select coalesce(exclusion_reason, '(監視対象)') as reason, count(*)
from public.client_activity_snapshot((now() at time zone 'Asia/Tokyo')::date, now())
group by 1
order by 1;
```

- 顧客ごとの中身を確かめたいときは、SQL Editor で `select * from public.evaluate_client_alerts() where state = 'detected';`
  を流す（payload に比較期間・途絶の期間が入る。表示用の文字列は無い）。
  **AI（MCP）経由で確かめるときは件数だけを取り、client_id や体重の値を出力しない**
- 過去の朝の状態を再現したいときは、対象日と締め時刻を渡す（締め時刻は「対象日の JST 0:00 以降、かつ今」の範囲）:
  `select ... from public.evaluate_client_alerts('2026-09-20', '2026-09-20 06:00+09');`

### 5-2. 30日バックテスト

有効化の判断基準は「**1日あたりの新規件数**」。過去30日の各日 d について `evaluate_client_alerts(d, d の 06:00 JST)` を流し、
**前日に detected でなかった（顧客, 種別）が detected になった件数**を1日ごとに数える
（続いている発生を毎日数えると、新規件数と比べられない）。

```sql
with days as (
  -- 30日分の新規を数えるため、比較用に1日前（31日前）から評価する
  select d::date as d
  from generate_series((now() at time zone 'Asia/Tokyo')::date - 31,
                       (now() at time zone 'Asia/Tokyo')::date - 1,
                       interval '1 day') as d
),
ev as (
  select days.d, e.client_id, e.alert_type, e.state, e.payload->>'variant' as variant
  from days
  cross join lateral public.evaluate_client_alerts(
    days.d, (days.d::timestamp + interval '6 hours') at time zone 'Asia/Tokyo') as e
)
select days.d as target_date,
       count(*) filter (where cur.state = 'detected' and prev.state is distinct from 'detected') as new_total,
       count(*) filter (where cur.state = 'detected' and prev.state is distinct from 'detected'
                          and cur.alert_type = 'weight_change')                              as new_weight_change,
       count(*) filter (where cur.state = 'detected' and prev.state is distinct from 'detected'
                          and cur.alert_type = 'record_gap')                                 as new_record_gap,
       count(*) filter (where cur.state = 'detected' and prev.state is distinct from 'detected'
                          and cur.alert_type = 'sleep_decline')                              as new_sleep_decline,
       count(*) filter (where cur.state = 'detected')                                        as detected_total
from days
left join ev as cur on cur.d = days.d
left join ev as prev
  on prev.client_id = cur.client_id and prev.alert_type = cur.alert_type and prev.d = cur.d - 1
where days.d >= (now() at time zone 'Asia/Tokyo')::date - 30
group by days.d
order by days.d;
```

- evaluate は alerts を見ない（監視対象は登録日・記録・メッセージだけで決まる）ので、本実行の前後どちらで取っても同じ結果になる。
  生きている record_gap があっても監視は延ばさず、顧客が「記録開始前（登録から14日超）」「2週間以上データなし」になった時点で
  本実行が resolved（expired）で閉じる（オーナー決定 2026-09-13 (1)）
- 睡眠の `updated_at` は後の同期で上書きされるため、過去の到着の痕跡が一部失われる →
  バックテストは「記録・同期なし（no_data）」を**多めに数える方向**にずれる（安全側）
- 体重は成立値と解消値の間（unknown）の日を挟むと、翌日にもう一度「新規」に数えられることがある（ヒステリシスの分）
- 睡眠の悪化も同じで、保留の日や、到着遅れで直近の窓が4晩に満たない日（不足 = unknown）を挟むと、翌日にもう一度「新規」に数えられる。
  睡眠は到着遅れが大きい（中央値 約35時間）ので、weight_change より**多めに出る方向**にずれる
- 見込み（計画時点のデータ）: 有効化の初回は 0〜1件、その後は1トレーナーあたり1日 0.03〜0.05件

### 5-3. 有効化直前の dry run の取り直し

監視対象が少ない（計画時点で1名）ので、有効化する直前にもう一度 §5-1 の件数を取り、見込みと大きく違わないことを確かめる。
特に「記録・同期なし（no_data）」が大量に出ていたら、直前に weight / sleep を一括 UPDATE する作業が無かったか確認する（§5-8）。

### 5-4. 初回の手動実行

cron を有効にする前に、SQL Editor（postgres）で本実行を1回だけ手で流し、戻り値と記録を確かめる:

```sql
select public.run_client_alert_detection((now() at time zone 'Asia/Tokyo')::date);
-- 戻り値: {"target_date": ..., "as_of": ..., "stats": {"opened": n, "monitored": n, "excluded": {...}, ...}}

select target_date, as_of, finished_at - started_at as duration, stats
from public.alert_detection_runs
order by finished_at desc
limit 1;
```

- 今日を対象日にすると締め時刻は「今」。同じ日のうちにもう一度流しても同じ状態に収束する（新規 0）
- **一度流すと、それより前の対象日では本実行できなくなる**（ガード）。過去の日を見たいときは evaluate を使う

### 5-5. 有効化と停止

```sql
-- 有効化（翌朝 06:00 JST から毎日）
select cron.alter_job((select jobid from cron.job where jobname = 'detect-client-alerts'), active := true);

-- 停止（データは残る。ダッシュボードは「停止中」を出す）
select cron.alter_job((select jobid from cron.job where jobname = 'detect-client-alerts'), active := false);
```

実行スケジュール: `0 21 * * *`（UTC 21:00 = **JST 毎日 06:00**）。回数を増やすときも `cron.alter_job` の schedule だけで足りる
（同じ対象日の再実行は冪等）。

### 5-6. 翌朝の確認 SQL（有効化の翌朝と、以後は週1回）

cron 失敗の自動監視ジョブは作っていない（当初は「トレーナー向け push の配線と一緒に作る」（オーナー決定 2026-09-13）だったが、
2026-10-04 のオーナー決定で、朝のまとめ通知（§6）の PR には含めず直後の PR で作ることにした）。
それまでは、ダッシュボードの検知状態表示と、下の SQL を**週1回**流すことで代える。

```sql
-- 直近7日の cron 実行（failed なら return_message に例外の内容が出る）
select jr.start_time at time zone 'Asia/Tokyo' as started_jst, jr.status, left(jr.return_message, 200) as message
from cron.job_run_details jr
join cron.job j on j.jobid = jr.jobid
where j.jobname = 'detect-client-alerts'
  and jr.start_time > now() - interval '7 days'
order by jr.start_time desc;

-- 直近7日の本実行の記録（1日1行・対象日が毎日進んでいること）
select target_date, as_of, finished_at - started_at as duration, stats
from public.alert_detection_runs
where finished_at > now() - interval '7 days'
order by finished_at desc;

-- alerts の件数（状態・種別・重要度ごと）
select status, alert_type, severity, count(*)
from public.alerts
group by 1, 2, 3
order by 1, 2, 3;
```

- `job_run_details` が `succeeded` で、`alert_detection_runs` にその日の行があれば正常
- `job_run_details` が `failed` なら、例外で**トランザクションごと巻き戻っている**（その日の alerts は変わっていない）。
  原因を直したら §5-4 の手動実行で同じ日を流し直せる
- Web は最終チェックが30時間より前なら「遅延」、ジョブが inactive なら「停止中」を出す

### 5-7. ロールバック

- **止めるだけ**: §5-5 の停止 SQL。データは残り、ダッシュボードは「停止中」を出す
- **撤去する**（順番を守る）:
  1. **Web を先に revert して本番に出す**（`getInactiveClients.ts` と旧表示も戻る）。
     Web を先に戻さないと、DB を落とした時点で「今日の対応」が取得失敗になる
  2. 新しい migration で次を実行する（**適用済みの migration ファイルは消さない**）:

```sql
select cron.unschedule('detect-client-alerts');
drop function if exists public.get_alert_detection_status();
drop function if exists public.run_client_alert_detection(date);
drop function if exists public.evaluate_client_alerts(date, timestamptz);
drop function if exists public.client_activity_snapshot(date, timestamptz, uuid);
drop table if exists public.alert_detection_runs;
drop table if exists public.alerts;  -- 対応済みの履歴もここで消える
```

  - alerts を消すと、トレーナーが「対応済み」にした履歴も消える（戻せない）

### 5-8. 注意: weight / sleep を一括 UPDATE する migration

「最終到着日」には `weight_records.updated_at` と `sleep_records.updated_at` を使っている（どちらも `set_updated_at`
トリガーで UPDATE のたびに now() になる。睡眠は Mobile の同期が毎回約30行を upsert するので、同期の痕跡として使える）。
そのため、**weight / sleep を一括 UPDATE する migration やデータ修正を流すと、全員が「今日同期した」ように見え**、
休眠中の顧客が監視対象に戻って「記録なし（no_record）」が大量に出る。流すときは次のどちらかにする:

- migration の中でトリガーを一時的に止める:

```sql
alter table public.sleep_records disable trigger set_updated_at;
-- ... 一括 UPDATE ...
alter table public.sleep_records enable trigger set_updated_at;
-- weight_records も同じ（トリガー名はどちらも set_updated_at）
```

- もしくは、前後で検知を止める（§5-5 の停止 → 作業 → §5-1 の dry run で件数を確かめる → 有効化）

### 5-9. ローカルで QA 用データを入れる（ローカル専用。リモートでは流さない）

Web の「今日の対応」を確かめるための手順。ローカル DB は他の worktree と共有しているので、終わったら片付ける。
seed の顧客（佐藤花子 `22222222-…`）に「登録から十分たってから 7日で +3% 以上増えた体重」を入れ、
別に QA 用の顧客を2人（記録・同期なし / 記録開始前）作ってから、今日の対象日で本実行する:

```sql
-- ローカル専用: docker exec -i supabase_db_fit-connect psql -U postgres -d postgres で流す
begin;

-- 1) seed の顧客: 登録日を40日前にし、前の窓（8〜14日前）60.0kg・直近の窓（1〜7日前）62.0kg の体重を入れる
--    （seed の体重が窓に入ると平均が動くので、直近15日分の seed の体重は先に消す）
update public.clients set created_at = now() - interval '40 days'
 where client_id = '22222222-2222-2222-2222-222222222222';
delete from public.weight_records
 where client_id = '22222222-2222-2222-2222-222222222222' and recorded_at > now() - interval '15 days';
insert into public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at)
select '22222222-2222-2222-2222-222222222222',
       case when g >= 8 then 60.0 else 62.0 end,
       now() - (g || ' days')::interval, 'manual',
       now() - (g || ' days')::interval, now() - (g || ' days')::interval
from generate_series(1, 13, 2) as g;  -- 1, 3, 5, 7（直近）/ 9, 11, 13（前）

-- 2) QA 用の顧客（ログインできる扱いにするため auth.users にも行を作る）
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
                        confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('99999999-0914-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'qa-alert-nodata@example.com', 'x', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('99999999-0914-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'qa-alert-notstarted@example.com', 'x', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');
insert into public.clients (client_id, name, trainer_id, created_at) values
  ('99999999-0914-0000-0000-000000000001', 'QA 記録・同期なし', '11111111-1111-1111-1111-111111111111', now() - interval '30 days'),
  ('99999999-0914-0000-0000-000000000002', 'QA 記録開始前',     '11111111-1111-1111-1111-111111111111', now() - interval '5 days');
-- 「記録・同期なし」: 最後に届いたのが10日前の体重だけ（→ no_data 9日・要確認）。
-- updated_at も到着の痕跡なので、省略して now() にしないこと（省略すると「今日同期した」扱いになる）
insert into public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at)
values ('99999999-0914-0000-0000-000000000001', 70.0, now() - interval '10 days', 'manual',
        now() - interval '10 days', now() - interval '10 days');
-- 「記録開始前」: 5日前に登録して何もしていない（→ not_started 5日・注意）

-- 3) 本実行（ローカルで何度もやり直すときは、先に alert_detection_runs を空にする。対象日のガードのため）
delete from public.alert_detection_runs;
select public.run_client_alert_detection((now() at time zone 'Asia/Tokyo')::date);

commit;
```

- 片付け: `delete from public.clients where client_id::text like '99999999-0914-%';`
  `delete from auth.users where id::text like '99999999-0914-%';`（seed の顧客の体重・登録日は `supabase db reset` で戻る。
  reset はスタックを共有している他のセッションと調整してから）
- seed のトレーナーが free プラン（トライアル切れ）だと顧客は3人まで。seed の顧客と QA 用の2人でちょうど3人になる

### 5-10. 睡眠の悪化（sleep_decline）の追加（2026-10-03、migration `20261003000000`）

cron はすでに有効なので、**push した翌朝 06:00 から新しいルールが動く**。判定の仕様は
`docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md` §4（直近7日と前の7日の睡眠時間の中央値を比べて1時間以上短い、
または直近の目覚め評価の平均が1.5未満。重大度は medium）。

1. push の前に `supabase migration list --linked` と `supabase db push --dry-run` で、未適用が `20261003000000` の1本だけであることを確かめる。
   06:00 JST の直前は避ける（適用後の確認の時間を取るため）
2. `supabase db push`。先頭のドリフトガード（`REMOTE_DRIFT_SINCE_CAPTURE`）か末尾の検査（`ALERT_FUNCTION_POSTCHECK_FAILED`）で止まったら、
   トランザクションごと巻き戻っている。リモートの関数の差分を調べてから migration を直す
3. 適用後すぐに確認する（**件数だけ**。AI（MCP）経由でも client_id や睡眠の値は出力しない）:

```sql
-- CHECK に sleep_decline が入った
select pg_get_constraintdef(oid) from pg_constraint where conname = 'alerts_alert_type_check';

-- 両関数の search_path と EXECUTE（service_role だけ true）
select p.proname, p.proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE')          as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated,
       has_function_privilege('service_role', p.oid, 'EXECUTE')  as service_role
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('evaluate_client_alerts', 'run_client_alert_detection');

-- dry run: 睡眠の悪化の判定ごとの件数
select state, count(*) from public.evaluate_client_alerts()
where alert_type = 'sleep_decline' group by 1 order by 1;
```

   続けて §5-2 のバックテストを流し、`new_sleep_decline` の1日あたりの件数を見る
4. 想定外の件数が出たら、06:00 より前に §5-5 の停止 SQL で cron を止める（体重・途絶の検知も止まるので、原因を直したらすぐ戻す）。
   想定外の目安: 監視対象は今1名で、睡眠悪化の検知はほぼ0件の見込み（設計 §2）。監視対象の人数を超える detected や、毎日の新規が続く場合は想定外とみなす。
   §5-2 の見込み（1トレーナーあたり1日 0.03〜0.05件）は体重と途絶だけを数えた値なので、睡眠悪化の目安には使わない
5. 翌朝、§5-6 の確認 SQL の runs の stats に `detected.sleep_decline` が入っていることを確かめる
6. ロールバック（必要なときだけ。新しい migration で、この順番で）:
   1. `delete from public.alerts where alert_type = 'sleep_decline';`（resolved の行も含めて全部。CHECK を ADD するときに全行が検証されるため、resolved にするだけでは戻せない）
   2. 両関数を `20260914000200` の定義に戻す。ドリフトガードの期待値は `evaluate_client_alerts` = `f9da5a2ab0ed75c6e3eb6cede096f41b`、
      `run_client_alert_detection` = `8204524cb8882d68e7314d318e9af9cd`（`md5(prosrc)`。2026-10-03 の実装の値）
   3. CHECK を `('weight_change', 'record_gap')` に戻す
   4. COMMENT を元の文面に戻す（`CREATE OR REPLACE FUNCTION` では COMMENT は戻らない。`md5(prosrc)` には影響しない）:
      - `public.alerts` の列 COMMENT 5つ（`alert_type` / `severity` / `payload` / `last_detected_on` / `resolved_reason`）を、
        `20260914000000_client_alerts.sql` の `COMMENT ON COLUMN public.alerts.…`（96〜127行）の文面に戻す
      - 関数の COMMENT 2つ（`evaluate_client_alerts` / `run_client_alert_detection`）を、
        `20260914000200_client_alert_detection.sql` の `COMMENT ON FUNCTION`（288行・601行）の文面に戻す

---

## 6. `notify-trainer-alerts`（トレーナー向けアラートの朝のまとめ通知）の有効化

**関連 migration**: `20261004000000_client_alert_push.sql`（通知種別 `client_alert` の CHECK・cron の登録（無効））
**関数**: `supabase/functions/notify-trainer-alerts/index.ts`（`config.toml` で verify_jwt = false）
**設計**: `docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md`（リリースの順序は §11.2、運用は §11.3）

> **2026-10-18 時点の状態**: 2026-10-12 に有効化済み（Claude が `active = true`・`10 21 * * *` を確認）。2026-10-18 06:10 に初めての朝のまとめが `sent=1/1` でオーナーの Chrome に届いた。
> §6-0 の 5（Web を main へリリース）は未実施で、Web は develop の Preview で確認した。§6-3 の本送信は、本番に未対応のアラートが 0 件で対象日が無かったため飛ばした。記録は `docs/tasks/IMPLEMENTATION_TASKS.md` の 9.1 の PR2 の項目

毎日 06:10 JST（`10 21 * * *` = UTC 21:10）に Edge Function を呼び、06:00 の自動チェック（§5）で**その日に新しく出た**アラート
（`status = 'open'` かつ `surfaced_on = 対象日 D`）があるトレーナーへ、ブラウザ通知（Web Push）を1通ずつ送るジョブです。

- D の自動チェックが成功していない（`alert_detection_runs` に `target_date = D` の行が無い）日は1通も送らず、`detectionReady: false` を返す
- 文面はタイトル `今日の対応があります`、本文 `新しく要確認 1名・注意 2名` のような重大度別の人数だけ（顧客名・数値は入れない）。
  クリックで `/dashboard` を開く。有効期限（TTL）は12時間
- 人数は顧客ごとの一番重い重大度で数える。今朝新しく出たアラートだけで決めるので、一覧の行のバッジ（全 open の最重大）とは違うことがある
- 冪等化は `notification_logs.dedup_key` = `client_alert_digest:<trainer_id>:<D>`。同じ D で何度呼んでも1トレーナーに1通（cron の再実行・手動実行を含む）。
  **結果が何であれ（skipped・failed・pending も）その日のキーは使い切る**。同じ D の再実行で送り直されるのは `failed` / `resolve_error` の行だけ（送り直しは §6-6）
- 宛先はトレーナーの `device_tokens`（`platform = 'web_push'`・`user_type = 'trainer'`）だけ。ブラウザ通知を登録していないトレーナーは `skipped` / `no_tokens`、
  通知設定の「アラート（朝のまとめ）」をオフにしたトレーナーは `skipped` / `disabled`

### 他のジョブとの違い

- `send-session-reminders` と同じく Vault の `project_url` / `secret_key` で関数を呼ぶ（url の組み立て・headers・
  `timeout_milliseconds := 60000` は同一）。違うのは body だけ:
  body は `{"dry_run": false, "target_date": "<JST の今日>"}`（**`+ 1` しない**。21:10 UTC は JST の翌日 06:10 なので、
  `(now() AT TIME ZONE 'Asia/Tokyo')::date` がその日の D）
- 検知（§5）は SQL だけで完結し、失敗は `cron.job_run_details` に残る。こちらは HTTP 経由なので、関数側の失敗は
  `net._http_response` と関数の Logs にしか残らない（§4）

### 呼び出し契約（body）

| body | 挙動 |
| --- | --- |
| 省略 / `{"dry_run": true}` | dry run（人数を返すだけで送らない）。`target_date` 省略時は JST の今日 |
| `{"dry_run": false, "target_date": "YYYY-MM-DD"}` | 本送信。**`target_date` は必須**（省略・実在しない日付は 400） |
| `"trainer_id": "<uuid>"`（任意。上のどちらにも足せる） | そのトレーナー1人だけを対象にする（本番での確認・送り直し用。cron は付けない）。UUID でなければ 400 |

- 送る側に倒れるのは真偽値の `false` だけ。`"false"`（文字列）・`0`・`null`、JSON でない body は dry run
- `target_date` が JST の今日より後なら 400。過去の日付は受け付ける（手動の確認・送り直し用。dedup キーで二重送信は防がれる）
- 返り値: `{ status, dryRun, targetDate, trainerId, detectionReady, trainerCount, alreadyLogged, digests: [{ trainer_id, high, medium, low }], outcome? }`。顧客の ID・名前は返さない
  - `alreadyLogged`: 対象の dedup キーで既に `notification_logs` に行がある人数（本送信が重複になるかを事前に知るため。読めなければ `null`）
  - `outcome`（本送信だけ）: `sent` / `partial` / `skipped` / `failed` / `pending` / `duplicate`（送る前から行があって送らなかった数）/
    `missing`（送ったのにログの行が無い数）/ `skippedBy`（`no_tokens` / `disabled` / `quiet_hours` / `vapid` / `other`）。`skippedBy` 以外の合計が `trainerCount` になる

### 6-0. 前提とリリースの順序（設計書 §11.2）

1. PR1（Web Push の土台、#97）のリリースが済んでいること: VAPID の鍵の作り直し → `parse-message-tags` / `send-session-reminders` の再デプロイ →
   Web のリリース → `docs/tasks/2026-07-19-webpush-vapid-setup.md` の手順0（Vercel の公開鍵と Edge Functions の鍵が対か）
2. PR2 を develop へマージ → develop から `supabase migration list --linked` と `supabase db push --dry-run` で未適用が `20261004000000` の1本だけであることを確かめ、
   `supabase db push`。末尾の検査（`CLIENT_ALERT_PUSH_POSTCHECK_FAILED`）で止まったら、トランザクションごと巻き戻っている
3. `supabase functions deploy notify-trainer-alerts` だけ（`parse-message-tags` / `send-session-reminders` の再デプロイは要らない）。
   deploy の後に `supabase functions list` で更新時刻を確かめる
   - CLI が `unexpected login role status 403 … database_write` で止まるときは、そのターミナルの `SUPABASE_ACCESS_TOKEN`（MCP 用の読み取り専用トークン）が原因。`unset SUPABASE_ACCESS_TOKEN` してから実行する
4. §6-1 の dry run
5. Web（sw.js・通知設定・「今朝」の目印）を main へリリース。デプロイ前から開いていたタブは一度リロードする（古いバンドルのままだと、通知のクリックで取り直さない）。
   ブラウザ通知を使うトレーナーには、設定画面でプッシュ通知をオンにしてもらう
6. §6-3 の1人に絞った本送信
7. §6-4 で cron を有効化 → 翌朝 §6-5 の確認

5 より前は本番の sw.js が古いままで、通知のクリック先が `/message` になる。本送信と有効化は 5 の後にする。

### 6-1. dry run（送らない）

SQL エディタから pg_net で呼ぶ。**`timeout_milliseconds := 60000` を必ず付ける**（既定の5秒では、DB の読み取りの再試行が1回あるだけで超え、
`timed_out = true` で結果が取れない）。

```sql
select net.http_post(
  url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notify-trainer-alerts',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'secret_key')
  ),
  body := '{"dry_run": true}'::jsonb,  -- 対象日を指定するときは jsonb_build_object('dry_run', true, 'target_date', '<D>')
  timeout_milliseconds := 60000
);
-- 数秒後、上の戻り値の request_id で結果を確認
select status_code, timed_out, error_msg, content from net._http_response where id = <request_id>;
```

- `status_code = 200`・`timed_out = false` で、`content` の `dryRun` が `true`、`detectionReady` が `true`、`digests` の人数が §6-2 の SQL と一致すれば OK
- 対象日を省略すると JST の今日。06:00 の自動チェックより前に流すと、今日の検知がまだ無いので `detectionReady: false`（送るものが無いだけで正常）
- `status_code` が 401 なら apikey の不一致か verify_jwt（`config.toml` の `[functions.notify-trainer-alerts]` を確かめて deploy し直す）、404 なら関数が未デプロイ
- あわせて読み取りで確かめる:

```sql
-- 旧 trainers.fcm_token が残っているトレーナー（web_push が無いと FCM に落ち、FCM→APNs は不達で failed になる。設計書 §9）
select count(*) from public.trainers where fcm_token is not null;

-- ブラウザ通知を登録しているトレーナー（宛先になる人）
select user_id, count(*) as browsers, max(last_seen_at) as last_seen_at
from public.device_tokens
where platform = 'web_push' and user_type = 'trainer'
group by user_id;
```

### 6-2. 人数の突き合わせ（読み取り）

D に新しく出たアラートがある担当顧客の一番重い重大度を、トレーナー別に数える。dry run の `digests` の `high` / `medium` / `low` と一致すること。
§6-3 では、ここで対象のアラートの `trainer_id` も確かめる。

```sql
with top as (
  select a.trainer_id, a.client_id,
         max(case a.severity when 'high' then 3 when 'medium' then 2 else 1 end) as sev_rank
  from public.alerts a
  join public.clients c on c.client_id = a.client_id and c.trainer_id = a.trainer_id
  where a.status = 'open' and a.surfaced_on = date '<D>'
  group by a.trainer_id, a.client_id
)
select trainer_id,
       count(*) filter (where sev_rank = 3) as high,
       count(*) filter (where sev_rank = 2) as medium,
       count(*) filter (where sev_rank = 1) as low
from top
group by trainer_id
order by trainer_id;
```

### 6-3. 1人に絞った本送信（有効化の前に1回だけ）

本番で実際に届くことを、ブラウザを登録したトレーナー1人だけで確かめる。**`trainer_id` を必ず付ける**
（付けないと、その D に新しいアラートがある全トレーナーに古い日付のまとめが飛び、その人たちの D のキーも使い切る）。

1. 対象日 D を決める（`status = 'open'` のアラートがある `surfaced_on` の日。§6-2 の SQL で探す）。
   設計書 §11.2 の予備の `2026-10-01` は、その日のアラートが対応済み（resolved）になっていて使えない
   （2026-10-12 の読み取りで open のアラートは0件）。open のアラートが無いときは手順5のとおり本送信をしない
2. §6-2 の SQL で、D のアラートの `trainer_id` に、ブラウザを登録したトレーナー（§6-1 の `device_tokens` の SQL）が入っていることを確かめる。
   同じブラウザで複数のトレーナーを切り替えて試したときは、最後に登録したトレーナーが宛先になる
3. `jsonb_build_object('dry_run', true, 'target_date', '<D>', 'trainer_id', '<そのトレーナー>')` で dry run し、`digests` にそのトレーナーが入っていて、`alreadyLogged` が 0 であること
4. 受け取るブラウザで新しい sw.js が有効なこと（DevTools → Application → Service Workers で `SW_VERSION` が `2026-10-04.client-alert-1`）。旧版のままだと、通知は出てもクリック先が `/message` になる
5. **一致するトレーナーが `digests` に入らない場合は本送信をしない**。§6-4 の有効化まで進め、最初の自然なアラートの日に §6-5 で確かめる
6. 本送信:

```sql
select net.http_post(
  url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notify-trainer-alerts',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'secret_key')
  ),
  body := jsonb_build_object('dry_run', false, 'target_date', '<D>', 'trainer_id', '<trainer_id>'),  -- trainer_id を必ず付ける
  timeout_milliseconds := 60000
);
select status_code, timed_out, error_msg, content from net._http_response where id = <request_id>;
```

- ブラウザに届く・クリックでダッシュボードが開く（ダッシュボードのタブが開いていればそれが前面に出て、「今日の対応」とバッジが取り直される）・
  `outcome.sent` が 1・`notification_logs` が `sent`
- これで D のそのトレーナーの dedup キーを使い切る。`failed` / `skipped` / `pending` で、鍵や設定を直してからやり直すときは §6-6 の DELETE をしてから同じ D で再実行する
- `outcome.skippedBy` で原因を見分ける: `vapid` は Edge Functions の VAPID の secrets が未設定、`no_tokens` はブラウザ通知が未登録、`disabled` は通知設定でオフ、`quiet_hours` は静かな時間帯
- `failed` のときは Edge Functions → `notify-trainer-alerts` → Logs の `[WebPush] Error sending notification` の `statusCode` を見る（403 なら鍵の不一致。PR1 の手順0 をやり直す）

### 6-4. 有効化と停止

```sql
-- 有効化（翌朝 06:10 JST から毎日）
select cron.alter_job((select jobid from cron.job where jobname = 'notify-trainer-alerts'), active := true);

-- 停止（通知だけ止まる。検知と「今日の対応」の表示は続く）
select cron.alter_job((select jobid from cron.job where jobname = 'notify-trainer-alerts'), active := false);
```

実行スケジュール: `10 21 * * *`（UTC 21:10 = **JST 毎日 06:10**。06:00 の `detect-client-alerts` の10分後）

### 6-5. 翌朝の確認（有効化の翌朝）

**`net._http_response` は6時間（`pg_net.ttl` の既定）で消えるので、12:10 JST までに読む**。それ以降は Edge Functions の Logs と `notification_logs` で確かめる。

`net._http_response`・`cron.job_run_details`・`notification_logs` は Claude の読み取り権限（MCP）でも読めるので、Claude に頼める。

```sql
-- 06:10 JST の cron の応答（timed_out / error_msg の行も見るため、content ではなく時刻で絞る）
select id, created at time zone 'Asia/Tokyo' as created_jst, status_code, timed_out, error_msg, content
from net._http_response
where created >= ((now() at time zone 'Asia/Tokyo')::date + time '06:09') at time zone 'Asia/Tokyo'
  and created <  ((now() at time zone 'Asia/Tokyo')::date + time '06:13') at time zone 'Asia/Tokyo'
order by created;
```

- **`status_code = 200` だけで判断しない**。`content` の中身を読む（`content::jsonb ->> 'dryRun'` など）
  - `dryRun` が `false` であること。`true` なら cron の body が欠けている（dry run の 200 になり、何も送らない）
  - `detectionReady` が `true` であること。`false` なら 06:00 の自動チェックが D に成功していない（§5-6 で確かめ、検知を流し直したら §6-6 で送る）
  - `outcome` の件数。期待値は、ブラウザ通知を登録したトレーナーの人数ぶん `sent`、未登録は `skipped` / `no_tokens`
    （設定画面でオンにしていない・iPhone だけで使う・購読が失効したトレーナーは正常に `no_tokens`）。`pending` か `missing` が 0 でなければ §6-6
- `detectionReady: true` かつ `trainerCount: 0` は正常（新しいアラートが無い日）。この日は `notification_logs` に行ができないので、
  行が無いだけでは「実行されなかった日」と区別できない。12:10 JST を過ぎたら、Logs の `Trainer alert digests: ...` の行
  （検知が未完了の日は `Alert detection has not succeeded for ...`）で確かめる
- `cron.job_run_details` の `succeeded` は enqueue しただけ（§4）

```sql
-- 送信の記録（12:10 JST 以降も残る）
select created_at, user_id, status, detail, dedup_key
from public.notification_logs
where dedup_key like 'client_alert_digest:%'
order by created_at desc
limit 20;
```

### 6-6. 送り直し（オーナー作業。本番への書き込みは Claude が行わない）

- **検知が遅れて成功した日**（`detectionReady: false` だった日）: その日はキーを使っていないので、検知が成功した後に
  `jsonb_build_object('dry_run', false, 'target_date', '<D>')` を §6-3 の形で送れば、そのまま送られる（全トレーナーが対象。`trainer_id` は付けない）
- **`failed` / `skipped` / `partial` / `pending` の行を作り直すとき**（§6-3 のやり直し、push サービスの一時障害（5xx）の日など）:
  そのトレーナーの dedup キー**1行だけ**を `dedup_key` の完全一致で消してから、同じ D で `trainer_id` を付けて再実行する。他の行を巻き込まない

```sql
delete from public.notification_logs
where dedup_key = 'client_alert_digest:<trainer_id>:<D>';
```

- 消してから再実行すると、そのトレーナーにもう1通届く。送る前に、`trainer_id` を付けた dry run で `alreadyLogged` が 0 になったことを確かめる
- `failed` / `resolve_error`（宛先を読めず何も送っていない行）だけは、消さずに同じ D で再実行すれば送り直される
- `outcome.missing` が出た日（ログの書き込みに失敗した）は、通知は送られている可能性がある。再実行すると二重に届きうるので、先に Logs とブラウザで確かめる

### 6-7. ロールバック

- **止めるだけ**: §6-4 の停止 SQL。関数は呼ばれなければ何もしない
- PR2 は migration を含むので **revert しない**（適用済みの migration ファイルまで消え、以後の `db push` が止まる）。戻すときは新しいコミットで直す
- sw.js に不具合があって通知が出ないとき: Vercel で直前のデプロイへ戻す。ブラウザが旧版に戻るのは次の更新確認（ページの読み込み・push の受信）の後なので、
  DevTools の `SW_VERSION` で確かめる
- CHECK に `client_alert` が残っても害は無い。消すなら先に `notification_preferences` の `kind = 'client_alert'` の行を消してから CHECK を戻す
