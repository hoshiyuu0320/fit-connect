# フェーズ8.3② セッション前日リマインダー — 実装計画（確定版）

**作成**: 2026-09-12 / ブランチ: `feature/session-reminder`
**出典**: `2026-07-08-solution-catalog.md` cat4 課題3（MVP = 前日 20:00 顧客宛のみ・固定時刻・設定なし）、
`2026-07-10-integration-decisions.md` 読み替え表（`clients.fcm_token` → `device_tokens` をディスパッチャ経由 / `reminder_sent_at` 列 → `notification_logs.dedup_key`）
**前提（2026-09-12 時点で解消済み）**: Vault に `project_url` / `secret_key` 登録済み、cron 3本 active。cron→Edge Function の認証は PR #84 の `apikey` 方式

## 実測した前提

- ディスパッチャ `_shared/push.ts` の `sendNotification(args)`: `{ supabaseAdmin, userId, userType, kind, title, body, data?, dedupKey }`。**戻り値 void・例外を外に出さない**（結果は `notification_logs.status/detail`）
- 冪等化は `notification_logs.dedup_key` の UNIQUE + upsert ignoreDuplicates。設定 OFF / quiet hours / トークン無しで skip した場合も行が残るため**同一キーの再送は永久に不可**
- `kind` は3箇所で列挙されている: `push.ts` の TS ユニオン / `notification_preferences.kind` の CHECK（`'message','goal_achievement'`）/ Mobile の `NotificationKind` enum。**CHECK 拡張 migration が無いと Mobile のトグル upsert が check_violation で落ちる**
- 設定はオプトアウト方式（行が無ければ有効）。quiet hours は JST 固定・該当時は**捨てる**（遅延しない）。UI から quiet hours を設定する導線は現状無い
- 宛先は `device_tokens` を `user_id` で全件 → 0件なら `clients.fcm_token` へフォールバック。`sessions.client_id` は `auth.users.id` と同一なのでそのまま `userId` に渡せる
- Mobile のタップ処理は `data['type']` と **`data['id']`** しか読まない（既存送信は messageId/clientId を送っているため id は常に null）。受け口 `app.dart` の `onNotificationTap` は print のみの空実装
- 通知タップでアプリを開けば、ホームの `NextSessionCard` が resumed 時に再取得されるため**ディープリンク無しでも次回セッションが見える**（別タブを開いたままバックグラウンド化した場合はそのタブに復帰する）
- pg_cron は UTC。**20:00 JST = `0 11 * * *`**
- `dry_run` の既定が関数間で不統一（auto-skip: 既定実行 / cleanup: 既定 dry）。**push を伴う本関数は cleanup 方式（既定 dry run、cron は `{"dry_run": false}` を明示）**

## 設計判断

1. **MVP は「前日 20:00 JST に顧客へ push」の1本のみ**。2時間前・トレーナー朝サマリ・設定 UI（時刻変更）は拡張
2. **通知種別 `session_reminder` を新設**し、通知設定センター（Mobile）のトグル対象にする（通知ガバナンス: 横断レビュー 1-3）。Web はトレーナー側なので変更なし
3. **dedup_key は `session_reminder:<session_id>:<対象日 YYYY-MM-DD(JST)>`**。別日へリスケされたら再送される（同日内の時刻変更は再送しない = 仕様）
4. **対象抽出は SQL 関数 `find_sessions_for_reminder(target_date date)`** に寄せる（`find_orphan_ai_images` と同型: SECURITY DEFINER・search_path 固定・EXECUTE は service_role のみ）。JST 暦日「明日」の判定は**範囲比較**で書き `idx_sessions_session_date` を効かせる
5. **cron は inactive で登録**し、リモートで dry run → オーナーが有効化（#84 の運用と同じ。初回から実顧客に push が飛ぶため dry run を必ず挟む）
6. **data ペイロードは `{ type: 'session_reminder', id: <session_id> }`**（Mobile が読むキー名に合わせる）。タップ時のタブ切替（ホーム強制）は MVP では実装しない
7. `push.ts` の変更は `kind` ユニオンへの追加のみ（型レベル）。既存 Function の再デプロイは不要

