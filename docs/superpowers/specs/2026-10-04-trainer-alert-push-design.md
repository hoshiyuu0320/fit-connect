# トレーナー向けアラートの朝のまとめ通知（フェーズ9.1 拡張 push `client_alert`）— 設計

- 日付: 2026-10-04
- ブランチ: `feature/trainer-alert-push`（`develop/1.0.0` から。本書はここ）。実装は2本の PR に分ける（§15）: PR1 Web Push の土台 → PR2 朝のまとめ
- 範囲: Supabase（migration 1本・Edge Function 1本の新設・`_shared/push.ts` の変更・テスト）と Web（`public/sw.js`・通知設定・購読の登録 API・「今日の対応」の行）、docs（手順書・計画書）。Mobile は変更なし
- 前提の設計: `docs/tasks/2026-09-13-trainer-intervention-plan.md` の「通知（VAPID 待ちの間と、後で push を足す場所）」。
  本書と食い違う箇所は本書に従う（オーナー決定 2026-10-04）
- レビュー反映（2026-10-04）: 一覧の「今朝」の目印（§4.3・§7.5）、購読の所有者（§7.6）、PR の分割（§15）、設計レビューの残りの指摘（運用の手順 §11.3、送信の安全策 §5・§6.2、Service Worker §7.1、購読の照合 §7.2、前提 §13・範囲外 §14）

## 1. 目的と成功の条件

**オーナーの依頼**: VAPID の設定（Edge Functions の secrets）が済んだので、設定を確かめながら 9.1 の残りの拡張（トレーナー向け push）を進める。

**目的**: 毎朝 06:00 JST の自動チェック（cron `detect-client-alerts`）で新しく対応が必要な顧客が見つかった日に、
トレーナーが Web を開いていなくてもブラウザ通知で気づけるようにする。

**オーナー決定（2026-10-04）**
1. cron 失敗の監視（判断7-3）は、この PR に含めず直後の PR で作る（9/13 の決定3「push と一緒に作る」の時期を1PR分ずらす）
2. 通知は **トレーナーごとに朝のまとめ1通だけ**。アラートごとの個別通知は送らない（9/13 計画の「high は1件ずつ + まとめ」を置き換える）
3. 本書 §4〜§11 の内容（チャットで提示した4節の設計）を承認。承認の後に足した範囲（§7.1 の `renotify` と tag、§7.2 の鍵の照合と自動解除、§7.3、§7.5、§7.6、PR の分割 §15）は §13 の「オーナーが覆せる前提」として扱う

**成功の条件**
1. その日に新しく出たアラートがあるトレーナーのブラウザに、06:10 JST 以降に1通だけ届く（ブラウザを登録した端末ごとに1通。§13-15）
2. 通知をクリックすると「今日の対応」があるダッシュボード（`/dashboard`）が開く。既にダッシュボードのタブがあればそれが前面に出て、一覧とサイドバーのバッジが取り直される（タブが既に見えていた場合も）
3. ロック画面に顧客名・健康の数値が出ない
4. 新しいアラートが無い日、通知設定で「アラート（朝のまとめ）」をオフにしたトレーナー、ブラウザ通知を登録していないトレーナーには届かない
5. 同じ D について、1トレーナーに送るのは1回だけ（cron の再実行・手動実行を含む）。過去日を手動で指定した送信は、別の D の通知として送られる（§13-6）
6. 顧客と兼務しているアカウントでも、トレーナー向けの通知が顧客用のスマホに届かない。顧客向けの通知もトレーナーのブラウザに届かない
7. 送信の記録（`notification_logs`）が `sent` になる
8. 同じブラウザを別のトレーナーが使っても、前のトレーナー宛の通知はそのブラウザに届かない（購読は最後に登録したトレーナー1人のもの。§7.6。PR1）
9. 通知から開いた「今日の対応」で、今朝新しく出た理由に「今朝」の目印が付き、見分けられる（§7.5。PR2）

## 2. 本番の実測（2026-10-04、読み取り専用。件数だけ）

| 項目 | 値 |
|---|---|
| Edge Functions の secrets | `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` の3つが登録済み（`supabase secrets list` で名前だけ確認。値は見ていない） |
| Vercel の公開鍵との対応 | **未確認**。トレーナーのブラウザ購読が0件のため、実際に1通送るまで分からない（オーナーに確認手順を依頼済み。§11.1 の手順0） |
| `device_tokens` | 1件（`ios` / `client`）。トレーナーの `web_push` は **0件** |
| `push_subscriptions` | 1件（最終更新 2026-02-23）。`device_tokens` へは未移行 |
| `notification_logs`（直近14日） | `message` の `failed` 4件（`sent=0/1 failed=1`。FCM→APNs の既知の不達）、`message` の `skipped`（`no_tokens`）3件 |
| 開いているアラート | `record_gap` / `high` 1件（`surfaced_on` 2026-10-01） |
| cron | 5本すべて active（`detect-client-alerts` は `0 21 * * *` = 06:00 JST） |
| `notification_preferences.kind` の CHECK | `message` / `goal_achievement` / `session_reminder` |
| トレーナーの通知設定の行 | `message` が `enabled` で1行だけ |
| トレーナー | 5名 |

## 3. 採用案

**朝のまとめ1通（採用）**: トレーナーごとに1日1通。その日に新しく出たアラートの人数を重大度別に書き、クリックでダッシュボードを開く。

| 案 | 採らなかった理由 |
|---|---|
| 要確認（high）は1件ずつ + まとめ（9/13 計画） | 自動チェックは1日1回なので、個別に送っても即時性は増えない。同じ時刻に複数通届き、ロック画面に顧客名が出る。顧客詳細の `?tab=` をクエリの変化に追従させる修正も要る |
| 要確認だけ1件ずつ | 「注意」（睡眠の悪化・3〜6日の記録途切れなど）が通知されない |
| 検知の完了を契機に通知する（検知の SQL の末尾から呼ぶ） | 手動の再実行（過去日のバックテストなど）で、過去日の通知が飛ぶ危険がある。検知は SQL だけで完結する1つのジョブで、通知は HTTP 越しの別の関数なので、別の cron（06:10）にして `alert_detection_runs` で検知の完了を確かめる方が、失敗の影響が小さい |

採用案では顧客詳細へ直接飛ばないため、9/13 計画の前提4点のうち「`/clients/[id]` の `?tab=` 追従」は不要になる（範囲外）。

## 4. 通知の仕様

### 4.1 対象日と前提
- 対象日 D は JST の暦日（`'YYYY-MM-DD'`）
- **D の自動チェックが成功していること**を先に確かめる: `alert_detection_runs` に `target_date = D` の行が**1行以上**ある
  - 無ければ1通も送らず、`detectionReady: false` を返して終える（HTTP 200）。失敗の検出は次の PR の監視で行う。この日のキー（`dedup_key`）は使わないので、検知が遅れて成功した日は、あとから同じ D を `target_date` に指定して送れる（§11.3）
  - `alert_detection_runs` は成功した本実行ごとに1行（失敗はトランザクションごと巻き戻る）。`target_date` に一意制約が無く、同じ D の再実行（手動）は仕様で許されているので、**同じ D の行が複数になりうる**。読むのは「有無」だけ（§5.2-2）
  - 行があるのは「D について本実行が成功した」こと。06:10 の時点では D の `alerts` は確定している。06:10 より後に同じ D を再実行して新しく `surfaced_on = D` になった行は、D の通知が送信済みなら通知されない（一覧には出る。許容する）

### 4.2 対象のアラート
- `alerts` のうち `status = 'open'` かつ `surfaced_on = D`
  - `surfaced_on = D` には、D の新規・対応済みからの再浮上・open のまま重大度が上がったもの、の3つが入る（`run_client_alert_detection` の 4-1 / 4-2 と新規 INSERT）
  - 06:00〜06:10 の間にトレーナーが対応済みにした行は入らない（それでよい）
- 今の担当顧客に限る: `clients.client_id = alerts.client_id` かつ `clients.trainer_id = alerts.trainer_id`
  - ダッシュボードの RLS（`alerts_trainer_select`）と同じ条件を、service_role で明示的に書く
- 読み取りは PostgREST: `alerts` から `trainer_id, client_id, severity, clients!inner(trainer_id)` を `status = 'open'`・`surfaced_on = D` で取り、担当の一致は純関数で絞る
  - API の最大行数（1000）を超えても漏れないよう、`id` 順に 1000 件ずつ取り切る

### 4.3 集計
- トレーナーごと・顧客ごとに、一番重い重大度を1つ採る（high > medium > low）
  - 1人に2件（例: 体重の変化 high と睡眠の悪化 medium）あっても1名として high に数える
  - 未知の重大度は medium として扱う（Web の `normalizeSeverity` と同じ）
- 重大度ごとの人数 `{ high, medium, low }` を数える。3つとも0のトレーナーは対象外（送らない）
- 出力はトレーナー ID 順（テストと dry run の結果を安定させるため）
- **この重大度は「今朝新しく出たアラート」だけで決める**。一覧の行のバッジ（その顧客の全 open の最重大。`buildTriageRows`）とは違うことがある
  - 例: 3日前から high が open の顧客に、今朝 medium が新しく出た → 通知は「注意 1名」、一覧の行は「要確認」
  - このずれは、一覧の理由に付ける「今朝」の目印（§7.5）で補う。通知の人数と一覧の人数（サイドバーのバッジ）は元から別物（通知は新着だけ、一覧は対応が必要な顧客すべてと未返信）
  - 採らなかった案: 顧客の全 open の最重大で数える（「新しく要確認」と言いながら新しいのは注意、になる。読み取りも顧客の open 全件に広がる）／通知の人数を一覧と同じ「対応が必要な全体」にする（新しいアラートが無い日は届かない条件4と矛盾し、未返信は `alerts` に無く Edge Function から数えにくい）

### 4.4 文面
- タイトル: `今日の対応があります`
- 本文: `新しく` + 次の区分を `・` でつないだもの。人数が0の区分は書かない
  - `要確認 N名`（high）→ `注意 N名`（medium）→ `参考 N名`（low）の順
  - 区分名は Web の `severityLabel` と同じ
- 例: `新しく要確認 1名・注意 1名` / `新しく注意 2名` / `新しく要確認 1名・注意 2名・参考 1名`
- 顧客名・アラートの種別・数値は入れない（ロック画面と `notification_logs.title/body` に残るため）

### 4.5 送信
`sendNotification` を、対象のトレーナー1人につき1回呼ぶ。

