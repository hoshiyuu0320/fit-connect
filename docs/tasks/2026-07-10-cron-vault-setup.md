# cron / Vault 初回セットアップ手順（ユーザー作業）

**作成日**: 2026-07-10
**対象**: プロジェクトオーナー（1回きりの手動作業）
**関連 migration**: `supabase/migrations/20260710020000_codify_cron_jobs.sql` / `20260829000300_cleanup_ai_images.sql` / `20260912000000_cron_use_secret_key.sql` / `20260913000000_session_reminder.sql` / `20260913000100_session_reminder_cron_target_date.sql` / `20260914000000_client_alerts.sql` / `20260914000100_client_activity_snapshot.sql` / `20260914000200_client_alert_detection.sql` / `20260922000100_secure_parse_message_tags_webhook.sql`（messages トリガー。§冒頭の 2026-09-22 追加の注記）

`auto-skip-workouts` / `cleanup-ai-images` / `send-session-reminders` の cron ジョブは migration で「無効(inactive)状態」で登録されます。
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
- `detect-client-alerts`（フェーズ9.1）は §5 の手順で有効化するまで active = false
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
  - 3ジョブとも pg_net のタイムアウトは60秒（`auto-skip-workouts` / `cleanup-ai-images` は migration
    `20260913000200` で既定5秒から延長。関数内の一時障害の再試行を含めて応答を待てるようにするため）
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
> （フェーズ7の通知ディスパッチャ完成後に配線予定。フェーズ5.3の残タスク）。

---

## 5. `detect-client-alerts`（異常検知）の有効化

**関連 migration**: `20260914000000_client_alerts.sql`（alerts / alert_detection_runs）/
`20260914000100_client_activity_snapshot.sql`（活動の定義）/ `20260914000200_client_alert_detection.sql`（評価・本実行・検知状態・cron）
**仕様**: `docs/tasks/2026-09-13-trainer-intervention-plan.md`

毎日 06:00 JST（`0 21 * * *` = UTC 21:00）に、担当顧客の「体重の急な変化（weight_change）」と「記録途絶（record_gap）」を
判定して `public.alerts` に残すジョブです。Web のダッシュボード「今日の対応」とサイドバーのバッジがこの表を読みます。
**push 通知は送りません**（VAPID 設定後の後続タスク）。

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

cron 失敗の自動監視ジョブは作っていない（トレーナー向け push の配線と一緒に作る。オーナー決定 2026-09-13）。
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
