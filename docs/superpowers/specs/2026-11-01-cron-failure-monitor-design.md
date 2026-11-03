# cron 失敗の監視（判断7-3 / フェーズ5.3 の残り）— 設計

- 日付: 2026-11-01
- ブランチ: `feature/cron-failure-monitor`（`develop/1.0.0` から）
- 範囲: Supabase（migration 1本・Edge Function 1本の新設・`_shared/push.ts` の種別追加・`config.toml`・テスト）と docs。Web / Mobile は変更なし
- 前提の決定: 統合判断7-3「`cron.job_run_details` の失敗を通知ディスパッチャ経由でトレーナー（運営）に飛ばす監視ジョブを1本設ける」。時期は「朝のまとめの直後の PR」（オーナー決定 2026-10-04）
- レビュー反映（2026-11-01）: pg_net の番号の巻き戻り（§4.1）、`outcome: null`（§4.2）、通知の tag（§5）、command の書き換え方（§4.4）、既定権限（§4.1）、確認の窓（§4.3）

## 1. 目的と成功の条件

**目的**: 毎日動く cron（6本）が失敗したり動かなかったりしたときに、オーナーが気づけるようにする。今は誰も気づけない（`job_run_details` は HTTP の成否を見ておらず、結果の `net._http_response` は6時間で消える。2026-09-13 の `cleanup-ai-images` の 500 は手で SQL を見て偶然見つけた）。

**成功の条件**
1. SQL の cron が失敗すると、次の確認（06:40 / 20:40 JST）でオーナーのブラウザに1通届く
2. HTTP の cron が 401・5xx・タイムアウト・接続失敗で失敗しても、同じように届く
3. 動くはずの時刻に動かなかった毎日の cron（DB の再起動などで pg_cron は取り戻さない）も届く
4. `200` でも中身が失敗（dry run のまま・その日の自動チェックが未完了・朝のまとめの送信失敗）なら届く
5. 同じ失敗で2回通知しない。届かなかった（宛先なし・送信失敗）ときは次の確認で送り直す
6. 問題が無ければ何も送らない。既存の cron の動き（schedule・active・送る内容）は変えない

## 2. 本番の実測（2026-11-01、読み取りのみ）

| ジョブ | schedule（UTC） | JST | 種類 |
|---|---|---|---|
| `issue-recurring-tickets` | `0 0 * * *` | 09:00 | SQL |
| `auto-skip-workouts` | `0 18 * * *` | 03:00 | HTTP |
| `cleanup-ai-images` | `0 19 * * *` | 04:00 | HTTP |
| `detect-client-alerts` | `0 21 * * *` | 06:00 | SQL |
| `notify-trainer-alerts` | `10 21 * * *` | 06:10 | HTTP |
| `send-session-reminders` | `0 11 * * *` | 20:00 | HTTP |

- `cron.job_run_details` は 468 行・`failed` は 0 件・`cron.timezone` は GMT・`pg_net.ttl` は 6 hours。pg_net 0.14.0 / pg_cron 1.6
- `net._http_response.id` が `net.http_post` の戻り値（request_id）。URL やジョブ名は残らず、webhook（`parse-message-tags`）の応答も同じ表に混ざるので、**今は応答とジョブを結び付けられない**
- `net.http_request_queue_id_seq` は UNLOGGED で、DB の異常終了や復元の後は 1 に戻る（本番の `last_value` は 226 で、2026-06-13 の起動以降の要求数とほぼ一致）。**request_id は長期的に一意ではない**
- `notification_logs.kind` に CHECK は無い。`notification_preferences` は行が無ければオンなので、新しい種別に migration は要らない

## 3. 採用案: request_id を記録して応答を照合する

HTTP の4本の command を `INSERT INTO public.cron_http_requests (jobname, request_id) SELECT '<job>', net.http_post(...)` に包み、確認のときに `net._http_response` と突き合わせる。url・headers・body・timeout は変えない（今の command を読んで先頭だけを置き換える。§4.4）。