| 引数 | 値 |
|---|---|
| `userId` | `trainer_id` |
| `userType` | `'trainer'` |
| `kind` | `'client_alert'` |
| `title` / `body` | §4.4 |
| `data` | `{ type: 'client_alert', url: '/dashboard', tag: 'client_alert:<D>' }`（`tag` は §7.1） |
| `dedupKey` | `client_alert_digest:<trainer_id>:<D>` |
| `ttlSeconds` | `43200`（12時間。§6.2） |
| `retryDeadline` | 関数の開始時刻 + `CRON_RETRY_BUDGET_MS`（既存の cron 関数と同じ） |

- dedup キーに対象日を含めるので、同じ D で何度呼んでも1通。宛先が無くて `skipped` になっても、翌日は新しいキーで送れる（9/13 計画が避けたかった「キーの使い切り」は日単位のキーでは起きない）
  - ただし**同じ D のキーは、結果が何であれその日の分を使い切る**。同じ D の再実行で送り直されるのは、宛先の解決が読めずに `failed / resolve_error` になった行だけ（`push.ts` の `reclaimUnsentLog`）。`skipped`（宛先なし・設定オフ・静かな時間帯・VAPID 未設定）、`failed`（push サービスの 5xx・403 など）、`partial`、`pending` は、その日は送り直されない（§9）。送り直す必要があるときの救済は §11.3
- 送信（`sendNotification`）は再試行しない（二重送信を避ける。IMPLEMENTATION_TASKS のフェーズ8.4 の方針）

### 4.6 通知設定
- `notification_preferences.kind` に `client_alert` を足す。行が無ければオン（既存の既定どおり）
- 静かな時間帯（`quiet_hours_*`）は `push.ts` が既に尊重する。Web に設定の UI は無い（範囲外）

## 5. Edge Function `notify-trainer-alerts`（新設）

### 5.1 リクエスト
- `POST`、ヘッダー `apikey`（cron は Vault の `secret_key`）、body は JSON `{ dry_run?: boolean, target_date?: string, trainer_id?: string }`
- 認証: `isServiceRequest(req)` が偽なら 401 `{ error: 'Unauthorized' }`（既存の cron 関数と同じ）
- `dry_run`: `body.dry_run !== false`。**省略時は dry run（送らない）**（lessons「push を伴う cron 起動 Function は dry_run 省略時に送らない」）。送る側に倒れるのは真偽値の `false` だけで、`'false'`（文字列）・`0`・`null` も dry run
- `target_date`:
  - キーがあって `undefined` / `null` でなければ `parseTargetDate` で検証する。実在する `YYYY-MM-DD` でなければ 400
  - JST の今日より後なら 400（未来の日付は検知が無いので送るものが無い。誤った cron 式の早期発見のため）
  - 過去の日付は受け付ける（手動での送り直し・本番での確認用。dedup キーで二重送信は防がれる）
  - `dry_run: false` でキーが無い（または `null`）なら 400（`target_date (YYYY-MM-DD) is required when dry_run is false`）
  - dry run でキーが無ければ JST の今日
- `trainer_id`（任意）: 指定すると、そのトレーナー1人だけを対象にする（本番での確認・送り直し用。cron は付けない）。dry run でも本送信でも使える
  - UUID の形式でなければ 400（空文字も 400）。キーがあって `undefined` / `null` なら、キーが無いのと同じ（全員）
  - 絞り込みは §5.2-5 の集計の後に掛ける（担当の一致などの判定は変えない）。レスポンスにも `trainerId` を入れる
- body が JSON でない、または JSON でもオブジェクトでない（`null`・配列・文字列・数値）ときは `{}` として扱う（`null` を `body.dry_run` と読んで TypeError にしない。既存の cron 関数と同じ形）。この場合は dry run になる＝cron の body が欠けても、何も送らない側に倒れる。手順9 の確認で見分ける（§11.2）
- 上の判定は純関数 `parseNotifyRequest(body: unknown, todayJst: string)` に切り出す（§10.1 でテスト）。返り値は `{ ok: true, dryRun: boolean, targetDate: string, trainerId: string | null } | { ok: false, error: string }`（`error` がそのまま 400 の body になる）

### 5.2 処理
1. 認証 → リクエストの検証
2. D の自動チェックの成否を読む（`alert_detection_runs` の `target_date = D` の有無。`withRetry` + `.retry(false)`）。読めなければ 500
   - 「有無」だけを読む: `.select('id').eq('target_date', D).limit(1)` を配列で受け、`data.length > 0` で判定する。**`.single()` / `.maybeSingle()` は使わない**（同じ D の行が複数あると PGRST116 で失敗し、その日のまとめが1通も出なくなる。§4.1）
3. 成功していなければ `detectionReady: false` で返す（送らない）
4. §4.2 のアラートを読む（`withRetry` + `.retry(false)`、1000件ずつ）。読めなければ 500
5. §4.3 の集計 → `trainer_id` の指定があればそのトレーナーだけに絞る → dry run ならここで返す
   - dry run でも、対象の dedup キーの `notification_logs` を読み取りで引き、既に行がある人数を `alreadyLogged` として返す（本番確認の手順6 で、手順7 が重複になることを事前に知るため。読めなければ `null`）
6. 本送信: 送る前に、対象の dedup キーの `notification_logs` を 50 件ずつ読み、既にある行を「重複」として控える（読み取りは `send-session-reminders` の `fetchReminderLogs` と同じ）
   - ただし `status = 'failed'` かつ `detail = RESOLVE_ERROR_DETAIL` の行は重複にしない。`push.ts` がその行を取り直して送り直すので、今回の結果として数える（`send-session-reminders/index.ts` の `isResendable` と同じ）
   - **この読み取りが読めなくても中断しない**。重複の数が分からなくなるだけで、二重送信は `sendNotification` 側の dedup（`UNIQUE`）が防ぐ。`console.warn` を出し、`duplicate: null` で続行する
7. トレーナーごとに `sendNotification`（§4.5）。呼び出す前の例外は `failed` に数えて続行する（`sendNotification` 自体は内部で例外を握りつぶすので、ここに来るのは呼び出し前の例外だけ）
8. 送った後に `notification_logs` を引き直し、status 別に数えて返す（§5.3）
   - 引き直しが読めなくても、送信は済んでいるので 500 にしない。`outcome: null` で 200 を返し、`console.warn` を出す

### 5.3 レスポンス

| 場合 | HTTP | body |
|---|---|---|
| dry run | 200 | `{ status: 'ok', dryRun: true, targetDate, detectionReady, trainerCount, alreadyLogged, digests: [{ trainer_id, high, medium, low }] }` |
| 本送信 | 200 | 上と同じ形で `dryRun: false`、加えて `outcome`（下） |
| 自動チェック未完了 | 200 | `detectionReady: false`・`trainerCount: 0`・`digests: []`（本送信なら `outcome` の数はすべて0） |
| 認証失敗 | 401 | `{ error: 'Unauthorized' }` |
| 入力不正 | 400 | `{ error }` |
| DB の読み取り失敗（送信前。§5.2-2・4） | 500 | `{ error }` |

- `digests` に入るのはトレーナー ID と人数だけ（顧客 ID・名前は返さない）
- `outcome`: `{ sent, partial, skipped, failed, pending, duplicate, missing, skippedBy: { no_tokens, disabled, quiet_hours, vapid, other } }`
  - `sent` / `partial` / `skipped` / `failed` / `pending` は、今回送った（または取り直した）キーの `notification_logs` の `status` を数えたもの。呼び出し前の例外（§5.2-7）は `failed` に足す（`missing` には数えない）
  - `duplicate` は、送る前から行があって送らなかったキーの数（その読み取りが読めなかったときは `null`）
  - `missing` は、送ったのにログの行が見つからないキーの数（ログの書き込み失敗や、関数が途中で止まった場合。0 でなければ `console.warn`）
  - `skippedBy` は `skipped` の行の `detail` から数える: `no_tokens`・`disabled`・`quiet_hours`・`vapid`（`vapid_not_configured` を含むもの）・`other`。VAPID 未設定などの設定の誤りと、宛先なし・設定オフを、人数だけで見分けるため（顧客・トレーナーの識別子は入れない）
  - `pending` が残るのは、push サービスが応答しないまま関数が止まった場合など。その行は同日の再実行では送り直されない（§9・§11.3）。`sent + partial + skipped + failed + pending + missing + duplicate` が `trainerCount` になる
  - 引き直しが読めなかったときは `outcome: null`

### 5.4 ファイル構成
- `supabase/functions/_shared/client_alert_digest.ts`（純関数。DB・ネットワークに依存しない。`parseTargetDate` を `_shared/session_reminder_format.ts` から import する）
  - `DIGEST_TITLE` / `DIGEST_URL`（`'/dashboard'`）/ `DIGEST_TTL_SECONDS`（`43200`）
  - `digestDedupKey(trainerId, targetDate)`
  - `buildTrainerDigests(rows: AlertRow[])`（§4.2 の担当の一致と §4.3 の集計）
    - `AlertRow = { trainer_id: string; client_id: string; severity: string; clients: { trainer_id: string } | { trainer_id: string }[] | null }`。`clients` は PostgREST の多対一の埋め込みで、通常はオブジェクトだが配列でも来うる（Web の `getOpenAlerts` と同じく、配列なら先頭を使う）。`null`・読めない形は「担当が一致しない」として数えない
  - `formatDigestBody({ high, medium, low })`（§4.4）
  - `parseNotifyRequest(body: unknown, todayJst: string)`（§5.1。`todayJst` は呼び出し側が `formatJstDate(new Date())` で作る）
  - 「今日（JST）」を返す関数は新設しない。`session_reminder_format.ts` の `formatJstDate(now)` を使う（日付の境目のテストは既存）
- `supabase/functions/_shared/client_alert_digest_test.ts`（Deno）
- `supabase/functions/notify-trainer-alerts/index.ts`（つなぎ込み。`createClient` は `send-session-reminders` と同じ esm.sh 版）
  - `notification_logs` を読む `fetchNotificationLogs` と `isResendable` は、`send-session-reminders/index.ts` の `fetchReminderLogs` / `isResendable` の**複製**（どちらもそのファイルの非公開の定義で、共有の置き場が無い）。どちらかを直したらもう片方も直す。`_shared` への切り出しは別の機会（§14）。複製元と違うのは、ラベル文字列（`notify-trainer-alerts ...`）と、読めなかったときの扱い（§5.2-6）
- `supabase/config.toml` に `[functions.notify-trainer-alerts] verify_jwt = false`（無いと deploy で verify_jwt=true になり cron が 401 で止まる）

## 6. `_shared/push.ts` の変更