## 契約（レーン間で共有。変更時は全レーンに周知）

### SQL 関数

```sql
find_sessions_for_reminder(target_date date DEFAULT ((now() AT TIME ZONE 'Asia/Tokyo')::date + 1))
RETURNS TABLE (
  session_id uuid, client_id uuid, trainer_id uuid, trainer_name text,
  session_date timestamptz, duration_minutes integer, session_type text, target_date date
)
```
- 条件: `status IN ('scheduled','confirmed')` かつ `session_date` が `target_date` の JST 暦日内（`>= target_date 0:00 JST` かつ `< target_date+1 0:00 JST`）
- `trainer_name` は `trainers.name`（通知本文用）。並びは `session_date` 昇順
- 同一顧客に同日複数セッションがあれば**複数行**返す（それぞれ別セッションとして通知。dedup_key が session_id を含むため重複しない）

### Edge Function `send-session-reminders`

- 認証: `isServiceRequest(req)` でなければ 401
- body `{ dry_run?: boolean, target_date?: 'YYYY-MM-DD' }`。`dry_run` **省略時 true**。dry run では `target_date` 省略可（SQL 関数の既定 = JST の明日）
- **本送信（`dry_run: false`）では `target_date` 必須**（省略・不正形式は 400）。cron は `to_char((now() AT TIME ZONE 'Asia/Tokyo')::date + 1, 'YYYY-MM-DD')` を body に入れて渡す（migration `20260913000100`）。
  理由（レビューで確定）: 関数既定に任せると JST 0:00 以降の手動再実行が翌々日を対象に本送信し、正規 cron が dedup で全件スキップされる
- 処理: `rpc('find_sessions_for_reminder', { target_date })` → 各行を `sendNotification({ userId: client_id, userType: 'client', kind: 'session_reminder', title, body, data: { type: 'session_reminder', id: session_id }, dedupKey: 'session_reminder:' + session_id + ':' + target_date })`
- 文面: title `明日のセッションのお知らせ` / body `9月13日(土) 18:00 から <trainer_name> トレーナーとのセッションがあります`（日時は JST で整形。曜日は日本語1文字）
- 返却: `{ status:'ok', dryRun, targetDate, candidateCount, candidates:[...] }`。本送信では加えて `outcome: { sent, partial, skipped, failed, duplicate }`（`notification_logs` を今回の dedup_key 群で集計。`sendNotification` は結果を返さないため「呼んだ回数」ではなく実結果を返す）
- 型の罠: `push.ts` は `https://esm.sh/@supabase/supabase-js@2` の `SupabaseClient` 型を要求する。`jsr:` の `createClient` を渡すと型不一致になり得るため、`parse-message-tags` と同じく esm.sh の `createClient` を使う（`// @ts-nocheck` は使わない）

### Mobile

- `NotificationKind.sessionReminder`（value `'session_reminder'`、表示名「セッションリマインダー」、説明「前日の夜にお知らせします」）

## タスク分割

### レーンA: Supabase（migration / cron / 共有型 / SQL テスト / 手順書）

1. `supabase/migrations/20260913000000_session_reminder.sql`
   - `notification_preferences` の `kind` CHECK を `('message','goal_achievement','session_reminder')` に拡張（`DROP CONSTRAINT IF EXISTS notification_preferences_kind_check` → `ADD CONSTRAINT`。制約名は実 DB で確認）
   - `find_sessions_for_reminder` を上記契約どおり作成。`REVOKE ALL FROM PUBLIC/anon/authenticated` + `GRANT EXECUTE TO service_role`。`COMMENT ON FUNCTION`
   - cron ジョブ `send-session-reminders`: `0 11 * * *`、`net.http_post(url := Vault project_url || '/functions/v1/send-session-reminders', headers := {'Content-Type','application/json','apikey': Vault secret_key}, body := '{"dry_run": false}'::jsonb)`。jobname 存在チェック → 登録直後に `cron.alter_job(active := false)`。書式は `20260912000000_cron_use_secret_key.sql` と `20260829000300` を踏襲