| 案 | 採らなかった理由 |
|---|---|
| 関数側で結果を記録する（2026-10-04 の設計書 §14 が想定した案） | 関数を4本変更して再 deploy する必要があり、共通のラッパーの不具合が本番の4本を同時に止める。関数に届かない失敗（401・404・接続失敗）は「記録が無い」としか分からず、原因が残らない。今回の案は関数に触らず、HTTP のステータスと本文がそのまま読める |
| 時刻で応答とジョブを結び付ける | webhook の応答と混ざるので確実でない |
| `pg_net.ttl` を延ばす | Supabase の設定に依存し、結び付けの問題も解決しない |

## 4. DB（migration `20261101000000_cron_health_monitor.sql`）

### 4.1 表

`public.cron_http_requests`（HTTP の cron の発射記録）: `id bigint GENERATED ALWAYS AS IDENTITY PK` / `request_id bigint NOT NULL` / `jobname text NOT NULL` / `requested_at timestamptz NOT NULL DEFAULT now()` / `checked_at timestamptz`（応答を評価した時刻。NULL は未評価）
- `request_id` に PK も UNIQUE も付けない（**重要**）。§2 のとおり番号が戻ると、一意制約があると cron の INSERT が重複で失敗し、同じトランザクションの `net.http_post` も巻き戻って本番の HTTP の cron が飛ばなくなる
- `checked_at IS NULL` の部分インデックスを付ける

`public.cron_health_problems`（見つけた問題）:
- `id bigint GENERATED ALWAYS AS IDENTITY PK`
- `source_key text NOT NULL UNIQUE`（同じ失敗を2回数えない。`run:<runid>` / `req:<cron_http_requests.id>` / `missed:<jobname>:<予定時刻の epoch>`。request_id は使わない）
- `jobname text NOT NULL`
- `kind text NOT NULL CHECK (kind IN ('job_failed','missed_run','http_error','no_response','bad_result'))`
- `occurred_at timestamptz NOT NULL`
- `summary text NOT NULL`（短く、ロック画面に出してよい内容だけ。例 `HTTP 500` / `失敗` / `未実行`）
- `detail text`（200 文字まで。例外の文言や本文の先頭。通知には出さない）
- `notified_at timestamptz` / `created_at timestamptz NOT NULL DEFAULT now()`

権限: どちらも RLS 有効・ポリシー無し。既定権限（`ALTER DEFAULT PRIVILEGES` で `service_role` にも全権限が付く）があるので、両表と IDENTITY のシーケンスから `PUBLIC, anon, authenticated, service_role` を REVOKE ALL してから、`service_role` に `cron_health_problems` の `SELECT` と `UPDATE (notified_at)` だけを GRANT する（`cron_http_requests` は無し）。cron は postgres（所有者）で動くので INSERT できる。

### 4.2 `public.cron_http_result_problem(p_jobname, p_status_code, p_timed_out, p_error_msg, p_content)`

応答1件を分類する純関数（IMMUTABLE。問題なしなら0行、問題ありなら `(kind, summary, detail)` の1行）。表を読まないので単体でテストできる。EXECUTE は postgres のみ（`PUBLIC, anon, authenticated, service_role` から REVOKE）。想定外の例外は `WHEN others` で `bad_result` / `応答が不正` にする（1件のせいで確認全体を 500 にしない）。

| 応答 | kind | summary |
|---|---|---|
| `timed_out = true`、または `error_msg` が `Timeout` で始まる（pg_net 0.14.0 はタイムアウトでも `timed_out` を埋めず、`status_code` も `timed_out` も NULL で `error_msg` が `Timeout of 60000 ms reached. ...` になる。隔離スタックの実際の応答で確認） | `no_response` | `タイムアウト` |
| `error_msg` あり（接続失敗など） | `no_response` | `接続失敗` |
| 2xx 以外 | `http_error` | `HTTP <code>` |
| `status_code` が NULL（`timed_out` でも `error_msg` ありでもないのに。pg_net は返さないはずの形で、`HTTP <code>` が作れない） | `bad_result` | `応答が不正` |
| 2xx で `content` が NULL・JSON でない・JSON オブジェクトでない | `bad_result` | `応答が不正` |
| `dryRun` か `dry_run` が true | `bad_result` | `dry run のまま` |
| `notify-trainer-alerts` で `detectionReady` が false | `bad_result` | `自動チェック未完了` |
| `notify-trainer-alerts` で `detectionReady` が false でなく（キーが無いときも含む）`outcome` が JSON オブジェクトでない（`null` は `notification_logs` を読み直せなかったとき。DB の障害で送信も失敗している場面に出る） | `bad_result` | `送信結果不明` |
| `notify-trainer-alerts` で `outcome` の `failed + pending + missing + skippedBy.vapid` が 1 以上 | `bad_result` | `送信失敗 N件` |