§6.3 は PR1、§6.1・§6.2 は PR2（§15）。

### 6.1 種別
- `SendArgs.kind` に `'client_alert'` を足す

### 6.2 有効期限（`ttlSeconds`）
- `SendArgs.ttlSeconds?: number` を足す。正の整数のときだけ Web Push の `TTL` オプションに渡す（それ以外は無視して今の既定のまま）
- FCM には渡さない（トレーナーは Web Push だけ。FCM→APNs は既知の不達で検証もできない）。コメントに「Web Push だけに効く」と書く
- 12時間にする理由: ブラウザが閉じていても、push サービスが預かって次に開いたときに届ける。夕方以降に朝のまとめが出ても役に立たないので、それまでに捨てさせる
- Web Push の送信オプションの組み立ては純関数 `buildWebPushOptions(vapid, ttlSeconds)` に切り出す。置き場は **import の無い新しいファイル `supabase/functions/_shared/web_push_options.ts`**（`vapid` は `{ subject, publicKey, privateKey }` の構造的な型で受ける）。`push.ts` がこれを import する。既存の `*_test.ts` と同じ「外部依存ゼロ・ネットワーク不要」で `deno test` できる（`push.ts` を import すると、型検査で esm.sh と npm の取得が走るため）。テストは §10.1
- **送信に `timeout` を付ける**: `buildWebPushOptions` は `timeout: 10000`（ミリ秒）も返す（`npm:web-push@3.6.7` が受け付ける有効なオプション名。無いと、push サービスが応答しない1件で逐次の送信が止まり、ログ行が `pending` のまま、その日のキーを使い切る）。Web Push 全体（メッセージ通知を含む）に効く
- 範囲外（§14）: 宛先 URL（`device_tokens.token`）の検査。顧客も RLS で自分の `device_tokens` に任意の URL を書けるが、本書では入れない（理由は §14）

### 6.3 宛先を `user_type` で絞る
- `resolveTargets` の `device_tokens` の読み取りに `.eq('user_type', userType)` を足す
  - 兼務アカウント（同じ auth uid に trainers 行と clients 行がある）で、トレーナー宛の通知が顧客用スマホ（Mobile は常に `user_type = 'client'` で登録）に届かなくなる。逆に顧客宛の通知がトレーナーのブラウザ（Web は常に `'trainer'` で登録）に届かなくなる
  - `device_tokens` が0件のときの `fcm_token` への後戻り（`clients` / `trainers` の列）は今も `userType` で表を選んでいるので変えない
- 既存の呼び出しへの影響

| 呼び出し | userType | 変わること |
|---|---|---|
| `parse-message-tags`（顧客→トレーナーのメッセージ通知） | trainer | トレーナー自身の `web_push` 行だけに届く（今は兼務なら顧客用スマホにも届く） |
| `parse-message-tags`（トレーナー→顧客のメッセージ通知・目標達成） | client | 顧客の Mobile の行だけに届く |
| `send-session-reminders` | client | 同上 |

- `push.ts` を同梱する `parse-message-tags` と `send-session-reminders` も再デプロイが要る（PR1 のリリースで行う。§11.1）。PR2 の `notify-trainer-alerts` は、この絞り込みが入った `push.ts` を最初から使う

## 7. Web の変更

### 7.1 `fit-connect/public/sw.js`
- **install / activate**: `install` で `self.skipWaiting()`。更新した sw.js が、開いているタブが全部閉じるのを待たずに有効になる（これが要点）。`activate` の `self.clients.claim()` は、この SW が `fetch` を扱わないので実質の効果は無い（入れても無害。入れるなら `event.waitUntil(self.clients.claim())`）
  - `sw.js` に `SW_VERSION`（版の識別用の定数）を持たせる。DevTools で、どの版が動いているかを見分けるため（§11.2 手順5・6）
  - 新版が先に有効になっても、デプロイ前から開いたままのタブは古いバンドルで、`message` を受けるリスナー（§7.3）を持たない。一度リロードするまで、そのタブは `notification-clicked` を受けても取り直さない（過渡期だけ）
- **push**（通知は必ず出す。`userVisibleOnly` の購読で通知を出さないと、Chrome は汎用の通知を出し、ブラウザによっては購読が失効する）
  - 全体を1本の `event.waitUntil` にまとめ、表示前の補助処理（古いまとめを閉じる）の失敗は `try/catch` で握りつぶして、**必ず `showNotification` を呼ぶ**
  - 本文を JSON として読む。読めない、または JSON が `null`・オブジェクトでない（文字列・数値・配列）ときは今と同じ（`title: '新着メッセージ'`、本文はテキスト、URL は `/message`）
  - URL: `payload.data?.url` → `payload.url`（古い形）→ `'/message'` の順に採る
    - 自分のオリジンの**パスだけ**を使う。`new URL(raw, self.location.origin)` を作り、(1) 解析できない、(2) オリジンが `self.location.origin` と違う、(3) 作った `pathname + search + hash` が `/` で始まらない、または `//` で始まる、のどれかなら `'/message'` にする（通知を踏み台にした外部サイトへの遷移を防ぐ）
    - (3) が要る理由: `https://<自オリジン>//evil.com` や `/.//evil.com` はオリジンが自分のままだが、`pathname` が `//evil.com` になる。これを `clients.openWindow()` に渡すと、スキーム相対 URL として外部ホストに解決される
    - この正規化は、push で `notification.data.url` に保存するときと、notificationclick で読むときの両方で同じ関数を通す（旧版の SW が保存した未検証の通知にも効く）
  - tag: `payload.tag` → `payload.data?.tag` → `payload.data?.type` → `'default'` の順に採る。各候補は「文字列で、空でない」ものだけを採る
    - 朝のまとめは `data.tag = 'client_alert:<D>'`（§4.5）なので日ごとに別の通知になり、前日のまとめが残っていても翌日のまとめは新しい通知として音・バナー付きで出る（同じ tag の置き換えは既定で無音のため）
    - **古いまとめを閉じる**: 今回の tag が `client_alert:` で始まるときだけ、`registration.getNotifications()` で `client_alert:` で始まる通知を探し、**日付部分が今回より古いものだけ**を閉じる（`YYYY-MM-DD` の文字列比較）。今回の tag が `client_alert:` で始まらない（メッセージなど）ときは何も閉じない。過去日の手動送信が、今日のまとめを閉じない
    - メッセージは `message`、それ以外の種別もそれぞれの種別名になり、種別をまたいで上書きしなくなる。ただし**全顧客・全会話のメッセージ通知は tag `message` の1枚に潰れる**（今の `default` と同じ。本文は最後の1通だけ残る）。会話ごとの tag は、`parse-message-tags` が送信者を `data` に入れる別の変更が要る（§14）
  - `renotify: true` を付ける。ただし**採った tag が空でないときだけ**（tag 無しの `renotify: true` は TypeError になる）。同じ tag の置き換え（例: 2通目のメッセージ）でも知らせる（連投されると連投の数だけ鳴る。§13-9）。対応していないブラウザ（Firefox・Safari）では無視される
  - タイトル・本文・アイコン・`requireInteraction: false` は今と同じ
- **notificationclick**
  - クリック先 `targetUrl = notification.data?.url`（上の正規化を通す。無い・不正なら `'/message'`）
  - `clients.matchAll({ type: 'window', includeUncontrolled: true })` のうち、オリジンと **パス名が `targetUrl` と同じ**タブがあれば、それを前面に出す（移動はしない。メッセージ画面の書きかけを消さないため）
    - 前面に出したタブに `postMessage({ type: 'notification-clicked', url: targetUrl })` を送る（§7.3）。タブが既に見えていた場合は `visibilitychange` が起きないので、これで取り直させる
    - `focus()` や `postMessage` が失敗したとき（`matchAll` の後にタブが閉じたなど）は、`clients.openWindow(targetUrl)` に落とす。クリックを必ず何かに繋ぐ
  - 無ければ `clients.openWindow(targetUrl)`
  - 別のパスのタブは動かさない
- 今のメッセージ通知（`data: { type: 'message', messageId }`、URL 無し）はクリックで `/message` を開く（今と同じ）

### 7.2 通知設定（`fit-connect/src/components/settings/NotificationSection.tsx`）
- 所属: 購読の登録し直し・鍵の照合・失敗の表示と `pushSubscriptionKey.ts` は PR1。`notificationKinds.ts` と「アラート（朝のまとめ）」のトグル・親トグルの説明は PR2（§15）
- 種別の一覧と既定値・読み込みのフィルタを純関数のモジュール `fit-connect/src/lib/notifications/notificationKinds.ts` に移し、`client_alert` を足す
  - 一覧の順: メッセージ受信 → **アラート（朝のまとめ）** → 目標達成のお知らせ
  - 文言: ラベル `アラート（朝のまとめ）`、説明 `朝の自動チェックで新しく対応が必要な顧客が見つかった日に1通お知らせします`
  - 既定はオン。読み込みでは一覧にある種別の行だけを反映する（今の `kind === 'message' || ...` の置き換え）