2. `supabase/functions/_shared/push.ts`: `kind` ユニオンに `'session_reminder'` を追加（それ以外は触らない）
3. `supabase/config.toml`: `[functions.send-session-reminders] verify_jwt = false`
4. `supabase/tests/session_reminder_test.sql`（`sessions_rls_test.sql` / `notification_prefs_logs_rls_test.sql` の構造を踏襲）
   - (a) JST 暦日の境界: 対象日 23:30 JST は含む / 対象日 0:00 JST は含む / 前日 23:59 JST と翌々日 0:00 JST は含まない（**UTC 日付で判定すると壊れる時刻を必ず含める**）
   - (b) `cancelled` / `completed` は除外、`scheduled` / `confirmed` は対象
   - (c) `authenticated` ロールからは EXECUTE 拒否（service_role は可）
   - (d) `notification_preferences` に `kind='session_reminder'` を INSERT できる。未知の kind は check_violation
5. `docs/tasks/2026-07-10-cron-vault-setup.md` に新ジョブの dry run SQL と有効化 SQL を追記（#84 が整えた書式に合わせる）

### レーンB: Edge Function

1. `supabase/functions/send-session-reminders/index.ts` を契約どおり新設（雛形: `auto-skip-workouts`（認証・dry_run・返却）+ `parse-message-tags`（esm.sh createClient・sendNotification 呼び出し））。各 `sendNotification` は try/catch で包み、1件の失敗で全体を止めない
2. 日時整形を純関数 `formatSessionReminderBody(sessionDate, trainerName)`（JST 固定・`_shared/quiet_hours.ts` の JST_OFFSET と同じ扱い）に切り出し、`supabase/functions/_shared/` に置く。**Deno 単体テスト**（`quiet_hours_test.ts` の形式）で「UTC 日付と JST 日付が異なる時刻」「曜日」「trainer_name 空」を検証
3. 構文確認: `deno` が無ければ `fit-connect/node_modules/.bin/tsc --noEmit --noResolve --skipLibCheck --target es2022 --module esnext`（8.2 と同じ手法）。Deno テストは `npx -y deno test <file>` で実行

### レーンC: Mobile

1. `NotificationKind.sessionReminder` を追加（enum / State フィールド / build の switch / setEnabled の switch / 設定画面のトグルの5箇所。網羅 switch なので漏れはコンパイルで検出される）
2. 設定画面の通知セクションにトグル行を追加（既存2件と同じ見た目。@Preview 更新）
3. `notification_service.dart`: `data['id']` の扱いは現状のまま（送信側でキー名を合わせる方針）。変更不要なら触らない
4. テスト: 通知設定 provider の既存テストがあれば新種別を追加。無ければ「3種別の初期値が有効 / setEnabled で該当種別だけ変わる」の小さなテストを追加
5. 検証: `dart run build_runner build --delete-conflicting-outputs` → `flutter analyze`（エラー0）→ `flutter test`

### 統合（マネージャー）

1. ローカル `supabase db reset` + テスト7本（既存6 + 新規）
2. `supabase db push` → `supabase functions deploy send-session-reminders`
3. リモートで `SELECT * FROM find_sessions_for_reminder();` により候補を確認（MCP は読み取りのみ可）。Edge Function の dry run 実行はオーナー（手順書の SQL）
4. `IMPLEMENTATION_TASKS.md` 8.3② 更新・lessons 追記。**L382 付近の「Vault 登録待ち」表記は陳腐化しているので直す**

## 既知のリスク・拡張候補

- **通知タップでホームに強制遷移しない**（別タブを開いたままだとそのタブに復帰）。`onNotificationTap` は空実装のまま。拡張1で `type=='session_reminder'` のときホームタブへ切替
- コールドスタート時の `getInitialMessage` と `onNotificationTap` 設定順の競合（既存問題）。MVP では影響なし（遷移処理が無いため）
- iOS フォアグラウンドでの二重表示の可能性（既存挙動。実機で要確認）
- 2時間前リマインダー・トレーナー朝サマリ・時刻設定 UI は拡張（cron を15分間隔に変える設計はその時点で）