`send-session-reminders` の `outcome.failed` は見ない（FCM→APNs の既知の不達で毎回のように出るため。APNs キーの登録後に足す。§10）。`cleanup-ai-images` の `failed` も見ない（次回の実行に回る設計）。

### 4.3 `public.run_cron_health_check()`

SECURITY DEFINER・`search_path = ''`・VOLATILE。EXECUTE は `service_role` のみ。引数なし（本実行に時刻を差し込める口を作らない。テストは `now()` からの相対で行を作る）。冪等で、何度呼んでも `source_key` で重複しない。

1. **SQL・HTTP 共通の失敗**: `cron.job_run_details` を `cron.job` に LEFT JOIN し（削除したジョブは `jobid:<id>` と書く）、時刻は `COALESCE(start_time, end_time)` で見る（起動前に失敗した行は `start_time` が NULL）。直近48時間の `status = 'failed'`（時刻がどちらも NULL の行も含む。`occurred_at` は記録した時刻）、または `succeeded` 以外のまま1時間を過ぎた行（時刻があるものだけ。時刻が無い `starting` は経過時間が分からず、pg_cron が次の起動で `failed` にする）→ `job_failed`（`run:<runid>`、summary は `失敗` / 止まった行は `未完了`、detail は `return_message`）。`jobid` が NULL の行は `jobid:不明` と書く（`jobname` の NOT NULL 違反で確認全体を止めない）
2. **動かなかった毎日のジョブ**: `active` で schedule が `M H * * *` の形のジョブごとに、`cron.timezone` で直近48時間の予定時刻（5分以上前のもの）をすべて求め、それぞれの前後（−1分〜+1時間）に実行が無ければ `missed_run`（`missed:<jobname>:<epoch>`）。窓を1の失敗とそろえるので、確認が2回続けて落ちても見逃さない。失敗した実行も「実行あり」に数える（1で出る）。`jobname` が NULL のジョブは `jobid:<id>` と書く
   - 直近7日に1回も動いていないジョブは対象外（有効化した直後に誤って出さない）
   - その予定時刻より前に実行があるジョブだけを見る（新設のジョブや7日以上止めて再開したジョブが今日初めて動いた直後に、まだ動いていなかった昨日の予定時刻を `未実行` にしない）
   - `inactive` は人が止めたものなので見ない。`M H * * *` 以外の schedule（監視自身の `40 11,21 * * *` など）もこの判定の対象外
3. **HTTP の応答**: `checked_at IS NULL` の `cron_http_requests` を `net._http_response` と `r.id = q.request_id AND r.created >= q.requested_at` で突き合わせる（番号が戻っても古い応答を拾わない。複数あれば発射の後で最初の応答）
   - 応答あり → §4.2 で分類し、問題があれば記録（`req:<id>`）。`checked_at` を埋める
   - 応答なしで15分以内 → 何もしない（次の確認に回す）
   - 応答なしで15分超・48時間以内 → `no_response` / `結果不明`（pg_net の停止か、6時間を過ぎて応答が消えた）。`checked_at` を埋める
   - 応答なしで48時間超 → 問題にせず `checked_at` だけ埋める（監視を止めて再開したときに、実際は正常だったジョブの `結果不明` が山になるのを防ぐ）
4. **掃除**: 90日より前の `cron_http_requests`（`requested_at`）と、通知から90日を過ぎた `cron_health_problems`（`notified_at`）を消す。未通知は消さない。時刻がどちらも NULL の `failed` の問題は、`job_run_details` に行が残っている間は消さない（1の窓で外れないので、消すと記録し直されて同じ失敗をもう1回通知する）
5. `notified_at IS NULL` の問題を古い順（**id の昇順**）に返す（`id, jobname, kind, summary, detail, occurred_at`）。`occurred_at` の順にすると、後から見つかった問題が途中に入っても §5 の「最初の id」「最後の id」が変わらず、同じ時間内の再実行で dedup キーが同じになって、送っていない問題まで通知済みになる