- 親トグルの説明（許可がブロックされていないとき）: `メッセージや朝のまとめをブラウザ通知でお知らせします。`
- **購読の登録し直し**: 設定画面を開いたとき、ブラウザに購読があり通知が許可されていれば、まず購読の公開鍵（`subscription.options.applicationServerKey`）と今の `NEXT_PUBLIC_VAPID_PUBLIC_KEY` をバイト単位で比べる
  - 比べた結果は3つ: **同じ**（`same`）／**違う**（`different`）／**比べられない**（`unknown`）。`unknown` は、ブラウザが購読の鍵を返さない（`null`）、環境変数が空・壊れている（引用符つき・base64url として読めない・65バイトでない）など。**復号の例外や不正な形は `different` ではなく `unknown`**（不一致として扱うと、正常な購読を自動で消してしまう）
  - 同じ、または比べられない: その購読を `POST /api/push-subscriptions` に送り直す（画面には何も出さない。失敗は `console.error`）
    - ブラウザでは購読済みなのにサーバーに登録が無い状態（2026-02 の `push_subscriptions` の1件など）が、設定画面を開くだけで直る。`device_tokens.last_seen_at` も更新される
    - API は upsert なので何度送っても行は増えない。同じ endpoint を別のトレーナーが持っていれば、その行は登録時に消える（§7.6）
  - 違う（古い鍵で作った購読。送っても push サービスに 403 で拒まれ続ける）: 送り直さず、`DELETE /api/push-subscriptions` でサーバーの行を消し、ブラウザの購読も解除して、トグルをオフに戻す。案内 `通知の設定が変わりました。もう一度オンにしてください。` を出す。`DELETE` が失敗したら（非 OK・例外）、ブラウザの購読は解除せずトグルもそのままにして、`console.error` だけ残す（サーバーに行が残ってブラウザの購読だけ消える状態を作らない）
  - 公開鍵が無い dev 環境などでは比べられないので、何もしない（送り直しもしない）
  - 比較は純関数 `compareApplicationServerKey(subscriptionKey, vapidPublicKeyBase64Url): 'same' | 'different' | 'unknown'`（`fit-connect/src/lib/notifications/pushSubscriptionKey.ts`）に切り出す。既存の `urlBase64ToUint8Array` もここへ移し、`window.atob` を**グローバルの `atob`** に書き換える（vitest は `environment: 'node'` で `window` が無い）。例外は `unknown` に畳む
  - 分岐の全体も、依存を引数で受ける関数 `syncPushSubscription({ getSubscription, vapidPublicKey, post, del, unsubscribe })`（`fit-connect/src/lib/notifications/syncPushSubscription.ts` 新規）に出し、結果は `'reposted' | 'purged' | 'noop' | 'failed'` を返す。コンポーネントはこれを呼んで結果を画面に反映するだけにする。`same` / `different` / `unknown`・API の失敗・`unsubscribe` の失敗を vitest で確かめる（§10.3）
  - 非同期の処理は、`cancelled` フラグ付きの専用の effect に分ける（既存の購読確認の effect とは別）。React の StrictMode は dev で effect を2回走らせるので、`cancelled` が無いと POST・DELETE・`unsubscribe` が2回走る。**処理の間は親トグルを `disabled` にする**（自動の POST が走っている最中に利用者がオフにすると、DELETE の後に POST が追いついて、解除済みの行が復活するため）
- **有効化・無効化の失敗を画面に出す**（今は `console.error` だけでトグルが黙って戻る）
  - 公開鍵が無い: `現在プッシュ通知を有効にできません。時間をおいて再度お試しください。`。**通知の許可を求める前に**確かめる（許可のダイアログを出した後に「有効にできません」と出さない）
  - 登録の API が失敗: `プッシュ通知の登録に失敗しました。再度お試しください。`
  - それ以外の失敗（`subscribe()` の例外、購読の鍵データが欠けている、解除の失敗）: `プッシュ通知の設定を変更できませんでした。再度お試しください。`
  - 無効化で `DELETE` が失敗した（非 OK・例外）ときは、購読を残したまま「それ以外の失敗」を出す（やり直せるように。今は `response.ok` を見ずに続けて解除してしまう）
  - 許可のダイアログを閉じた（`default`）ときは何も出さず、トグルはオフのまま。拒否（`denied`）は既存の説明のとおり
  - 表示は種別の保存失敗と同じ場所に出す（既存の文言 `通知設定の保存に失敗しました。再度お試しください。` の表示）。エラーは `role="alert"`（今の赤い表示は読み上げに伝わらない）。上の「通知の設定が変わりました」の案内はエラーではないので、別の見た目（`role="status"`・中立色）にする。有効化・無効化・種別の保存を始めるときに前の表示を消す
- Vercel で必要な環境変数は `NEXT_PUBLIC_VAPID_PUBLIC_KEY` だけ（ビルド時に埋め込まれる。変えたら再デプロイ）
- 鍵を変えるときの順序: Edge Functions の secrets（`VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY`）→ Vercel の `NEXT_PUBLIC_VAPID_PUBLIC_KEY` を変えて再デプロイ → 手順0（§11.1）。Vercel だけ先に変わると、その間に設定画面を開いた人の、動いていた購読が「違う」として自動で消える。手順書に書く（§12）

### 7.3 通知クリック時の取り直し（`TriageSection.tsx`・`layout.tsx`）
- `navigator.serviceWorker` の `message` イベントで `data.type === 'notification-clicked'` を受けたら、`TriageSection` は一覧を取り直し（既存の `load()`）、`layout` はサイドバーのバッジを取り直す（既存の取り直しの処理）
- `serviceWorker` が無いブラウザでは何もしない。リスナーはアンマウントで外す
- 既存の `visibilitychange` での取り直しはそのまま

### 7.4 Mobile
変更なし。未知の `kind` の行は無視され（`notification_preferences_provider.dart` の switch に default が無い）、`device_tokens` は読まない。

### 7.5 「今日の対応」の行に「今朝」の目印（`fit-connect/src/components/dashboard/TriageRow.tsx`。PR2）
朝のまとめは「今朝新しく出たもの」を数えるが、遷移先の一覧は対応が必要な顧客すべてを並べ、どれが新しいかを示していない（§4.3）。通知から着いた人が新着を探せるようにする。
- 理由（`reason`）の `surfacedOn` が、表示時点の JST の今日と同じなら、その理由のチップの先頭に小さな文字ラベル「今朝」を付ける
  - 通知の対象（`surfaced_on = D`: 新規・対応済みからの再浮上・open のまま重大度が上がったもの。§4.2）と同じ定義。日付が変われば消える
  - 行の見た目（顧客名・重要度バッジ・並び順・スコア）は変えない。行のバッジは今までどおり全 open の最重大
- 判定は純関数 `isSurfacedToday(surfacedOn, now)`（`fit-connect/src/lib/triage/surfacedToday.ts` 新規）。`surfacedOn` は `'YYYY-MM-DD'`、`now` の JST の暦日と文字列で比べる。`now` は引数で受ける（テストで固定。JST の日付が変わる UTC 14:59:59 / 15:00:00 の境目を入れる）。`now` は `TriageSection` が一覧を取り直した時点の値を `TriageRow` まで渡す（未返信の時間と同じ基準）。依存の無い小さなモジュールにする（`date-fns` などを import しない。lessons の First Load の例。`next build` で前後を比べる。§10.3）
- 見た目: 色だけに頼らず文字「今朝」で示す。red / amber は重要度専用なので使わず、`TRIAGE_TEXT_LINK` と同じ teal 系（文字 `#0F766E`・背景 `#F0FDFA`）の小さなラベルにする。読み上げでは理由の文言の前に「今朝」と読まれる
- 範囲外: 新着の行を上位に寄せる並び替え（スコアは据え置き）。「今朝」の行が上位5件の外にあるときは「すべて表示」で見える（§14）

### 7.6 購読の所有者（1 endpoint = 1 所有者。`fit-connect/src/lib/supabase/savePushSubscription.ts`。PR1）
ブラウザの購読はアカウントではなくブラウザに付く。いっぽうサーバーの行は `device_tokens` の `(user_id, token)` で一意なので、同じブラウザで別のトレーナーが登録すると、同じ endpoint の行が2つになる。ログアウトは `supabase.auth.signOut()` だけで購読も行も消さない（`settings/page.tsx`。`signOut` を呼ぶのはここだけ）ので、前のトレーナー宛の通知（メッセージ通知は送信者名と本文の先頭50文字を含む）が、いま別のトレーナーがログインしているブラウザに出続ける（既存の挙動）。§7.2 の自動の登録し直しを入れると、後のトレーナーの行が増えて両方が届くようになる。
- 登録（`POST /api/push-subscriptions`）で、**同じ endpoint を持つ他のトレーナーの行を消す**（購読は最後に登録したトレーナー1人のもの）。旧 `push_subscriptions` は `onConflict: 'endpoint'` で、すでにこの動き
  1. `device_tokens` に自分の行を upsert
  2. `platform = 'web_push'` かつ `token = endpoint` かつ `user_id <> 自分` の行を削除（`user_type = 'trainer'` に限る。顧客の `ios` / `android` の行は触らない）
  3. 旧 `push_subscriptions` に upsert（従来どおり。ここの失敗は `console.error` だけで、応答は失敗にしない）
  - 1・2 のどちらかが失敗したら 500 を返す。どちらも何度流しても同じ結果になる（べき等）ので、画面からの再試行で直る。1 を先にするのは、削除だけが済んで自分の行が無い（誰にも届かない）状態を作らないため
  - これは、`device_tokens` が送信側の唯一の宛先になった今、登録の失敗を黙って成功にしないことも兼ねる（現状は `device_tokens` の失敗を `console.error` で握りつぶし、旧表の失敗だけを失敗にしている）。§7.2 の「登録の API が失敗」の文言が実際に出るようになる
- 削除（`DELETE`）は今までどおり、自分の行だけ（endpoint 単位）
- 残る穴（範囲外。§14）: 後のトレーナーが設定画面を開く（登録する）まで、前のトレーナーの行は残る。ログアウト時にサーバーの行を消す案は、`signOut` を呼ぶのが設定画面のログアウトボタンだけでセッション切れでは走らないため、今回は見送る
- §11.1 の手順0と §11.2 の手順7で、同じブラウザのアカウントを切り替えて試したときは、最後に登録したトレーナーが宛先になる

## 8. DB の変更（migration `20261004000000_client_alert_push.sql`。PR2）

1. `notification_preferences.kind` の CHECK を `('message', 'goal_achievement', 'session_reminder', 'client_alert')` に広げる（`DROP CONSTRAINT IF EXISTS notification_preferences_kind_check` → `ADD CONSTRAINT`。`20260913000000_session_reminder.sql` と同じ書き方）。列の COMMENT も更新
2. cron `notify-trainer-alerts` を登録する
   - schedule `'10 21 * * *'`（UTC。JST 06:10）
   - command: `net.http_post` で `<Vault project_url>/functions/v1/notify-trainer-alerts` を、ヘッダー `apikey` = Vault `secret_key` で呼ぶ。body は `jsonb_build_object('dry_run', false, 'target_date', to_char((now() AT TIME ZONE 'Asia/Tokyo')::date, 'YYYY-MM-DD'))`（JST の今日。`send-session-reminders` と違い `+ 1` しない）、`timeout_milliseconds := 60000`。headers と url の組み立ては `20260913000100_session_reminder_cron_target_date.sql` の command と同一（`Content-Type: application/json` と `apikey` の2つ）。body と timeout だけが違う
   - 同名のジョブが無いときだけ登録し、登録直後に `cron.alter_job(..., active := false)` で **無効** にする。有効化はオーナー（§11.2）
   - command は名前付きドル引用 `$cmd$` で書く
3. 末尾で検査する（違えば `RAISE EXCEPTION` で migration ごと止める）
   - `notification_preferences` の `kind` に関する CHECK（`contype = 'c'` で、定義に `kind` を含むもの）が**1本だけ**で、その定義に4種別（`message` / `goal_achievement` / `session_reminder` / `client_alert`）がすべて入っていること（制約名が想定と違う環境で、古い CHECK が別名で残るのを見逃さない）
   - `cron.job` の `jobname = 'notify-trainer-alerts'` が1件で、`schedule = '10 21 * * *'`・`active = false` であること（「無効で登録」の最終形を migration の中で固定する。§11.2 手順8 の前に有効になっていてはいけない）

新しい表・関数・権限は無い。既存の関数を書き換えないのでドリフトガードは要らない。

## 9. エラー処理

| 状況 | 動き |
|---|---|
| 自動チェックが D に成功していない | 送らない。200・`detectionReady: false`。`console.warn` |
| DB の読み取りの一時障害 | `withRetry`（最大3回）。それでも失敗なら 500。送信前なので1通も送っていない |
| 送信前の dedup 確認が読めない | 送信は続ける（二重送信は `push.ts` の dedup が防ぐ）。`duplicate: null`・`console.warn`（§5.2-6） |
| トレーナーに宛先が無い | `push.ts` が `skipped` / `no_tokens` を記録。翌日は新しいキー |
| トレーナーに旧 `trainers.fcm_token` が残っている | `device_tokens` が0件のときだけ、`push.ts` がその FCM トークンへ送る（stage2 の後戻り。`client_alert` でも変えない）。FCM→APNs は届かないので `failed`、APNs が直れば実際に届く。リリース前に件数を確かめる（§11.2 手順4） |
| 通知設定でオフ | `push.ts` が `skipped` / `disabled` |
| 静かな時間帯 | `push.ts` が `skipped` / `quiet_hours` |
| VAPID 未設定 | `push.ts` が `skipped`（`web_push:skipped(vapid_not_configured)`） |
| push サービスが 404 / 410 | `push.ts` が購読を削除（今の動き） |
| push サービスが 403（鍵の不一致など） | `push.ts` が `failed`。購読は残す（今の動き）。手順0で事前に確かめる |
| push サービスが 5xx / 429 / 通信失敗・`timeout` | `push.ts` が `failed`。購読は残す。**同じ D の再実行では送り直されない**（§4.5）。救済は §11.3 |
| 送信が途中で止まった（push サービスが応答しない・関数の実行が打ち切られた） | ログ行が `pending` のまま残り、同日の再実行では送り直されない。`outcome.pending` と `console.warn` で気づく。救済は §11.3 |
| ログの書き込み（upsert）が失敗した | `push.ts` は通知を止めずに送る（ログは残らない）。`outcome.missing` に出る。同日の再実行は二重に送りうるので、`missing` が出たら §11.3 の確認を先にする |
| `sendNotification` を呼ぶ前の例外 | `failed` に数えて次のトレーナーへ |
| 同じ D の2回目 | `duplicate` に数え、送らない |

## 10. テスト

各テストが入る PR は §12 の表のとおり（§15）。

### 10.1 Deno（`npx -y deno test supabase/functions/_shared/client_alert_digest_test.ts supabase/functions/_shared/web_push_options_test.ts`）
- `buildTrainerDigests`
  - 1人に high と medium → high に1名
  - 担当が変わった顧客（`clients.trainer_id` ≠ `alerts.trainer_id`）は数えない
  - 未知の重大度は medium
  - 複数トレーナーがトレーナー ID 順に並ぶ
  - 入力が空 → 空
  - `clients` がオブジェクト・配列・`null` の3通り（配列は先頭を使う。`null` は数えない）
- `formatDigestBody`: high だけ / medium だけ / 3区分すべて / 0の区分を書かない
- `digestDedupKey` の形
- `parseNotifyRequest`
  - 省略時は dry run / body が `null`・配列・文字列・数値 → `{}` 扱い（dry run・今日）
  - `dry_run: false` で日付無し・`null` → 400 / `dry_run: 'false'`（文字列）・`0`・`null` → dry run
  - 不正な日付・空文字・数値の日付 → 400 / 未来 → 400 / 今日・過去は通る / dry run で日付無し → 今日
  - `trainer_id`: UUID でない・空文字 → 400 / 無し・`null` → `null`（全員）/ UUID → `trainerId` に入る
- 日付の境目（UTC 14:59:59 と 15:00:00）は、既存の `session_reminder_format_test.ts` の `formatJstDate` のテストが押さえている（`jstToday` は新設しない）
- `buildWebPushOptions`（`web_push_options_test.ts`。外部依存ゼロ）: `ttlSeconds` が正の整数なら `TTL` が入る / 0・負・小数・未指定なら入らない / `timeout`（10000）が常に入る / `vapidDetails` に3つの値が入る
- `push.ts` の型確認は `deno check`（lessons「deno 未導入環境で構文検証できない」）

### 10.2 SQL（隔離したローカルのスタックで流す。共有スタック `supabase_db_fit-connect` には当てない）
- 新規 `supabase/tests/client_alert_push_test.sql`
  - CHECK が `client_alert` を受け付け、未知の種別を拒む
  - ジョブ `notify-trainer-alerts` が1件で、schedule が `10 21 * * *`。**`active` は断定しない**（`cron_jobs_test.sql` の慣行。ローカルは migration で inactive のままだが、リモートはオーナーが有効化するなど、環境で値が違う。「無効で登録」は migration 末尾の検査が固定する。§8）
  - command の body が JST の今日（`+ 1` 無し）・`dry_run` false・timeout 60000
    - 文字列の部分一致だけにしない（UTC の日付に取り違えても通ってしまう）。command から `to_char(...)` の式を正規表現で取り出し、`now()` を固定した時刻に置き換えて `EXECUTE` し、返る日付を確かめる: `2026-10-03 21:10:00+00`（= 06:10 JST）→ `2026-10-04` / `2026-10-03 14:59:59+00` → `2026-10-03` / `2026-10-03 15:00:00+00` → `2026-10-04`。「`+ 1` が無い」は `position('+ 1')` ではなく正規表現 `\+\s*1` で否定する
- `supabase/tests/cron_jobs_test.sql` の期待一覧に `notify-trainer-alerts` を足す（`/functions/v1/<ジョブ名>`・Vault の apikey・旧方式を含まないことの検査に乗せる）
  - ファイルの見出し・コメント・`\echo` の「3 ジョブ」は4本に直す。ケース(d)の `body_fragment` には、`'target_date', to_char((now() AT TIME ZONE 'Asia/Tokyo')::date, 'YYYY-MM-DD')` まで含める（`'dry_run', false` だけだと `send-session-reminders` と同じ緩い断片になり、`target_date` の組み立てが壊れても検知できない。migration 側の括弧の書式と一致させる）
- 既存の SQL テストがすべて通ること

### 10.3 Web（vitest）
- `notificationKinds.test.ts`: 一覧の順と文言 / 既定がすべてオン / 読み込みで未知の種別を無視する
- `pushSubscriptionKey.test.ts`: 同じ鍵 → `same` / 1バイト違い・長さ違い → `different` / 購読の鍵が `null`・環境変数が空・引用符つき・65バイトでない → `unknown`（例外にしない）/ base64url（`-` `_`・パディング無し）の変換。`window` の無い Node で動くこと（`atob` を使う）
- `syncPushSubscription.test.ts`（新規）: `same` / `unknown`（鍵が `null`・環境変数が壊れている）→ `post` を1回だけ（`del`・`unsubscribe` は呼ばない。`reposted`）/ `different` → `del` → `unsubscribe` の順で、`post` は呼ばない（`purged`）/ 公開鍵が無い → 何もしない（`noop`）/ `post` の失敗 → `failed` / `different` で `del` が失敗 → `unsubscribe` を呼ばない / `unsubscribe` の失敗 → `failed`
- `savePushSubscription.test.ts`（新規。`supabaseAdmin` を差し替える）: `device_tokens` に upsert したあと、同じ endpoint の他のトレーナーの行だけを消す条件（`platform = 'web_push'`・`token`・`user_id <> 自分`・`user_type = 'trainer'`）で delete を呼ぶ / upsert か delete の失敗は throw / 旧 `push_subscriptions` の失敗は throw しない
- `surfacedToday.test.ts`（新規）: 同じ日 → 今朝 / 前日 → 違う / UTC 14:59:59 と 15:00:00 の境目で JST の日付が変わる / 読めない文字列 → 違う
- `sw.test.ts`: `public/sw.js` を Node の `vm` で読み込む
  - sandbox に渡すもの: `self`（sandbox 自身）、`location`（`origin` を持つ）、`URL`、`clients` と `self.clients`（**同じオブジェクト**。`matchAll` / `openWindow` / `claim`）、`self.skipWaiting`、`registration`（`showNotification` / `getNotifications`）、`addEventListener`（登録されたハンドラを記録する）。vm の新しいコンテキストには `URL` も `location` も無い
  - `sw.js` のパスは `new URL('../../../public/sw.js', import.meta.url)` で解決する（`process.cwd()` 基準にしない。monorepo のルートや worktree から実行しても見失わない）。vm の中で作ったオブジェクトは別の realm なので、比較は `toEqual` を使う（`toStrictEqual` は落ちうる）
  - install / activate: `install` で `skipWaiting` が呼ばれる
  - push: `data.url` を使う / 古い形の `url` を使う / 外部オリジンの URL は `/message` になる / **`//` で始まる形も `/message` になる**（`https://<自オリジン>//evil.com`、`/.//evil.com`、`//evil.com`、`javascript:alert(1)`、`data:text/html,x`、バックスラッシュを含む `/\evil.com`）/ tag が `data.tag` → `data.type` → `default` の順になる（空文字・数値の tag は飛ばす）/ `renotify: true`（採った tag が空のときは付けない）/ 今回が `client_alert:<D>` のときだけ、**日付が古い** `client_alert:` の通知を閉じ、新しい日付のまとめは閉じない / メッセージの push は今日の `client_alert:` の通知を閉じない / `getNotifications` が reject しても `showNotification` が呼ばれる / 本文が JSON でない・`null` のときは今の既定
  - click: 同じパス名のタブがあれば前面に出して `notification-clicked` を送るだけ（移動しない）/ 無ければ新しいタブ / 別のパスのタブは動かさない / `focus()` が reject したら `openWindow` に落ちる / `notification.data.url` が不正なら `/message`
- 既存の `TriageSection` / `layout` の取り直しの分岐が純関数に無いので、`notification-clicked` を受けたときの取り直しは §10.5 の画面の確認で確かめる
- 既存のテストがすべて通ること。Web の変更を含む PR は **`next build` と `next lint` まで**通す（lessons「tsc/vitest が通っても next build までが Web の検証セット」）。`/settings` の First Load JS を変更の前後で比べる（lessons の `describeAlert` の例）