### 4.4 cron

- HTTP の4本の command を §3 の形に書き換える。**書き写さず、今の `cron.job.command` を読み**、先頭の `SELECT net.http_post(` を `INSERT INTO public.cron_http_requests (jobname, request_id) SELECT '<job>', net.http_post(` に正規表現で置き換えて `cron.alter_job(<jobid>, command := ...)` で戻す（`send-session-reminders` の `+ 1` のような式を写し間違えない）。先頭がこの形でなければ RAISE で止める。すでに包まれていれば飛ばす。schedule・active は変えない
- `check-cron-health` を `40 11,21 * * *`（06:40 / 20:40 JST）で登録。`{"dry_run": false}`・`timeout_milliseconds := 60000`・command は他と同じ形（自身は `cron_http_requests` に記録しない。応答が次の確認まで残らず、自分の失敗を自分では通知できないため）。**無効で登録**し、有効化はオーナー
- 時刻の理由: 06:40 は 03:00〜06:10 の4本を6時間以内に読め、朝のうちに検知を流し直せる。20:40 は 09:00 と 20:00 の2本を読め、その晩のうちにリマインダーを手で送り直せる
- 末尾で検査し、違えば migration ごと止める: 4本の command が `public.cron_http_requests` を含み、url のジョブ名・`timeout_milliseconds := 60000` が残っていること／`send-session-reminders` に `+ 1` の式が残っていること／`check-cron-health` が1件で無効

## 5. Edge Function `check-cron-health`（新設）

- `POST`（他のメソッドは 405）、`isServiceRequest` で認証（401）。`supabase/config.toml` に `[functions.check-cron-health] verify_jwt = false`（無いと deploy で true になり、cron が 401 で止まる）
- body: `{ dry_run?: boolean, test_notification?: boolean }`。真偽値の `false` のときだけ送る（省略時は dry run。lessons「push を伴う cron 起動 Function は dry_run 省略時に送らない」）
- 宛先: Edge Functions の secret `CRON_ALERT_TRAINER_IDS`（カンマ区切りの trainer_id。UUID でないものは捨てて `console.warn`）。PUBLIC リポジトリに ID を書かないため secret にする

処理:
1. `test_notification: true`（`dry_run: false` のときだけ）: タイトル `自動処理の監視`・本文 `テスト通知です` を宛先に送って返す（`{ status, dryRun, testNotification: true, recipients, notified }`。`notified` は届いたか）。確認や記録は行わない。実際の失敗が起きるまで通知の経路を試せないため（dedup は分単位）
2. `rpc('run_cron_health_check')`（冪等なので `withRetry`）。読めなければ 500
3. dry run → 問題の一覧を返す（記録は §4.3 が冪等に行うが、送らず `notified_at` も埋めない）
4. 問題が0件 → 200
5. 宛先が0人 → 送らず `recipients: 0` と `console.warn`（問題は未通知のまま残り、宛先を設定した後の確認で送られる）
6. 宛先ごとに `sendNotification`
   - `kind: 'cron_failure'` / `userType: 'trainer'` / `data: { type: 'cron_failure', url: '/dashboard', tag: 'cron_failure:<最初の問題の id>-<最後の問題の id>' }`（tag を問題ごとに変える。同じ tag だと、ブラウザを閉じている間に届いた前の通知が後の通知に置き換えられ、前の問題に気づけないまま通知済みになる。`sw.js` は `data.tag` を優先するので変更不要）。テスト通知の tag は `cron_failure_test`
   - タイトル `自動処理で問題が起きています`、本文は最大3件 `<job>（<summary>）` を `・` でつなぎ、残りは `ほかN件`。`detail` は入れない
   - dedupKey: `cron_failure:<trainer_id>:<最初の問題の id>-<最後の問題の id>:<UTC の YYYY-MM-DDTHH>`（同じ問題の同じ時間内の再実行は1通。届かなかった分は次の確認で別のキーになり送り直せる）
   - TTL は既定（ブラウザを次に開いたときに届く）。`sendNotification` は再試行しない