### 10.4 通しの確認（隔離スタック + 関数をホストで動かす）
- `user_type` の絞り込み（§6.3）の確認は PR1 でも、同じ隔離スタックで `kind = 'message'` の通知で行う。PR2 では `client_alert` でもう一度確かめる
- 鍵: テスト用の VAPID の鍵と、受け口用の購読の鍵（ECDH P-256 と auth）をその場で作り、scratch のファイルにだけ置く（コミットしない・チャットに出さない）
- 受け口: 自己署名証明書の **HTTPS** サーバーを scratch で立てる（`npm:web-push@3.6.7` は URL のスキームを見ずに常に `https.request` で送るため、HTTP の受け口には届かない）。`device_tokens.token` にその URL、`web_push_p256dh` / `web_push_auth` に受け口用の鍵
- 関数: `supabase functions serve`（Docker の中から 127.0.0.1 に届かず、証明書も信頼させにくい）ではなく、ホストで `npx -y deno run` で動かす。隔離スタックの API の URL とキー、テスト用の VAPID の鍵は環境変数で渡し、自己署名証明書は deno の `--unsafely-ignore-certificate-errors=127.0.0.1` で通す
  - この方法で送れないと分かった場合: 受け口で中身を受け取る確認をやめ、TTL は §10.1 の `buildWebPushOptions` の単体テストで、1回だけ送ることと宛先の振り分けは `notification_logs` の `status` / `detail`（`sent=x/宛先数`）で確かめる。どちらで確かめたかを報告する
- 環境変数（関数が読むもの）: `SUPABASE_URL`、`SUPABASE_SERVICE_ROLE_KEY`、`VAPID_PUBLIC_KEY`、`VAPID_PRIVATE_KEY`、`VAPID_SUBJECT`（`https:` か `mailto:` の URL でないと `web-push` が例外にする）。実行は `npx -y deno run --allow-net --allow-env ...`。呼び出しは `Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY`（`isServiceRequest` が互換で許す形）
- 証明書: `--unsafely-ignore-certificate-errors=127.0.0.1` が、`web-push` の使う `node:https` に効くかは未確認。効かなければ、SAN に `IP:127.0.0.1` を入れた自己署名証明書を作り、`DENO_CERT=<その PEM>` で信頼させる。それでも送れなければ、上の退路に進む
- 確かめること
  - dry run の人数が §4.3 どおり
  - 本送信で受け口に1回だけ届き、`TTL: 43200` のヘッダーが付く。受け口側で復号して `{ title, body, data: { type: 'client_alert', url: '/dashboard', tag: 'client_alert:<D>' } }` を確かめる
  - 2回目は `duplicate`、受け口には届かない
  - 前回が `failed` / `resolve_error` の行は、再実行で送り直され `duplicate` ではなく今回の結果に数えられる
  - 自動チェックが未完了の日は送らない
  - 兼務アカウント（同じ uid に trainer の `web_push` 行と client の `ios` 行）で、`client_alert` は `web_push` だけに行き、顧客宛の通知は `ios` 側（FCM の鍵が無いので `skipped`）だけに行く
  - 通知設定でオフのトレーナーは `skipped` / `disabled`
  - ブラウザを登録していない（`device_tokens` が無い）トレーナーは `skipped` / `no_tokens`
  - 新しいアラートが無い日は、`notification_logs` に行が作られない
  - 同じトレーナーに `web_push` の行が2つあると、受け口に2回届く（端末ごとに1通。§13-15）
  - 同じ D の `alert_detection_runs` の行が2つあっても `detectionReady: true`（§5.2-2）
  - `trainer_id` を指定すると、そのトレーナー1人だけが `digests` に入り、本送信もその1人だけ
  - 受け口を応答しないサーバーにすると、`timeout`（10秒）で `failed` になり、`pending` が残らない
  - 前回が `failed` / `resolve_error` の行は、`notification_logs` に `status = 'failed'`・`detail = 'resolve_error'` の行を SQL で直接作ってから再実行して確かめる
  - 顧客宛の通知は `notify-trainer-alerts` では確かめられない（顧客には送らない）。scratch の Deno スクリプトから `push.ts` の `sendNotification` を `userType: 'client'` で直接呼ぶ

### 10.5 画面の確認（確立済みの「隔離スタック + 合成 Cookie + 内蔵ブラウザ」）
- 通知設定に「アラート（朝のまとめ）」が出て、保存・読み込みができる
- 公開鍵の無い dev server で有効化すると、通知の許可を求める前に §7.2 の文言が出る
- 設定画面を開くと、購読があれば `POST /api/push-subscriptions` が**1回**送られる（StrictMode の dev でも二重にならない）。前提: `NEXT_PUBLIC_VAPID_PUBLIC_KEY` に65バイトのダミーの公開鍵を入れた dev server（鍵が無い dev server では何も送らない）と、購読を作れるブラウザ、または差し替えた `pushManager`。内蔵ブラウザで購読を作れない場合は、ネットワークを確かめる代わりに `syncPushSubscription` の vitest で `same` / `different` / `unknown` を確かめ、その旨を報告する
- 鍵が違う購読（`different`）: `pushManager` を差し替えて通すと、`DELETE` → `unsubscribe` → トグルがオフ → 案内（`role="status"`）が出る。`DELETE` を失敗させると、購読は残り、トグルもそのまま
- ダッシュボードを表示したまま、ページに `notification-clicked` のメッセージを届けると（Service Worker からの `postMessage` を模して）「今日の対応」とバッジが取り直される
- 「今朝」の目印: `surfaced_on` が今日の open のアラートがある顧客の行にだけ「今朝」が付き、前日のものには付かない（隔離スタックに今日と前日の `surfaced_on` のアラートを入れて確かめる）
- 購読の所有者（PR1）: トレーナー2人の合成 Cookie で同じ endpoint を `POST /api/push-subscriptions` すると、`device_tokens` の `web_push` の行は後の1人だけになる（旧 `push_subscriptions` も同じ）。2人目の登録を失敗させた場合は 500 になる

### 10.6 本番での確認（オーナー。§11.2）
実機のブラウザに届き、クリックでダッシュボードが開き、`notification_logs` が `sent` になること。確認に含めるもの:
- **タブを開いたまま**通知をクリックして、そのタブが前面に出て、「今日の対応」とバッジが取り直されること（Service Worker からの `postMessage` は、実機でしか確かめられない。§7.1・§7.3）
- 新しい `sw.js` が有効なこと（DevTools の Application → Service Workers と `SW_VERSION`。§11.2 手順5・6）
- メッセージ通知の挙動の変更（§13-9）: tag `message` で出て、連投すると連投の数だけ鳴り、本文は最後の1通だけ残る。クリックで `/message` が開く

## 11. リリースとロールバック

2本の PR を順に出す（§15）。PR1 には migration が無く、PR2 にある。

### 11.1 PR1（Web Push の土台）

**リリース（オーナー作業。順序どおり）**
0. 鍵の作り直し（2026-10-04 追記）: 本番に登録された VAPID の鍵が、PUBLIC リポジトリの旧手順書に載っていたものと同じだった。Web のリリースと手順0 の前に、手順書の「鍵を変えるときの順序」で作り直す（トレーナーの web_push 購読が0件のうちなら影響なし）
1. PR を `develop/1.0.0` へマージ（DB の変更は無い）
2. 関数のデプロイ: `supabase functions deploy parse-message-tags`、`supabase functions deploy send-session-reminders`（`push.ts` の `user_type` の絞り込みを反映。`push.ts` を使う関数は、いまはこの2つだけ。デプロイの後に `supabase functions list` で2関数の更新時刻を確かめる）
3. Web（購読の登録 API・設定画面）を main へリリース（時期はオーナー判断）
4. 手順0（下）で鍵の対応を確かめる。実装と並行して済ませてあれば、結果を確認するだけ
5. 回帰の確認: テスト用の顧客アプリからトレーナーへ、トレーナーから顧客へメッセージを1通ずつ送り、どちらも従来どおり届く。Claude が `notification_logs`（件数）の `sent` を読み取りで確かめる

**手順0（設計・実装と並行。コード変更不要）**: Vercel の公開鍵と Edge Functions の鍵が対になっているかを確かめる。**鍵を変えるたびに行う**（変える順序は §7.2）
1. Vercel の `NEXT_PUBLIC_VAPID_PUBLIC_KEY` を今回変えたなら、Vercel を再デプロイ
2. 本番の Web の「設定」→「プッシュ通知」を一度オフ→オン（ブラウザの許可を求められたら許可）
3. テスト用の顧客アプリから、**本文のあるテキスト**のメッセージを1通送る。送り先は、手順2でブラウザを登録したトレーナーの担当顧客として送る（画像だけのメッセージは通知されない。顧客の担当トレーナーが、ブラウザを登録したトレーナーと違うと届かない）
4. 判定は、Claude が `notification_logs` の、そのメッセージの行（`dedup_key = 'message:<messageId>'`）の `status` と `detail` を読み取りで確かめて行う。ブラウザに出たかどうかは補助にとどめる（OS の集中モードなどでも出ない）
   - `sent`（`sent=1/1`）: 鍵が一致している（push サービスが VAPID の署名を受け付けた証拠）
   - `failed`: Edge Functions の Logs の `[WebPush] Error sending notification` の `statusCode` を見る。`403` なら鍵の不一致
   - `skipped` / `no_tokens`: `device_tokens`（トレーナーの `web_push`）が登録されていない
   - `skipped` / `disabled`・`quiet_hours`: 通知設定のため

**PR1 のロールバック**
- PR1 には migration が無いので、PR1 を revert してよい（2関数の再デプロイと、Web の Vercel デプロイの巻き戻しも要る）。一部だけ戻すなら、`.eq('user_type', userType)` の1行を外して2関数を再デプロイする
- 購読の登録 API の変更を戻しても、すでに消えた他のトレーナーの行は戻らない（その人が設定画面を開けば自動で登録し直される。§7.2）
- PR1 の Web を戻すと、設定画面の自動の登録し直し・鍵の照合も戻る（`sw.js` は PR1 では変わらない）

### 11.2 PR2（朝のまとめ）

前提: PR1 が `develop/1.0.0` に入り、手順0 の確認が済んでいること。