7. `notification_logs` を引き直し、1人でも `sent` / `partial` なら対象の問題の `notified_at` を埋める。それ以外（`no_tokens`・`failed`）は埋めない。引き直せなければ埋めない（`console.warn`。もう1回通知する方が、通知が欠けるより軽い）。更新は `id` の範囲（最初〜最後の問題の id）と `notified_at IS NULL` で絞る（問題は id の昇順で返るので同じ行になり、問題が多くても URL が伸びない）

返り値: `{ status, dryRun, recipients, pendingCount, notified, problems: [{ jobname, kind, summary, occurred_at }] }`（`detail` は返さない。`pendingCount` は埋める前の未通知の数、`notified` はこのリクエストで `notified_at` を埋めたか）。

純関数は `_shared/cron_health.ts`（`parseCheckRequest` / `parseRecipientIds` / `formatProblemsBody` / `problemsDedupKey` / `problemsTag` / `testNotificationDedupKey` / `isDeliveredStatus`、送信と読み直しを引数で受ける `dispatchAndCheckDelivered`）に置き、Deno でテストする。`_shared/push.ts` は `kind` に `'cron_failure'` を足すだけ。通知設定の画面には出さない（オーナーだけの通知で、行が無ければオン）。

## 6. エラー処理

| 状況 | 動き |
|---|---|
| RPC の一時障害 | `withRetry`。それでも失敗なら 500（次の確認でやり直す。発見は冪等なので失うものは6時間を過ぎた応答だけで、それは `結果不明` として出る） |
| 宛先なし・`no_tokens`・送信失敗 | `notified_at` を埋めず、次の確認（最長14時間後）で送り直す |
| `notified_at` の更新失敗 | 200 で `console.warn`。次の確認で同じ問題をもう1回通知する（通知が欠けるより軽い） |
| `check-cron-health` 自身の失敗 | `job_run_details` の失敗は次回の確認で拾える。関数に届かない失敗や、RPC が 500 を返し続ける場合は通知できない（§10 の限界。Edge Functions の Logs と SQL で見る） |

## 7. テスト

- **SQL**（隔離スタック）: 新規 `supabase/tests/cron_health_check_test.sql` を BEGIN…ROLLBACK で。§4.2 の全行を表で確かめる（`outcome: null`、`content` が NULL・配列を含む）／`failed`・`start_time` が NULL の `failed`・止まった行・48時間より前・削除したジョブ／予定時刻に実行があるとき・無いとき・2日前の予定・7日動いていないとき・inactive／応答あり（200・500）・15分以内の応答なし・15分超・48時間超／**同じ `request_id` の古い行と古い応答があっても INSERT が通り、新しい失敗が記録され、古い応答を拾わない**／2回呼んでも重複しない／通知済みは返らない／掃除／権限（`anon`・`authenticated` は表も関数もシーケンスも不可、`service_role` は §4.1 の範囲だけ。`has_column_privilege('service_role', ..., 'detail', 'UPDATE')` は false、分類関数の EXECUTE は無し）／`cron.timezone` の時刻計算。`cron_jobs_test.sql` は5本に広げ、HTTP の4本が `cron_http_requests` に記録することと、**監視自身以外で `net.http_post` を呼ぶ cron が記録を忘れていないこと**を固定し、`send-session-reminders` の期待値を `+ 1` の式まで含む断片にする。既存の SQL テストはすべて通すこと
- **負の対照**: command から INSERT を外す・`+ 1` を落とす・判定の閾値を変える・EXECUTE を広げる・`request_id` に UNIQUE を付ける、でテストが落ちることを確かめる
- **Deno**: `_shared/cron_health_test.ts`（§5 の純関数）。`deno check`（`--node-modules-dir=none`）
- **通し**（隔離スタック + ホストの Deno + 自己署名の HTTPS 受け口。lessons「Web Push の通しの確認」）: 500 の応答を作って本送信 → 受け口に1通（復号して title・body・`data.tag` を確かめる）・`notified_at` が埋まる → 2回目は送らない／`no_tokens` では埋まらず、次の時間に送り直される／宛先なし／`test_notification`／問題なしのときは何も送らない／dry run は送らない

## 8. リリース（オーナー作業。順序どおり）

1. PR を `develop/1.0.0` へマージ
2. `supabase migration list --linked` と `supabase db push --dry-run` で未適用が `20261101000000` の1本だけであることを確かめて `supabase db push`
3. `supabase secrets set CRON_ALERT_TRAINER_IDS=<自分の trainer_id>`
4. `supabase functions deploy check-cron-health`
5. dry run（SQL エディタから `net.http_post`、`{"dry_run": true}`、`timeout_milliseconds := 60000`）。問題が0件であること
6. `{"dry_run": false, "test_notification": true}` でブラウザに届くことを確かめる
7. cron を有効化。翌日に `cron_http_requests` に4本分の行があり、`checked_at` が埋まっていることを Claude が読み取りで確かめる

2 から 7 は一度に行い、ジョブの時刻（03:00・04:00・06:10・20:00 JST）をまたがない（2 の後に動いたジョブの応答は6時間で消えるので、評価しないまま6時間を過ぎると `結果不明` が出る）。またいだら、有効化の直前に dry run をもう1回流す（6時間以内の応答ならそこで評価される）。Web のリリースとは無関係に進められる。

**ロールバック**: 通知を止めるだけなら cron を無効に。4本の command の INSERT は残っても害が無い（掃除が止まり、`cron_http_requests` が1日4行ずつ増えるだけ）。migration は revert しない。戻すなら新しい migration で command を戻す。

## 9. 前提として決めたこと（オーナーが覆せる）

1. 宛先はオーナーのトレーナーアカウントへの Web Push（統合判断7-3 の「通知ディスパッチャ経由」。追加のサービス契約が要らない）。メールは範囲外（§10）
2. 確認は1日2回（06:40 / 20:40 JST）で、夜中には送らない
3. `send-session-reminders` の個別の送信失敗は通知しない（APNs の既知の不達のため）
4. 1回の確認で1通のまとめ。問題ごとに別の通知にはしない
5. 通知設定の画面には種別を足さない
6. 他のトレーナーのブラウザの購読が失効（410）すると、掃除は正常に済んでも朝のまとめの `failed` に数えられ、オーナーに `送信失敗 1件` が届く。関数に触らないと見分けられないので受け入れる（まれで、1回限り）
7. ジョブを止めて7日以内に、予定時刻をまたいで再開すると `未実行` が出る（`cron.job` に有効化の時刻が無く、SQL では見分けられない）
8. schedule を変えた直後は、古い時刻の実行が新しい予定の窓に入らず `未実行` が1件出ることがある
9. 起動前に DB が再起動した行（時刻が両方 NULL の `failed`）は `失敗` と `未実行` の両方が並ぶことがある（時刻が無く予定時刻に結び付けられないため）

## 10. 範囲外・分かっている限界

- **監視の経路そのものが止まると気づけない**: pg_cron の停止・Vault のキーの誤り・Edge Functions の障害・RPC が失敗し続ける不具合では、監視も同時に止まる（Vault のキーが壊れると HTTP の5本が全部 401 になり、通知も送れない）。**外部の死活監視**（healthchecks.io などに確認のたび ping し、途絶えたらメール）で塞げるが、外部サービスの登録が要るので別の変更にする
- 通知の宛先のブラウザの購読が消えていると `no_tokens` のまま届かない（確認のたびに `notification_logs` には残る）。メールの経路は別の変更
- `check-cron-health` の応答は `cron_http_requests` に入れないので、最新の結果を見るには6時間以内の `net._http_response` か Edge Functions の Logs
- 検知が遅れた日の自動の回復（06:40 の再送スロット）は入れない（通知を受けて手で流し直す）。これまで失敗は0件で、自動化の根拠が無い
- `send-session-reminders` の `outcome.failed` の監視は、APNs キーの登録後に足す
- 運営向けの画面は作らない。詳細は `cron_health_problems` を SQL か Claude の読み取りで見る