**リリース（オーナー作業。順序どおり）**
1. PR を `develop/1.0.0` へマージ
2. develop から `supabase migration list --linked` と `supabase db push --dry-run` で未適用が `20261004000000` の1本だけであることを確かめ、`supabase db push`
3. 関数のデプロイ: `supabase functions deploy notify-trainer-alerts` だけ（`parse-message-tags` と `send-session-reminders` は PR1 で `user_type` の絞り込みを反映済み。PR2 の `push.ts` の変更（`client_alert` の種別・`ttlSeconds`・`timeout`）はこの2関数の動きに必須ではないので、再デプロイは要らない。次に再デプロイしたときに、メッセージ通知の Web Push にも `timeout` が効く。デプロイの後に `supabase functions list` で更新時刻を確かめる）
4. dry run: SQL エディタから `net.http_post` で `{"dry_run": true}` を送り、`net._http_response` で人数を確かめる。**`timeout_milliseconds := 60000` を付ける**（既定は 5000 ms で、読み取りの再試行が1回あるだけで超え、`timed_out = true` で結果が取れなくなる）。読み出しは `select status_code, timed_out, error_msg, content from net._http_response where id = <request_id>`。人数の突き合わせには §11.3 の SQL を使う。あわせて読み取りで確かめる: `trainers.fcm_token IS NOT NULL` の件数（残っていると、`web_push` が無いトレーナーが FCM に落ちる。§9）
5. Web（sw.js・通知設定・「今朝」の目印）を main へリリース（時期はオーナー判断）。sw.js は、ブラウザが更新を確かめたとき（ページの読み込み・push の受信）に入れ替わる。**デプロイ前から開いていたタブは、一度リロードする**（古いバンドルのままだと、`notification-clicked` を受けても取り直さない）。ブラウザ通知を使いたいトレーナーには、設定画面でプッシュ通知をオンにしてもらう（すでに購読済みのブラウザは、設定画面を開くだけで登録し直される。§7.2。設定画面を開かない人は宛先なしのまま）
6. 本番での確認用の対象日 D を決める（新しいアラートがある日が無ければ、実測の `2026-10-01`）。確かめること:
   - 対象のアラートの `trainer_id` が、手順0でブラウザを登録したトレーナーの ID と一致すること（読み取りの SQL で確かめる。§11.3）
   - `{"dry_run": true, "target_date": "<D>", "trainer_id": "<そのトレーナー>"}` で、`digests` にそのトレーナーが入っていて、`alreadyLogged` が 0 であること
   - 新しい `sw.js` が有効なこと（DevTools の Application → Service Workers で `SW_VERSION`）。旧版のままだと、通知は出てもクリック先が `/message` になり、成功条件2を確かめたことにならない
   - 同じブラウザで複数のトレーナーを切り替えて試したときは、最後に登録したトレーナーが宛先になる（§7.6）
   - **一致するトレーナーが `digests` に入らない場合は、手順7 の本送信をしない**。cron の有効化（手順8）まで進め、最初の自然なアラートの日に手順9 で確認する（他のトレーナーに古い日付のまとめを送り、その人の D のキーを使い切ってしまわないため）
7. 本番で1回だけ本送信（`{"dry_run": false, "target_date": "<D>", "trainer_id": "<そのトレーナー>"}`。**`trainer_id` を付けて1人に絞る**）→ ブラウザに届く・クリックでダッシュボードが開く・`notification_logs` が `sent`。D のそのトレーナーの dedup キーは、これで使い切る。結果が `failed` / `skipped` / `pending` で、鍵や設定を直したあとにやり直すときは、§11.3 の救済（そのトレーナーの dedup キー1行の DELETE）をしてから、同じ D で再実行する。`outcome.skippedBy` で、VAPID 未設定（`vapid`）と、宛先なし・設定オフを見分ける
8. cron を有効化: `SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'notify-trainer-alerts'), active := true);`
9. 翌朝 06:10 以降に確かめる。**`net._http_response` は 6 時間（`pg_net.ttl` の既定）で消える**ので、12:10 JST までに読む。それ以降は Edge Functions の Logs と `notification_logs`（`dedup_key` が `client_alert_digest:%` の行）で確かめる
   - `content` を読む（`content::jsonb ->> 'dryRun'` など）: `dryRun` が `false`、`detectionReady` が `true`、`outcome` の件数。**`status_code = 200` だけで判断しない**（body が欠けた cron は dry run の 200 になり、検知が未完了の日も 200 で何も送らない）
   - 件数が 0 でも、`detectionReady: true` かつ `trainerCount: 0` なら正常（新しいアラートが無い日）。`notification_logs` に行が無いだけでは、実行されなかった日と区別できない
   - 期待値: 登録済みの人数ぶんだけ `sent`、未登録は `skipped` / `no_tokens`（設定画面でオンにしていないトレーナー・iPhone だけで使うトレーナー・購読が失効したトレーナーは、正常に `no_tokens` になる。§13-14）

**手順5より前の挙動**: 本番の sw.js は古いままなので、通知のクリック先が `/message` になり、tag も `default` のまま（メッセージ通知と上書きし合う）。通知設定に「アラート」の切り替えもまだ出ない（既定はオン）。このため、本送信と cron の有効化は手順5の後にする。鍵の対応は PR1 の手順0（メッセージの通知）で確かめ済みのはず。

**PR2 のロールバック**
- 通知を止める: cron を無効にする（`active := false`）。関数は呼ばれなければ何もしない
- PR2 は migration を含むので revert はしない（適用済みの migration ファイルまで消え、以後の `db push` が止まる）。戻すときは新しいコミットで直す。migration ファイルは消さない
- `sw.js` に不具合があり通知が出ないとき: Vercel で直前のデプロイへ戻す。ブラウザが旧版に戻るのは次の更新確認（ページの読み込み・push の受信）の後なので、戻ったことを DevTools の `SW_VERSION` で確かめる
- CHECK に `client_alert` が残っても害は無い。消すなら先に `kind = 'client_alert'` の行を消してから CHECK を戻す

### 11.3 運用の手順（オーナー作業。本番への書き込みは Claude が行わない）
手順書（`docs/tasks/2026-07-10-cron-vault-setup.md` の `notify-trainer-alerts` の節）に載せる。

**人数の突き合わせ（読み取り）**: D の新しいアラートがある担当顧客の最重大度を、トレーナー別に数える。`digests` の `high` / `medium` / `low` と一致すること。手順6 では、ここで対象のアラートの `trainer_id` も確かめる

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

**送り直し**
- 検知が遅れて成功した日（`detectionReady: false` だった日）: 検知が成功したあとで、その D を `target_date` に指定して手動で送る（`{"dry_run": false, "target_date": "<D>"}`）。`detectionReady: false` の日はキーを使っていないので、そのまま送れる
- `failed` / `skipped` / `partial` / `pending` の行を作り直すとき: オーナーが、そのトレーナーの dedup キー**1行だけ**（`dedup_key` の完全一致）を消してから、同じ D で再実行する。他の行を巻き込まない

```sql
delete from public.notification_logs
where dedup_key = 'client_alert_digest:<trainer_id>:<D>';
```

- 消してから再実行すると、そのトレーナーにもう1通届く。手順7（1人に絞った本送信）のやり直しと、push サービスの一時障害（5xx）の日の送り直しに使う。送る前に、`trainer_id` を付けた dry run で `alreadyLogged` が 0 になったことを確かめる

## 12. 触るファイル

| PR | 層 | ファイル | 内容 |
|---|---|---|---|
| 1 | Web | `fit-connect/src/lib/supabase/savePushSubscription.ts` | §7.6（`device_tokens` を主に・同じ endpoint の他のトレーナーの行を消す・旧表は失敗しても応答を失敗にしない） |
| 1 | Web | `fit-connect/src/lib/notifications/pushSubscriptionKey.ts`（新規）、`fit-connect/src/lib/notifications/syncPushSubscription.ts`（新規）、`fit-connect/src/components/settings/NotificationSection.tsx` | §7.2（購読の登録し直し・鍵の照合・失敗の表示） |
| 1 | Edge | `supabase/functions/_shared/push.ts` | §6.3（`user_type` の絞り込み） |
| 1 | Web テスト | `fit-connect/src/lib/notifications/pushSubscriptionKey.test.ts`（新規）、`fit-connect/src/lib/notifications/syncPushSubscription.test.ts`（新規）、`fit-connect/src/lib/supabase/savePushSubscription.test.ts`（新規） | §10.3 |
| 1 | Docs | `docs/tasks/2026-07-19-webpush-vapid-setup.md`（Vercel に `VAPID_PRIVATE_KEY` は不要で、`fit-connect/src` に参照が無い。秘密鍵の正本の置き場は Edge Functions の secrets と別の保管先。鍵を変える順序 §7.2。手順0の判定 §11.1。確認先は `device_tokens`）、`fit-connect/docs/SETUP_PUSH_NOTIFICATIONS.md`（環境変数の表の `VAPID_PRIVATE_KEY`・確認先の `push_subscriptions` → `device_tokens`・ブラウザ終了時の挙動・削除済みの `/api/push-notify` 前提を今の経路に直す）、`fit-connect/docs/tasks/IMPLEMENTATION_TASKS.md`（Web 固有の通知の旧い記述） | — |
| 2 | DB | `supabase/migrations/20261004000000_client_alert_push.sql`（新規） | §8 |
| 2 | DB テスト | `supabase/tests/client_alert_push_test.sql`（新規）、`supabase/tests/cron_jobs_test.sql` | §10.2 |
| 2 | Edge | `supabase/functions/_shared/client_alert_digest.ts`（新規）、`_shared/client_alert_digest_test.ts`（新規） | §5.4・§10.1 |
| 2 | Edge | `supabase/functions/notify-trainer-alerts/index.ts`（新規）、`supabase/config.toml` | §5 |
| 2 | Edge | `supabase/functions/_shared/web_push_options.ts`（新規。`buildWebPushOptions`）、`_shared/web_push_options_test.ts`（新規）、`supabase/functions/_shared/push.ts` | §6.1・§6.2（`client_alert` の種別・`ttlSeconds`・`timeout`）・§10.1 |
| 2 | Web | `fit-connect/public/sw.js`、`fit-connect/src/lib/notifications/notificationKinds.ts`（新規）、`fit-connect/src/components/settings/NotificationSection.tsx`、`fit-connect/src/components/dashboard/TriageSection.tsx`、`fit-connect/src/app/(user_console)/layout.tsx` | §7.1・§7.2（種別）・§7.3 |
| 2 | Web | `fit-connect/src/components/dashboard/TriageRow.tsx`、`fit-connect/src/lib/triage/surfacedToday.ts`（新規） | §7.5 |
| 2 | Web テスト | `fit-connect/src/lib/notifications/notificationKinds.test.ts`（新規）、`fit-connect/src/lib/notifications/sw.test.ts`（新規。`public/sw.js` をファイルとして読み込む。vitest の既定の include で拾われる）、`fit-connect/src/lib/triage/surfacedToday.test.ts`（新規） | §10.3 |
| 2 | Docs | `docs/tasks/2026-07-10-cron-vault-setup.md`（`notify-trainer-alerts` の節: dry run（`timeout_milliseconds := 60000`）・有効化・停止・§11.3 の SQL・翌朝の確認の期限と読み方。「push 通知は送りません（VAPID 設定後の後続タスク）」の記述も直す）、`docs/tasks/2026-09-13-trainer-intervention-plan.md`（通知の節のほか、L5「VAPID が済むまで着手しない」・L85「当面は送らない」・L132/L145 の拡張の列挙・L299/L569「cron 失敗監視は push と一緒に作る」・L371「後で足す手順」・L554/L564 の注意と優先順を、本書の決定に合わせる。行は 2026-10-04 時点）、`docs/tasks/IMPLEMENTATION_TASKS.md`（L40 の 9.1 の push・睡眠悪化の「リモート適用待ち」→ 適用済み、L496 の決定③と「Phase 9 では送らない」、L507 の「push は VAPID と APNs キーの設定待ち」。トレーナーの Web Push は APNs と無関係）、`docs/tasks/lessons.md` | — |

## 13. 前提として決めたこと（オーナーが覆せる）
1. 送る時刻は 06:10 JST（自動チェックの10分後）。ブラウザが閉じていても、開いたときに届く。10分は 06:00 の自動チェックが終わっていることへの余裕で、終わっていなければ送らない（`detectionReady: false`。この日のキーは使わず、あとから手動で送れる。§11.3）
2. 有効期限は12時間
3. 未返信はまとめに含めない（メッセージは届くたびに別の通知が出る）
4. 「アラート（朝のまとめ）」の既定はオン
5. クリック時は同じパス名のタブを前面に出すだけで、移動しない（書きかけを消さない）。別のパスのタブは動かさず、新しいタブを開く
6. 過去の対象日を手動で指定して送れる（本番での確認・送り直し用）。未来は拒否
7. 有効期限は Web Push だけに効かせ、FCM には渡さない
8. 種別名は `client_alert`、dedup キーは `client_alert_digest:<trainer_id>:<D>`（将来アラートごとの通知を足すときは `client_alert:<alert_id>:<surfaced_on>` を使える）
9. 通知の tag は種別ごと（朝のまとめは日ごと）にし、`renotify: true` を付ける。メッセージの通知も、2通目以降を無音で差し替えずに知らせるようになる（今は全通知が tag `default` で無音の差し替え）。ただし全顧客・全会話のメッセージ通知は tag `message` の1枚に潰れる（今の `default` と同じ）ので、本文は最後の1通だけ残り、連投すると連投の数だけ鳴る。連投が気になるときは、`renotify` を `data.tag` を持つ種別（朝のまとめ）だけにして、メッセージは従来の無音の置き換えのまま「種別をまたいで上書きしない」ことだけを得る選択もできる（§14）。メッセージの挙動の確認は §10.6
10. 古い公開鍵で作られたブラウザの購読は、設定画面を開いたときに解除してトグルをオフに戻し、もう一度オンにしてもらう。自動解除は PR1 に含める（PR1 は revert できる。分岐は `syncPushSubscription` の単体テストで固める。§7.2）
11. 通知の重大度は「今朝新しく出たアラート」だけで決める。一覧の行のバッジ（全 open の最重大）とは違うことがあり、一覧の理由に付ける「今朝」の目印で補う（§4.3・§7.5）
12. 購読は最後に登録したトレーナー1人のもの（同じ endpoint の他のトレーナーの行は登録時に消す）。ログアウト時にサーバーの行を消すことはしない（§7.6）
13. PR は2本に分ける。PR1 = Web Push の土台（既存の通知の挙動を直す）、PR2 = 朝のまとめ本体（§15）
14. 通知が届く範囲は、ブラウザ通知を登録した人だけ。設定画面が案内するブラウザ（Chrome・Edge・Firefox の最新版）が対象で、iPhone・iPad の Safari は、ホーム画面に追加した Web アプリでないと Web Push が使えず、fit-connect には `manifest` が無いので対象外。本番のトレーナーの `web_push` は0名なので、リリース直後は、設定画面でオンにした人だけが受け取る。購読が失効した（404 / 410）人は、`push.ts` に掃除されて `no_tokens` になる（§11.2 手順9 の期待値）
15. 「1通」はトレーナー単位の dedup。ブラウザを登録した端末ごとに1通届く（PC とノート PC の両方で購読していれば2通）
16. 再送用の2つ目の cron スロット（06:40 など）は採らない。救えるのは `detectionReady: false` の日と `failed / resolve_error` の行だけで、push サービスの一時障害（5xx）の `failed` は救えない。手動の送り直し（§11.3）で足りる規模（トレーナー5名）で、監視の PR で再検討する（§14）
17. 契約状態・プランでは絞らない（ダッシュボードの検知・表示と同じ）。退会したトレーナーは `device_tokens` / `alerts` が cascade で消えるので送られない
18. 旧 `trainers.fcm_token` への後戻りは変えない（stage3 で廃止。§9）
19. 想定規模はトレーナー数十人まで。送信は逐次で、1人あたり 0.5〜1.5 秒（概算。実測していない）。pg_net の応答枠 60 秒を超えると `timed_out` になるが、関数は走り続ける。超える規模になったら、並列化か分割を検討する（§14）
20. 手動の確認・送り直し用に、任意の `trainer_id`（1人に絞る）を受け取る。cron は付けない（§5.1）
21. 宛先 URL の検査は本書では入れない（§14）

## 14. 範囲外・拡張候補
- cron 失敗の監視（判断7-3）— **直後の PR**。HTTP で動く cron は失敗しても `job_run_details` が succeeded になり、`net._http_response` も既定で6時間しか残らないため、関数側で結果を記録する仕組みから設計する。06:00 の自動チェックが D に成功していないこと（本書の `detectionReady: false`）もそこで知らせる
- アラートごとの個別通知、未返信をまとめに含めること
- 静かな時間帯の設定 UI
- 顧客詳細の `?tab=` のクエリ追従（個別通知を作るときに必要）
- メッセージ通知のクリックで、その顧客の会話を開くこと（`parse-message-tags` の `data` に `url` を足す）
- `pushsubscriptionchange`（ブラウザが購読を作り直したときの自動更新）
- トレーナーの「目標達成のお知らせ」トグル（実際の送信先は顧客で、トレーナー宛には何も送られていない）の整理
- `push_subscriptions` 表と両書きの廃止（判断1 の移行 stage3）
- FCM→APNs の不達（APNs 認証キーの問題）
- ログアウト時にサーバーの購読の行を消すこと（`signOut` を呼ぶのが設定画面のログアウトボタンだけで、セッション切れでは走らない。§7.6）
- 新着の行を上位に寄せる並び替えと、上位5件の外にある「今朝」の行の知らせ方（§7.5）
- 再送用の2つ目の cron スロット（06:40 など）。監視の PR で、検知が遅れた日の自動の回復として検討する（§13-16）
- `fetchNotificationLogs` / `isResendable` の `_shared` への切り出し（`send-session-reminders` と共有する。§5.4）
- Web Push の宛先 URL の検査（`https` と、既知の push サービスのホストに限る）と、`device_tokens` の RLS の絞り込み（顧客が任意の `platform` / `token` を書ける）。既存の問題で、本書で悪化はしない。`push.ts` で検査すると §10.4 の通しの確認（127.0.0.1 の受け口）と衝突するので、本書では `timeout`（§6.2）で被害を時間で打ち切るだけにする。直すなら、RLS の `WITH CHECK` か migration での `token` の検査として別の変更にする。購読の鍵データが不正で、`web-push` が送る前に例外にする行の掃除（今は `failed` のまま残る）も、同じ変更で扱う
- メッセージ通知を会話ごとの tag にすること（`parse-message-tags` の `data` に送信者を入れる。クリック先 URL の変更と同じ時期。§7.1）。`renotify` を `data.tag` を持つ種別（朝のまとめ）だけにして、メッセージは従来の無音の置き換えのままにする選択（§13-9）
- ダッシュボードにプッシュ通知の有効化の案内を出すこと、失効した購読をトレーナーに知らせること（§13-14）
- 送信の並列化・打ち切り（トレーナーが数十人を超える規模になったら。§13-19）

## 15. PR の分割

1本の PR に、既存の通知の挙動の変更（`user_type` の絞り込み・購読の登録 API・購読の自動解除）と新機能（朝のまとめ）が混ざると、レビューもロールバックも重くなる（朝のまとめには migration があり、PR を revert できない。§11.2）。2本に分け、PR1 は DB の変更が無いので単独で revert できるようにする。

| | PR1 Web Push の土台 | PR2 朝のまとめ |
|---|---|---|
| ブランチ | `feature/web-push-foundation`（`develop/1.0.0` から） | `feature/trainer-alert-push`（PR1 のマージ後に `develop/1.0.0` を取り込む） |
| 入るもの | §6.3（`user_type` の絞り込み）、§7.2 の購読の登録し直し・鍵の照合・失敗の表示、§7.6（購読の所有者・登録 API の失敗の扱い） | §3〜§5（通知・Edge Function）、§6.1・§6.2、§7.1（`sw.js`）、§7.2 の通知設定の種別、§7.3、§7.5（「今朝」の目印）、§8（migration・cron） |
| DB の変更 | なし | migration 1本（cron は無効で登録） |
| 既存の通知への影響 | あり（宛先の絞り込み・登録 API の挙動・古い鍵の購読の自動解除） | `sw.js` のクリック先・tag・renotify（メッセージ通知にも及ぶ。§13-9） |
| 確かめること | 手順0（鍵の対応）とメッセージ通知の回帰（§11.1） | §10.1〜§10.5 |
| ロールバック | PR1 を revert してよい（2関数の再デプロイと Vercel の巻き戻しも要る） | cron の無効化。revert はしない（§11.2） |

- PR2 は PR1 に依存する。成功条件6（顧客用スマホにトレーナー向けの通知が届かない）と条件8の前提が PR1 で入るため、PR1 が `develop/1.0.0` に入り手順0 が済むまで、PR2 のリリース（§11.2）は始めない
- 実装とレビューは並行してよい。ただし両方が `push.ts` と `NotificationSection.tsx` を触るので、先に出す PR1 を `develop/1.0.0` に入れてから PR2 に取り込む
- 本書は PR1 に載せて先に `develop/1.0.0` へ入れる（PR2 の実装者も参照できる）。ブランチの切り方（本書のコミットをどちらに載せるか）は、実装を始めるときに決める
