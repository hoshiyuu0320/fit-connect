# 睡眠悪化アラート（フェーズ9.1 拡張 ③ `sleep_decline`）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 毎朝 06:00 JST の既存の自動チェックで睡眠の悪化（睡眠時間の短縮・目覚め評価の低下）を `sleep_decline` アラートとして検知し、「今日の対応」から睡眠タブと「直近7日の睡眠」を引用したメッセージ画面に一手で移れるようにする。

**Architecture:** Supabase 側は既存の `evaluate_client_alerts` に睡眠の CTE と3本目の `UNION ALL` を足し、`run_client_alert_detection` に睡眠の期限切れと `stats.detected.sleep_decline` を足す（migration 1本。先頭のドリフトガードと末尾の権限検査で挟む）。Web 側は純関数 `describeAlert` が payload から文言・タブ・引用の参照（`messageRef`）を決め、`buildTriageRows` が先頭の理由の参照を行に載せ、`TriageRow` は表示するだけにする。SQL と Web は payload の形（設計書 §4.6）だけでつながる。

**Tech Stack:** PostgreSQL 15 / PL/pgSQL（Supabase ローカル、psql を `docker exec`）、Supabase CLI（隔離スタックの `db reset` だけ）、Next.js 15（App Router）・TypeScript・Tailwind CSS・lucide-react・vitest・pnpm 10.32.1

**Spec:** `docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md`

**実施順:** Task 1 → 2（SQL）→ 3 → 4 → 5（Web）→ 6（ドキュメント）→ 実装後の確認。Web の Task は SQL に依存しない（payload は合成データでテストする）が、レビューの順序をそろえるためこの順に進める。

## 作業場所とコマンド

- worktree: `/Users/hoshidayuuya/Documents/FIT-CONNECT/.claude/worktrees/sleep-decline-alert`（ブランチ `feature/sleep-decline-alert`、`develop/1.0.0` から作成）
- コミットは worktree のルートから行う
- `.env` / `.env.local` は読まない

### SQL（Task 1・2）

コマンドはすべて **worktree のルート**から実行する。

```bash
SP=/private/tmp/claude-501/-Users-hoshidayuuya-Documents-FIT-CONNECT/ab68eea9-a74a-49fb-b328-1a51c801b004/scratchpad
```

- テストだけを流す（今のスタックに対して）:
  ```bash
  docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/sleep_decline_alert_test.sql
  ```
- migration を適用してから流す（migration を変更するたびに、scratch のスタックを作り直す）:
  ```bash
  rsync -a --delete supabase/migrations/ $SP/sleep-stack/supabase/migrations/
  (cd $SP/sleep-stack && supabase db reset)   # 隔離スタック fitconnect-sleep101 だけが作り直される。リポジトリ内で実行しないこと
  docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/sleep_decline_alert_test.sql
  ```
- **`supabase db reset` は必ず `$SP/sleep-stack` の中で実行する。worktree やリポジトリのルートでは絶対に実行しない**（ルートの `supabase/config.toml` は共有スタック `fit-connect` を指しており、他のセッションの DB が消える）。`supabase start` / `supabase stop` も実行しない
- **共有スタック `supabase_db_fit-connect` には接続・書き込みしない**
- migration の先頭にドリフトガードがあるので、同じ DB に2回は流せない（2回目は `ERROR:  REMOTE_DRIFT_SINCE_CAPTURE` で止まる）。psql で migration を直接流し直さず、必ず上の `rsync` → `db reset` で作り直す

### Web（Task 3〜5）

テスト・型・lint・build は **`fit-connect` ディレクトリから**実行する（依存パッケージは worktree の `fit-connect/node_modules` に入っている）。

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/.claude/worktrees/sleep-decline-alert/fit-connect
```

- 対象ファイルだけのテスト: `npx -y pnpm@10.32.1 exec vitest run <path>`
- 全体のテスト: `npx -y pnpm@10.32.1 test`
- 型: `npx -y pnpm@10.32.1 exec tsc --noEmit`
- lint: `npx -y pnpm@10.32.1 lint`
- build: `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 NEXT_PUBLIC_SUPABASE_ANON_KEY=dummy SUPABASE_SERVICE_ROLE_KEY=dummy npx -y pnpm@10.32.1 build`

## Global Constraints

- コミットのメッセージは日本語、末尾に空行を挟んで `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。push 前にマネージャーが `git reset --soft` で1コミットにまとめる
- migration は1本だけ: `supabase/migrations/20261003000000_alert_sleep_decline.sql`。Task 1 で作り、Task 2 で末尾に追記する
- ドリフトガードの期待値（`md5(prosrc)`）: `evaluate_client_alerts` = `9c553a939d98fb60d58022897f6a5d4c`、`run_client_alert_detection` = `0e80baea1335f09889edac7fc584836f`（2026-10-03 にローカルとリモートで一致を確認）
- 両関数とも `SECURITY DEFINER`・`SET search_path = ''`・テーブルと関数は完全修飾。REVOKE（PUBLIC / anon / authenticated）と GRANT（service_role）の4行を書く
- 判定の定数（設計 §4）: 窓 14日・直近 7日 / 睡眠時間 120〜960 分（両端を含む）/ 各窓 4 晩以上 / 成立 Δ ≤ −60 / 解消 Δ > −48（−60 × 0.8）/ 目覚め評価 3 回以上・成立 平均 < 1.5・解消 平均 ≥ 2.0 / 重大度 medium / 期限切れ `c_sleep_expire_days := 14`
- 中央値は `percentile_cont(0.5)` を `::numeric` にキャストしてから差・丸め。丸めは numeric の `round`（340.5 → 341、−59.5 → −60）。判定は丸める前の差で行う
- payload（v: 1）: `{v, triggers, recent:{from,to,median_minutes,nights}, previous:{from,to,median_minutes,nights}, delta_minutes, wakeup:{avg,count}, threshold:{drop_minutes,min_nights,wakeup_avg,min_ratings}}`。`severity_reason` は入れない。表示用の文字列は入れない
- 表示の文言は設計書 §6.1 の表のとおり（kindLabel・title「睡眠の悪化」、severityLabel「注意」、tab `sleep`、messageRef `{ kind: 'sleep_week' }`）。chip の符号は体重と同じ ASCII の `-`
- 分の表示は `formatSleepMinutes`（「H時間M分」）に**絶対値**を渡す。日付は既存の `M/d` の文字列処理（Date のローカル時刻に通さない）
- payload の検証は triggers にある条件に要る項目だけ。不正なら汎用の文言（例外を投げず、1件の不正で「今日の対応」全体を落とさない）
- `describeAlert` / `buildTriageRows` / `triageLabels` は React・`'use client'` に依存させない。`describeAlert` は全ページの layout から読まれるので date-fns を読むモジュールを経由させない
- 優先度スコアは変えない（medium = 10 点）。未返信がある行の「返信する」には引用を付けない
- アクセシブルな名前は顧客名（敬称は `clientHonorific`）と操作を入れ、見えている文字をそのまま含める
- UI: リンクの色 `#0F766E`・hover の背景 `#F0FDFA`・フォーカスは既存の `TRIAGE_FOCUS_RING`・角丸 `rounded-md`・`transition-colors`。影・グラデーションは使わない。アイコンは lucide-react で `aria-hidden`（マネージャーが実行した ui-ux-pro-max の指針）
- Mobile は変更しない（alerts を参照していない）

## Review Focus

仕様が暗に求めるのに、ふつうに使うと最初に引っかかりそうな入力・状態（多い順）。どれも下のタスクのテストで固定してある。

1. **顧客が自由に書ける異常値**（`recorded_date` が ±infinity、睡眠時間が負・0・integer の最大値）が1件あっても、全員分を1トランザクションで処理する本実行が落ちず、その晩を数えない → Task 1 のテスト case 10（顧客 28）
2. **到着遅れで直近の窓が3晩になる日**: 目覚め評価だけで解消せず、対応済みの行が閉じては開くことが無い → Task 1 のテスト case 15（顧客 24）
3. **未返信がある行で睡眠悪化が先頭の理由**: 「返信する」は引用なしのまま、引用は詳細のリンクから → Task 5 Step 8 の静的確認と実装後の画面確認
4. **登録直後で前の窓が空**（from が to より後）: SQL の payload が壊れず、Web が目覚め評価だけの文言で読める → Task 1 のテスト case 12・16、Task 3 の「wakeup だけ（前の窓が空）」のテスト
5. **監視対象から外れた顧客**（inactive など）の生きている `sleep_decline` が残り続けない → Task 2 のテスト case 20（顧客 53）

ほかに固定してあるもの: UTC より西のタイムゾーンでも比較期間がずれない（Task 3）、成立と食い違う payload（duration が triggers にあるのに Δ ≥ 0）は汎用の文言（Task 3）、先頭の睡眠悪化を対応済み → 元に戻すと引用が外れて付き直す（Task 4）、全ページの初回読み込み量が増えない（Task 3・4・5）。

## ファイル構成

| ファイル | 責務 | Task |
|---|---|---|
| `supabase/migrations/20261003000000_alert_sleep_decline.sql`（新規） | ドリフトガード・CHECK・列 COMMENT・`evaluate_client_alerts`・`run_client_alert_detection`・末尾の権限検査 | 1・2 |
| `supabase/tests/sleep_decline_alert_test.sql`（新規） | 睡眠悪化の evaluate / run / CHECK / 権限のテスト | 1・2 |
| `supabase/tests/client_alert_detection_test.sql` | 1顧客3行（case (e)）・stats のキー（case (j)） | 1・2 |
| `fit-connect/src/types/alert.ts` | `'sleep_decline'` と `SleepDeclinePayload` などの型 | 3 |
| `fit-connect/src/lib/sleep/formatSleepMinutes.ts`（新規） | 分 →「H時間M分」（依存なし。`sleepQuote.ts` が再 export） | 3 |
| `fit-connect/src/lib/sleep/sleepQuote.ts` | `formatSleepMinutes` を上のモジュールから再 export | 3 |
| `fit-connect/src/lib/alerts/describeAlert.ts`（+ test） | 睡眠悪化の文言・tab・messageRef／引用付きの「メッセージ」の href | 3・4 |
| `fit-connect/src/lib/message/recordQuoteLink.ts`（新規） | `RecordQuoteRef` の型と `recordQuoteHref`（依存なし。`recordQuoteRef.ts` が再 export） | 4 |
| `fit-connect/src/lib/message/recordQuoteRef.ts` | 型・リンクの組み立てを上のモジュールから再 export | 4 |
| `fit-connect/src/types/triage.ts` | 行の `messageRef` | 4 |
| `fit-connect/src/lib/triage/buildTriageRows.ts`（+ test） | 先頭の理由の messageRef を行に載せる | 4 |
| `fit-connect/src/lib/triage/triageLabels.ts`（+ test） | 引用付きのアクセシブルな名前・詳細のリンクの文字 | 4 |
| `fit-connect/src/lib/triage/triageListState.test.ts` | 対応済み → 元に戻すで引用が追随することの固定 | 4 |
| `fit-connect/src/components/dashboard/TriageRow.tsx` | 「メッセージ」の href・名前と、詳細のリンク | 5 |
| `docs/tasks/2026-07-10-cron-vault-setup.md` ほか3本 | 手順書・計画書・タスク表・学び | 6 |

---

### Task 1: 評価関数と CHECK

**Files:**
- Create: `supabase/migrations/20261003000000_alert_sleep_decline.sql:1-580`（ヘッダー・0 ドリフトガード・1 CHECK・2 列 COMMENT・3 `evaluate_client_alerts`）
- Create: `supabase/tests/sleep_decline_alert_test.sql:1-662`（第0部 CHECK の case 23・第1部 evaluate の case 1〜16）
- Modify: `supabase/tests/client_alert_detection_test.sql:631-637`（case (e)。評価が3行になるため）

**Interfaces:**
- Consumes:
  - `public.client_activity_snapshot(p_target_date date, p_as_of timestamptz, p_trainer_id uuid DEFAULT NULL) RETURNS TABLE (client_id uuid, trainer_id uuid, join_on date, purpose text, last_activity_on date, last_record_on date, exclusion_reason text)`（変更しない。監視対象 = `exclusion_reason IS NULL`）
  - `public.sleep_records (client_id uuid, recorded_date date, total_sleep_minutes integer NULL, wakeup_rating smallint NULL CHECK IN (1,2,3), source text CHECK IN ('manual','healthkit'), created_at timestamptz NOT NULL, updated_at timestamptz NOT NULL)`、UNIQUE `(client_id, recorded_date)`、CHECK `total_sleep_minutes IS NOT NULL OR wakeup_rating IS NOT NULL`
  - 今の `evaluate_client_alerts` / `run_client_alert_detection` の本体（`20260914000200` のまま。md5 は Global Constraints）
- Produces:
  - `public.evaluate_client_alerts(p_target_date date DEFAULT ((now() AT TIME ZONE 'Asia/Tokyo')::date), p_as_of timestamptz DEFAULT NULL) RETURNS TABLE (client_id uuid, trainer_id uuid, alert_type text, state text, severity text, payload jsonb)` — 監視対象1名につき3行（`weight_change`・`record_gap`・`sleep_decline`）。`sleep_decline` の行は `state` ∈ {`detected`,`cleared`,`unknown`}、`severity` は detected のとき `'medium'`・それ以外 NULL、`payload` は次の形（Web の `SleepDeclinePayload` が読む）:
    ```json
    {"v": 1, "triggers": ["duration", "wakeup"],
     "recent":   {"from": "YYYY-MM-DD", "to": "YYYY-MM-DD", "median_minutes": 330, "nights": 5},
     "previous": {"from": "YYYY-MM-DD", "to": "YYYY-MM-DD", "median_minutes": 402, "nights": 7},
     "delta_minutes": -72, "wakeup": {"avg": 1.33, "count": 3},
     "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}
    ```
    `triggers` は detected のときだけ1つ以上（並びは duration → wakeup）、それ以外は `[]`。窓が空なら `median_minutes` は null、どちらかの窓が空なら `delta_minutes` は null、評価0回なら `wakeup.avg` は null・`count` は 0。`previous.from` が `previous.to` より後のことがある（そのとき `nights` は 0）
  - CHECK `alerts_alert_type_check`: `alert_type IN ('weight_change', 'record_gap', 'sleep_decline')`

**`evaluate_client_alerts` の既存（`20260914000200`）からの差分**（本体の他の行は一字一句同じ）:
- DECLARE の見出しコメントに「睡眠悪化の設計 §4」を足した
- DECLARE に ③ の定数 11 個（`c_sleep_span_days` 14 / `c_sleep_recent_days` 7 / `c_sleep_min_minutes` 120 / `c_sleep_max_minutes` 960 / `c_sleep_min_nights` 4 / `c_sleep_drop_minutes` 60 / `c_sleep_clear_ratio` 0.8 / `c_sleep_min_ratings` 3 / `c_sleep_wakeup_avg` 1.5 / `c_sleep_wakeup_clear` 2.0 / `c_sleep_severity` 'medium'）と根拠のコメント
- `g_eval` の後ろに CTE 5つ: `s_night`（窓の晩）→ `s_window`（窓ごとの晩の数・中央値、目覚め評価の回数・平均）→ `s_eval`（監視対象に LEFT JOIN、Δ）→ `s_cond`（条件ごとの5状態 none / insufficient / met / pending / cleared）→ `s_state`（§4.4 の順序付き規則）
- `record_gap` の SELECT 末尾の `FROM g_eval ge;` の `;` を外し、3本目の `UNION ALL`（`sleep_decline`）を足した
- 関数の COMMENT を「3行」に直し、睡眠悪化の設計への参照を足した
- 関数の前のブロックコメントを「3行を返す」に直し、差分の説明を足した

- [ ] **Step 1: テストを書く**

`supabase/tests/sleep_decline_alert_test.sql` を次の内容で作る（Task 2 で第2部・第3部を足す）。

```sql
-- =============================================================================
-- 睡眠悪化アラート（sleep_decline）のテスト
-- （フェーズ9.1 拡張 ③ / 20261003000000_alert_sleep_decline.sql。
--   設計: docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md §4・§8.1）
--
-- 実行方法（リポジトリルートから。20261003000000 まで適用したローカル Supabase スタックで）:
--   docker exec -i supabase_db_<project_id> psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/sleep_decline_alert_test.sql
--   <project_id> は使うスタックの supabase/config.toml の project_id。
--   migration の検証は隔離したスタックで行い、共有スタック（supabase_db_fit-connect）には当てない
--
-- - 全ケース成功時のみ最終行に「ALL SLEEP DECLINE ALERT TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
--
-- 方針（client_alert_detection_test.sql と同じ）:
--   - BEGIN の直後に alerts と alert_detection_runs を DELETE する（ROLLBACK で戻る）
--   - 件数・状態の assert は試験用の顧客に限る（evaluate / 本実行は全顧客を評価する）
--   - 対象日は過去の固定日（2026-09）。evaluate の既定の締め時刻 = D+1 の JST 0:00
--   - sleep_records の created_at / updated_at は必ず明示する（既定値の now() のままだと、過去の
--     対象日では締め時刻より後になり、窓にも最終到着日 R にも入らない）。省略した行は起床日の
--     08:00 JST に届いたものとする
--   - 監視対象にするため、各顧客の最終到着 R が D − 14 以降になるようにする（睡眠の created_at で足りる）
--   - 関数は postgres（cron と同じ実行ロール）で呼ぶ
--
-- 検証ケース（番号は設計 §8.1）:
--   第0部 CHECK
--   (23) alerts は alert_type = 'sleep_decline' を受け付け、未知の値を拒む
--   第1部 evaluate（D = 2026-09-20。直近の窓 09-13〜09-19、前の窓 09-06〜09-12）
--   (1)  睡眠時間が成立（前 7晩・直近 5晩、Δ −70）→ detected・medium・triggers ["duration"]・payload の全体
--   (2)  境界: Δ = −60 は成立、Δ = −59.5 は保留（丸めると −60 だが成立しない）
--   (3)  解消: Δ = −47 は cleared、Δ = −48 は保留
--   (4)  直近の窓が3晩（目覚め評価なし）→ unknown
--   (5)  範囲: 119分・961分の晩は数えず、120分・960分ちょうどは数える
--   (6)  外れ値: 毎晩 383 分で前の窓に 900 分が1晩 → 成立しない。直近4晩のうち1晩だけ 140 分 → 成立しない
--   (7)  窓の境界: D−8 の晩は前の窓、D−7 の晩は直近の窓、D−15 の晩は窓の外
--   (8)  登録日: 登録日より前の晩は数えない。D = J + 10 は評価できず、D = J + 11 は評価できる
--   (9)  created_at > as_of の晩は数えない
--   (10) 当日 D の晩と未来の日付は数えない。顧客が書ける値（recorded_date = ±infinity、睡眠時間が負・0・
--        integer の最大値）でも evaluate は落ちず、その晩は数えない（設計 §7）
--   (11) delta_minutes は丸める前の中央値どうしの差から出る（340.5 − 400 → −60。341 − 400 = −59 ではない）
--   (12) 目覚め評価だけで成立（睡眠時間が NULL・範囲外の行の評価、[1, 1, 2]）→ triggers ["wakeup"]・前の窓は nights 0。
--        登録直後（前の窓の from が to より後）でも目覚め評価で成立する
--   (13) 目覚め評価の境界: 平均ちょうど 1.5（[1, 1, 2, 2]）は保留、[2, 2, 2] は解消
--   (14) 両方成立 → triggers ["duration", "wakeup"]
--   (15) 設計 §4.4 の表の代表的な組み合わせ
--   (16) 監視対象でない顧客（no_account・self）には行が無い。データの無い監視対象には unknown の行がある
--        （監視対象1名につき3行）。全行で「detected ⇔ medium ⇔ triggers が空でない」・severity_reason なし
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DELETE FROM public.alerts;
DELETE FROM public.alert_detection_runs;

-- -----------------------------------------------------------------------------
-- 共通の試験データ（postgres として実行。RLS バイパス）
--   trainer T  : aaaaaaaa-1003-0001-0000-00000000000a（試験用顧客の担当。business）
--   trainer XS : aaaaaaaa-1003-0001-0000-00000000000d（自己登録: 自分自身が顧客）
--   client  NN : cccccccc-1003-0001-0000-0000000000NN（第1部 01〜28）
-- -----------------------------------------------------------------------------
\echo '--- setup: 共通の試験データ作成 (trainer T・XS)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT v.id::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'sleep-alert-test-' || v.id || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM (VALUES
    ('aaaaaaaa-1003-0001-0000-00000000000a'),
    ('aaaaaaaa-1003-0001-0000-00000000000d')
  ) AS v(id);

INSERT INTO public.trainers (id, name, email, subscription_plan)
SELECT v.id::uuid, v.name, 'sleep-alert-test-' || v.id || '@example.com', 'business'
  FROM (VALUES
    ('aaaaaaaa-1003-0001-0000-00000000000a', '睡眠テスト トレーナーT'),
    ('aaaaaaaa-1003-0001-0000-00000000000d', '睡眠テスト 自己登録XS')
  ) AS v(id, name);

-- =============================================================================
-- 第1部: evaluate_client_alerts（D = 2026-09-20、既定の締め時刻 = 2026-09-21 0:00 JST）
--   D−15 = 09-05、D−14 = 09-06、D−8 = 09-12、D−7 = 09-13、D−1 = 09-19
--   01 DUR_MET      : 前 [390,395,400,400,405,410,420]（中央値 400）・直近 [320,325,330,340,345]（330）
--   02 BND60        : 前 400×4・直近 340×4（Δ −60）
--   03 BND59_5      : 前 [400,400,401,401]（400.5）・直近 341×4（Δ −59.5）
--   04 CLR47        : 前 400×4・直近 353×4（Δ −47）     05 CLR48 : 前 400×4・直近 352×4（Δ −48）
--   06 RECENT3      : 前 400×7・直近 300×3
--   07 RANGE        : 前 960×4 + 961×1・直近 120×4 + 119×1
--   08 OUT_PREV900  : 毎晩 383、前の窓の 09-08 だけ 900
--   09 OUT_RECENT140: 前 383×4・直近 [383,383,383,140]
--   10 WIN_BND      : 09-05（D−15）・09-06（D−14）・09-10〜09-12（09-12 = D−8）は 400、
--                     09-13（D−7）・09-15・09-17・09-19（D−1）は 330
--   11 JOIN         : 登録 09-09 10:00。09-01〜09-09 は登録時に一括で届いた（09-01〜09-08 は 330、09-09 は 400）。
--                     09-10〜09-12 は 400、09-13〜09-19 は 330
--   12 ASOF         : 前 400×4・直近 330×4。うち 09-19 の晩だけ 09-20 07:00 JST に届く
--   13 DAY_D_FUTURE : 前 400×4・直近 330×3。D（09-20）の晩と未来（09-25）の晩も締め時刻までに届いている
--   14 UNROUNDED    : 前 400×4・直近 [340,340,341,341]（340.5）
--   15 WAKE_ONLY    : 睡眠時間 NULL / 60 / NULL の行の評価 [1, 1, 2]
--   16 WAKE_NEWJOIN : 登録 09-16 10:00。睡眠時間 NULL の評価 [1, 1, 1]（09-16〜09-18）
--   17 WAKE_15      : 評価 [1, 1, 2, 2]               18 WAKE_20 : 評価 [2, 2, 2]
--   19 BOTH         : 前 400×4・直近 330×4、評価 [1, 1, 2, 1]
--   20 MET_WCLR     : 前 400×4・直近 330×4、評価 [3, 3, 3]
--   21 CLR_WPEND    : 前 400×4・直近 400×4、評価 [1, 2, 2]
--   22 CLR_WNONE    : 前 400×4・直近 400×4、評価なし
--   23 CLR_WINSUF   : 前 400×4・直近 400×4、評価 [1, 1]
--   24 INSUF_WCLR   : 前 400×4・直近 400×3、評価 [3, 3, 3]
--   25 NONE_WINSUF  : 睡眠時間 NULL の評価 [1, 1]
--   26 NOAUTH       : auth.users に行が無い（データは成立する形）
--   27 NODATA       : 登録 09-15 12:00・睡眠の記録なし（監視対象）
--   28 HOSTILE      : 前 400×4・直近 330×3 に加え、-5 / 2147483647 / 0 分の晩と、起床日 infinity / -infinity の晩
--   XS SELF         : 自己登録（データは成立する形）
-- =============================================================================
\echo '--- 第1部 setup: evaluate 用の試験用顧客 01〜28 と XS'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-1003-0001-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'sleep-alert-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['01','02','03','04','05','06','07','08','09','10','11','12','13','14',
                    '15','16','17','18','19','20','21','22','23','24','25','27','28']) AS n;  -- 26 NOAUTH は入れない

INSERT INTO public.clients (client_id, name, trainer_id, purpose, created_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || v.n)::uuid, '睡眠テスト顧客' || v.n,
       'aaaaaaaa-1003-0001-0000-00000000000a', 'health_improvement', v.created_at::timestamptz
  FROM (VALUES
    ('01', '2026-07-01 12:00+09'), ('02', '2026-07-01 12:00+09'), ('03', '2026-07-01 12:00+09'),
    ('04', '2026-07-01 12:00+09'), ('05', '2026-07-01 12:00+09'), ('06', '2026-07-01 12:00+09'),
    ('07', '2026-07-01 12:00+09'), ('08', '2026-07-01 12:00+09'), ('09', '2026-07-01 12:00+09'),
    ('10', '2026-07-01 12:00+09'), ('11', '2026-09-09 10:00+09'), ('12', '2026-07-01 12:00+09'),
    ('13', '2026-07-01 12:00+09'), ('14', '2026-07-01 12:00+09'), ('15', '2026-07-01 12:00+09'),
    ('16', '2026-09-16 10:00+09'), ('17', '2026-07-01 12:00+09'), ('18', '2026-07-01 12:00+09'),
    ('19', '2026-07-01 12:00+09'), ('20', '2026-07-01 12:00+09'), ('21', '2026-07-01 12:00+09'),
    ('22', '2026-07-01 12:00+09'), ('23', '2026-07-01 12:00+09'), ('24', '2026-07-01 12:00+09'),
    ('25', '2026-07-01 12:00+09'), ('26', '2026-07-01 12:00+09'), ('27', '2026-09-15 12:00+09'),
    ('28', '2026-07-01 12:00+09')
  ) AS v(n, created_at);

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('aaaaaaaa-1003-0001-0000-00000000000d', '睡眠テスト 自己登録XS',
   'aaaaaaaa-1003-0001-0000-00000000000d', '2026-07-01 12:00+09');

-- 同じ値が続く晩（毎晩 1 行。評価なし。到着 arrived を省略した行は起床日の 08:00 JST）
INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || r.n)::uuid, g.d::date, r.minutes, NULL, 'healthkit',
       coalesce(r.arrived::timestamptz, (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'),
       coalesce(r.arrived::timestamptz, (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo')
  FROM (VALUES
    ('02', '2026-09-09', '2026-09-12', 400, NULL), ('02', '2026-09-16', '2026-09-19', 340, NULL),
    ('03', '2026-09-16', '2026-09-19', 341, NULL),
    ('04', '2026-09-09', '2026-09-12', 400, NULL), ('04', '2026-09-16', '2026-09-19', 353, NULL),
    ('05', '2026-09-09', '2026-09-12', 400, NULL), ('05', '2026-09-16', '2026-09-19', 352, NULL),
    ('06', '2026-09-06', '2026-09-12', 400, NULL),
    ('07', '2026-09-06', '2026-09-09', 960, NULL), ('07', '2026-09-13', '2026-09-16', 120, NULL),
    ('08', '2026-09-06', '2026-09-07', 383, NULL), ('08', '2026-09-09', '2026-09-19', 383, NULL),
    ('09', '2026-09-09', '2026-09-12', 383, NULL), ('09', '2026-09-16', '2026-09-18', 383, NULL),
    -- 11 JOIN: 登録（09-09 10:00）時の初回連携で、09-01〜09-08 の 330 と 09-09 の 400 が一括で届いた
    ('11', '2026-09-01', '2026-09-08', 330, '2026-09-09 10:05+09'),
    ('11', '2026-09-09', '2026-09-09', 400, '2026-09-09 10:05+09'),
    ('11', '2026-09-10', '2026-09-12', 400, NULL), ('11', '2026-09-13', '2026-09-19', 330, NULL),
    ('12', '2026-09-09', '2026-09-12', 400, NULL),
    ('13', '2026-09-09', '2026-09-12', 400, NULL),
    ('14', '2026-09-09', '2026-09-12', 400, NULL),
    ('19', '2026-09-09', '2026-09-12', 400, NULL),
    ('20', '2026-09-09', '2026-09-12', 400, NULL),
    ('21', '2026-09-09', '2026-09-12', 400, NULL),
    ('22', '2026-09-09', '2026-09-12', 400, NULL), ('22', '2026-09-16', '2026-09-19', 400, NULL),
    ('23', '2026-09-09', '2026-09-12', 400, NULL),
    ('24', '2026-09-09', '2026-09-12', 400, NULL),
    ('26', '2026-09-09', '2026-09-12', 400, NULL), ('26', '2026-09-16', '2026-09-19', 330, NULL),
    ('28', '2026-09-09', '2026-09-12', 400, NULL)
  ) AS r(n, from_day, to_day, minutes, arrived)
 CROSS JOIN LATERAL generate_series(r.from_day::date, r.to_day::date, interval '1 day') AS g(d);

-- 1晩ずつ値を指定する行（評価・到着を含む。睡眠時間が NULL の行は手動の評価だけ）
INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || v.n)::uuid, v.day::date, v.minutes, v.rating,
       CASE WHEN v.minutes IS NULL THEN 'manual' ELSE 'healthkit' END,
       coalesce(v.arrived::timestamptz, (v.day::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'),
       coalesce(v.arrived::timestamptz, (v.day::date + time '08:00') AT TIME ZONE 'Asia/Tokyo')
  FROM (VALUES
    -- 01 DUR_MET
    ('01', '2026-09-06', 390, NULL, NULL), ('01', '2026-09-07', 395, NULL, NULL),
    ('01', '2026-09-08', 400, NULL, NULL), ('01', '2026-09-09', 400, NULL, NULL),
    ('01', '2026-09-10', 405, NULL, NULL), ('01', '2026-09-11', 410, NULL, NULL),
    ('01', '2026-09-12', 420, NULL, NULL),
    ('01', '2026-09-13', 320, NULL, NULL), ('01', '2026-09-14', 325, NULL, NULL),
    ('01', '2026-09-15', 330, NULL, NULL), ('01', '2026-09-17', 340, NULL, NULL),
    ('01', '2026-09-19', 345, NULL, NULL),
    -- 03 BND59_5: 前の窓の中央値 400.5
    ('03', '2026-09-09', 400, NULL, NULL), ('03', '2026-09-10', 400, NULL, NULL),
    ('03', '2026-09-11', 401, NULL, NULL), ('03', '2026-09-12', 401, NULL, NULL),
    -- 06 RECENT3: 直近の窓は3晩
    ('06', '2026-09-13', 300, NULL, NULL), ('06', '2026-09-15', 300, NULL, NULL),
    ('06', '2026-09-17', 300, NULL, NULL),
    -- 07 RANGE: 961 と 119 は範囲外
    ('07', '2026-09-10', 961, NULL, NULL), ('07', '2026-09-17', 119, NULL, NULL),
    -- 08 OUT_PREV900: 前の窓に1晩だけ 900（平均なら前の窓 456.9 で Δ −73.9 の成立になる）
    ('08', '2026-09-08', 900, NULL, NULL),
    -- 09 OUT_RECENT140: 直近の窓に1晩だけ 140（平均なら直近 322.25 で Δ −60.75 の成立になる）
    ('09', '2026-09-19', 140, NULL, NULL),
    -- 10 WIN_BND
    ('10', '2026-09-05', 400, NULL, NULL), ('10', '2026-09-06', 400, NULL, NULL),
    ('10', '2026-09-10', 400, NULL, NULL), ('10', '2026-09-11', 400, NULL, NULL),
    ('10', '2026-09-12', 400, NULL, NULL),
    ('10', '2026-09-13', 330, NULL, NULL), ('10', '2026-09-15', 330, NULL, NULL),
    ('10', '2026-09-17', 330, NULL, NULL), ('10', '2026-09-19', 330, NULL, NULL),
    -- 12 ASOF: 09-19 の晩だけ 09-20 07:00 JST に届く
    ('12', '2026-09-13', 330, NULL, NULL), ('12', '2026-09-15', 330, NULL, NULL),
    ('12', '2026-09-17', 330, NULL, NULL), ('12', '2026-09-19', 330, NULL, '2026-09-20 07:00+09'),
    -- 13 DAY_D_FUTURE: D（09-20）の晩と未来（09-25）の晩は締め時刻までに届いているが窓の外
    ('13', '2026-09-13', 330, NULL, NULL), ('13', '2026-09-15', 330, NULL, NULL),
    ('13', '2026-09-17', 330, NULL, NULL),
    ('13', '2026-09-20', 330, NULL, '2026-09-20 08:00+09'),
    ('13', '2026-09-25', 330, NULL, '2026-09-20 09:00+09'),
    -- 14 UNROUNDED: 直近の窓の中央値 340.5
    ('14', '2026-09-16', 340, NULL, NULL), ('14', '2026-09-17', 340, NULL, NULL),
    ('14', '2026-09-18', 341, NULL, NULL), ('14', '2026-09-19', 341, NULL, NULL),
    -- 15 WAKE_ONLY: 睡眠時間が NULL / 範囲外（60）の行の評価も数える
    ('15', '2026-09-15', NULL, 1, NULL), ('15', '2026-09-17', 60, 1, NULL),
    ('15', '2026-09-19', NULL, 2, NULL),
    -- 16 WAKE_NEWJOIN: 登録（09-16 10:00）の後に付けた評価
    ('16', '2026-09-16', NULL, 1, '2026-09-16 21:00+09'), ('16', '2026-09-17', NULL, 1, '2026-09-17 21:00+09'),
    ('16', '2026-09-18', NULL, 1, '2026-09-18 21:00+09'),
    -- 17 WAKE_15 / 18 WAKE_20
    ('17', '2026-09-13', NULL, 1, NULL), ('17', '2026-09-15', NULL, 1, NULL),
    ('17', '2026-09-17', NULL, 2, NULL), ('17', '2026-09-19', NULL, 2, NULL),
    ('18', '2026-09-14', NULL, 2, NULL), ('18', '2026-09-16', NULL, 2, NULL),
    ('18', '2026-09-18', NULL, 2, NULL),
    -- 19 BOTH
    ('19', '2026-09-16', 330, 1, NULL), ('19', '2026-09-17', 330, 1, NULL),
    ('19', '2026-09-18', 330, 2, NULL), ('19', '2026-09-19', 330, 1, NULL),
    -- 20 MET_WCLR
    ('20', '2026-09-16', 330, 3, NULL), ('20', '2026-09-17', 330, 3, NULL),
    ('20', '2026-09-18', 330, 3, NULL), ('20', '2026-09-19', 330, NULL, NULL),
    -- 21 CLR_WPEND
    ('21', '2026-09-16', 400, 1, NULL), ('21', '2026-09-17', 400, 2, NULL),
    ('21', '2026-09-18', 400, 2, NULL), ('21', '2026-09-19', 400, NULL, NULL),
    -- 23 CLR_WINSUF
    ('23', '2026-09-16', 400, 1, NULL), ('23', '2026-09-17', 400, 1, NULL),
    ('23', '2026-09-18', 400, NULL, NULL), ('23', '2026-09-19', 400, NULL, NULL),
    -- 24 INSUF_WCLR
    ('24', '2026-09-17', 400, 3, NULL), ('24', '2026-09-18', 400, 3, NULL),
    ('24', '2026-09-19', 400, 3, NULL),
    -- 25 NONE_WINSUF
    ('25', '2026-09-17', NULL, 1, NULL), ('25', '2026-09-19', NULL, 1, NULL),
    -- 28 HOSTILE: 有効な晩は直近 3晩だけ。範囲外の睡眠時間と ±infinity の起床日は、締め時刻までに届いていても数えない
    ('28', '2026-09-13', 330, NULL, NULL), ('28', '2026-09-15', 330, NULL, NULL),
    ('28', '2026-09-17', 330, NULL, NULL),
    ('28', '2026-09-14', -5, NULL, NULL), ('28', '2026-09-16', 2147483647, NULL, NULL),
    ('28', '2026-09-18', 0, NULL, NULL),
    ('28', 'infinity',  300, NULL, '2026-09-19 08:00+09'), ('28', '-infinity', 300, NULL, '2026-09-19 08:00+09')
  ) AS v(n, day, minutes, rating, arrived);

-- XS SELF: 自己登録の顧客（データは成立する形: 前 400×4・直近 330×4）
INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT 'aaaaaaaa-1003-0001-0000-00000000000d', g.d::date,
       CASE WHEN g.d < '2026-09-13' THEN 400 ELSE 330 END, NULL, 'healthkit',
       (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo',
       (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'
  FROM generate_series('2026-09-09'::date, '2026-09-19'::date, interval '1 day') AS g(d)
 WHERE g.d::date NOT IN ('2026-09-13', '2026-09-14', '2026-09-15');

-- -----------------------------------------------------------------------------
-- ケース(23): CHECK は sleep_decline を受け付け、未知の値を拒む
--   resolved の行として入れて、生きている行の一意性（alerts_live_client_type_key）には触れない。
--   入れた行はこのブロックの最後に消す
-- -----------------------------------------------------------------------------
\echo '--- case 23: alerts.alert_type の CHECK が sleep_decline を受け付け、未知の値を拒むこと'

DO $$
BEGIN
  BEGIN
    INSERT INTO public.alerts (
      trainer_id, client_id, alert_type, severity, status, payload,
      first_detected_on, surfaced_on, last_detected_on, resolved_at, resolved_reason
    ) VALUES
      ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000027',
       'sleep_decline', 'medium', 'resolved', '{"v":1}', '2026-09-01', '2026-09-01', '2026-09-01', now(), 'cleared');
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'FAIL: (23) alerts が alert_type = ''sleep_decline'' を拒んだ（%）', SQLERRM;
  END;

  -- 既存の2種別も今までどおり入る
  INSERT INTO public.alerts (
    trainer_id, client_id, alert_type, severity, status, payload,
    first_detected_on, surfaced_on, last_detected_on, resolved_at, resolved_reason
  ) VALUES
    ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000027',
     'weight_change', 'high', 'resolved', '{"v":1}', '2026-09-01', '2026-09-01', '2026-09-01', now(), 'cleared'),
    ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000027',
     'record_gap', 'medium', 'resolved', '{"v":1}', '2026-09-01', '2026-09-01', '2026-09-01', now(), 'cleared');

  BEGIN
    INSERT INTO public.alerts (
      trainer_id, client_id, alert_type, severity, status, payload,
      first_detected_on, surfaced_on, last_detected_on, resolved_at, resolved_reason
    ) VALUES
      ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000027',
       'sleep_quality', 'medium', 'resolved', '{"v":1}', '2026-09-01', '2026-09-01', '2026-09-01', now(), 'cleared');
    RAISE EXCEPTION 'FAIL: (23) 未知の alert_type（sleep_quality）を受け付けた';
  EXCEPTION
    WHEN check_violation THEN
      IF SQLERRM NOT LIKE '%alerts_alert_type_check%' THEN RAISE; END IF;
  END;

  DELETE FROM public.alerts WHERE client_id = 'cccccccc-1003-0001-0000-000000000027';
  RAISE NOTICE 'OK: CHECK は weight_change / record_gap / sleep_decline を受け付け、未知の値（sleep_quality）を alerts_alert_type_check で拒む';
END $$;

-- 既定の締め時刻（D+1 の JST 0:00）での評価結果（試験用顧客だけ。全種別）
CREATE TEMP TABLE eval_0920 ON COMMIT DROP AS
  SELECT e.*
    FROM public.evaluate_client_alerts('2026-09-20') e
   WHERE e.client_id::text LIKE 'cccccccc-1003-0001-%'
      OR e.client_id = 'aaaaaaaa-1003-0001-0000-00000000000d';

-- -----------------------------------------------------------------------------
-- ケース(1): 睡眠時間が成立（payload の全体を比べる）
-- -----------------------------------------------------------------------------
\echo '--- case 1: 睡眠時間が成立（前 7晩・直近 5晩、Δ −70）→ detected・medium・triggers ["duration"]・payload の全体'

DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000001' AND e.alert_type = 'sleep_decline';
  IF r.client_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: (1) 監視対象の顧客 01 に sleep_decline の評価行が無い';
  END IF;
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'medium'
     OR r.payload IS DISTINCT FROM
        '{"v": 1,
          "triggers": ["duration"],
          "recent":   {"from": "2026-09-13", "to": "2026-09-19", "median_minutes": 330, "nights": 5},
          "previous": {"from": "2026-09-06", "to": "2026-09-12", "median_minutes": 400, "nights": 7},
          "delta_minutes": -70,
          "wakeup": {"avg": null, "count": 0},
          "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}'::jsonb THEN
    RAISE EXCEPTION 'FAIL: (1) 睡眠時間の成立が期待と異なる: % / % / %', r.state, r.severity, r.payload;
  END IF;
  RAISE NOTICE 'OK: 前 7晩（中央値 400）・直近 5晩（330）で Δ −70 → detected・medium、payload は設計 §4.6 の形';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(2)(3)(4): 成立・解消の境界と晩の数
-- -----------------------------------------------------------------------------
\echo '--- case 2-4: Δ −60 は成立・−59.5 は保留 / −47 は解消・−48 は保留 / 直近3晩は評価しない'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: %s / %s / %s（期待 %s / %s / triggers %s / delta %s / 直近 %s晩・%s / 前 %s晩・%s）',
                           x.n, e.state, e.severity, e.payload,
                           x.exp_state, x.exp_severity, x.exp_triggers, x.exp_delta,
                           x.exp_recent_nights, x.exp_recent_median, x.exp_previous_nights, x.exp_previous_median), E'\n')
    INTO v_bad
    FROM (VALUES
      -- (2) Δ = −60 ちょうどは成立
      ('02', 'detected', 'medium', '["duration"]', -60, 4, 340, 4, 400),
      -- (2) Δ = −59.5 は保留（delta_minutes は丸めると −60 だが成立しない。前の窓の中央値 400.5 は 401 と出る）
      ('03', 'unknown',  NULL,     '[]',           -60, 4, 341, 4, 401),
      -- (3) Δ = −47 は解消
      ('04', 'cleared',  NULL,     '[]',           -47, 4, 353, 4, 400),
      -- (3) Δ = −48 ちょうどは保留
      ('05', 'unknown',  NULL,     '[]',           -48, 4, 352, 4, 400),
      -- (4) 直近の窓が3晩 → 評価しない（差は出るが unknown）
      ('06', 'unknown',  NULL,     '[]',          -100, 3, 300, 7, 400)
    ) AS x(n, exp_state, exp_severity, exp_triggers, exp_delta,
           exp_recent_nights, exp_recent_median, exp_previous_nights, exp_previous_median)
    LEFT JOIN pg_temp.eval_0920 e
      ON e.client_id = ('cccccccc-1003-0001-0000-0000000000' || x.n)::uuid
     AND e.alert_type = 'sleep_decline'
   WHERE (e.state, e.severity, e.payload->'triggers', (e.payload->>'delta_minutes')::numeric,
          (e.payload->'recent'->>'nights')::int, (e.payload->'recent'->>'median_minutes')::numeric,
          (e.payload->'previous'->>'nights')::int, (e.payload->'previous'->>'median_minutes')::numeric)
         IS DISTINCT FROM
         (x.exp_state, x.exp_severity, x.exp_triggers::jsonb, x.exp_delta::numeric,
          x.exp_recent_nights, x.exp_recent_median::numeric, x.exp_previous_nights, x.exp_previous_median::numeric);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (2)-(4) 境界・晩の数の判定が期待と異なる:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: Δ −60 は detected、−59.5 は unknown（delta_minutes −60）、−47 は cleared、−48 は unknown、直近3晩は unknown';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(5)(6)(7): 範囲外の晩・外れ値・窓の境界
-- -----------------------------------------------------------------------------
\echo '--- case 5-7: 119 / 961 分は数えず 120 / 960 分は数える / 1晩の外れ値では成立しない / D−8 は前・D−7 は直近・D−15 は外'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: %s / %s（期待 %s / delta %s / 直近 %s晩・%s / 前 %s晩・%s）',
                           x.n, e.state, e.payload,
                           x.exp_state, x.exp_delta,
                           x.exp_recent_nights, x.exp_recent_median, x.exp_previous_nights, x.exp_previous_median), E'\n')
    INTO v_bad
    FROM (VALUES
      -- (5) 前の窓は 960×4（961 は数えない）、直近の窓は 120×4（119 は数えない）
      ('07', 'detected', -840, 4, 120, 4, 960),
      -- (6) 前の窓の 900 が1晩あっても中央値は 383 のまま
      ('08', 'cleared',     0, 7, 383, 7, 383),
      -- (6) 直近の窓の 140 が1晩あっても中央値は 383 のまま
      ('09', 'cleared',     0, 4, 383, 4, 383),
      -- (7) 前の窓は 09-06（D−14）・09-10・09-11・09-12（D−8）の4晩、直近の窓は 09-13（D−7）〜09-19 の4晩。
      --     09-05（D−15）は数えない
      ('10', 'detected',  -70, 4, 330, 4, 400)
    ) AS x(n, exp_state, exp_delta, exp_recent_nights, exp_recent_median, exp_previous_nights, exp_previous_median)
    LEFT JOIN pg_temp.eval_0920 e
      ON e.client_id = ('cccccccc-1003-0001-0000-0000000000' || x.n)::uuid
     AND e.alert_type = 'sleep_decline'
   WHERE (e.state, (e.payload->>'delta_minutes')::numeric,
          (e.payload->'recent'->>'nights')::int, (e.payload->'recent'->>'median_minutes')::numeric,
          (e.payload->'previous'->>'nights')::int, (e.payload->'previous'->>'median_minutes')::numeric)
         IS DISTINCT FROM
         (x.exp_state, x.exp_delta::numeric,
          x.exp_recent_nights, x.exp_recent_median::numeric, x.exp_previous_nights, x.exp_previous_median::numeric);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (5)-(7) 範囲外・外れ値・窓の境界の判定が期待と異なる:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: 範囲は 120〜960 分（両端を含む）、1晩の外れ値は中央値で吸収、窓の境界は D−14 / D−8 / D−7 / D−1';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(8)(9)(10): 登録日・締め時刻・当日と未来の晩
-- -----------------------------------------------------------------------------
\echo '--- case 8-10: 登録日より前の晩は数えない（J+10 は評価しない・J+11 は評価する）/ 締め時刻より後に届いた晩・当日と未来の晩・顧客が書いた異常値は数えない'

DO $$
DECLARE r record;
BEGIN
  -- (8) D = J + 11（09-20）: 前の窓は登録日 09-09 から4晩（登録前の 09-06〜09-08 は数えない）→ 評価して detected
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000011' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'detected'
     OR r.payload->'previous'->>'from' IS DISTINCT FROM '2026-09-09'
     OR (r.payload->'previous'->>'nights')::int IS DISTINCT FROM 4
     OR (r.payload->'previous'->>'median_minutes')::numeric IS DISTINCT FROM 400
     OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 7 THEN
    RAISE EXCEPTION 'FAIL: (8) D = J + 11 の評価が期待（detected・前の窓は 09-09 から4晩）と異なる: % / %', r.state, r.payload;
  END IF;

  -- (8) D = J + 10（09-19）: 前の窓は 09-09〜09-11 の3晩 → 評価しない。
  --     登録前の晩も数えると前の窓が7晩（中央値 330）になり、Δ 0 の cleared になる
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-09-19') e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000011' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown'
     OR r.payload->'previous'->>'from' IS DISTINCT FROM '2026-09-09'
     OR r.payload->'previous'->>'to' IS DISTINCT FROM '2026-09-11'
     OR (r.payload->'previous'->>'nights')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'FAIL: (8) D = J + 10 の評価が期待（unknown・前の窓は 09-09〜09-11 の3晩）と異なる（登録前の晩を数えている疑い）: % / %',
      r.state, r.payload;
  END IF;

  -- (9) 締め時刻 06:00 JST では 09-19 の晩（07:00 に届く）を数えず直近3晩で unknown。08:00 にずらすと4晩で detected
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-09-20', '2026-09-20 06:00+09') e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000012' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown' OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'FAIL: (9) 締め時刻 06:00 JST で、後から届いた晩を数えている疑い: % / %', r.state, r.payload;
  END IF;
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-09-20', '2026-09-20 08:00+09') e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000012' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'detected' OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'FAIL: (9) 締め時刻を 08:00 JST にずらしても届いた晩が窓に入らない: % / %', r.state, r.payload;
  END IF;

  -- (10) D（09-20）の晩と未来（09-25）の晩は、締め時刻までに届いていても数えない → 直近3晩で unknown
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000013' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown' OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 3
     OR r.payload->'recent'->>'to' IS DISTINCT FROM '2026-09-19' THEN
    RAISE EXCEPTION 'FAIL: (10) 当日 D の晩か未来の日付の晩を数えている疑い: % / %', r.state, r.payload;
  END IF;

  -- (10) 顧客が書ける値: ±infinity の起床日と、範囲外（-5 / 2147483647 / 0）の睡眠時間は数えない（評価は落ちない）
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000028' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown'
     OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 3
     OR (r.payload->'recent'->>'median_minutes')::numeric IS DISTINCT FROM 330
     OR (r.payload->'previous'->>'nights')::int IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'FAIL: (10) ±infinity の起床日か範囲外の睡眠時間を数えている疑い: % / %', r.state, r.payload;
  END IF;
  RAISE NOTICE 'OK: 登録前の晩は数えず J+10 は unknown・J+11 は detected。締め時刻より後に届いた晩・当日 D と未来の晩・±infinity の晩は数えない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(11)(12): 丸める前の差 / 目覚め評価だけで成立
-- -----------------------------------------------------------------------------
\echo '--- case 11-12: delta_minutes は丸める前の差を丸める / 目覚め評価だけで成立（前の窓は nights 0、登録直後も）'

DO $$
DECLARE r record;
BEGIN
  -- (11) 直近 340.5・前 400.0 → delta_minutes は round(−59.5) = −60（round(340.5) − 400 = −59 ではない）。
  --      判定は丸める前の −59.5 なので保留（unknown）
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000014' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown'
     OR (r.payload->>'delta_minutes')::numeric IS DISTINCT FROM -60
     OR (r.payload->'recent'->>'median_minutes')::numeric IS DISTINCT FROM 341
     OR (r.payload->'previous'->>'median_minutes')::numeric IS DISTINCT FROM 400 THEN
    RAISE EXCEPTION 'FAIL: (11) delta_minutes が丸める前の中央値どうしの差から出ていない: % / %', r.state, r.payload;
  END IF;

  -- (12) 睡眠時間が NULL・範囲外（60）の行の評価 [1, 1, 2]（平均 1.33）だけで成立。睡眠時間は「なし」
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000015' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'medium'
     OR r.payload IS DISTINCT FROM
        '{"v": 1,
          "triggers": ["wakeup"],
          "recent":   {"from": "2026-09-13", "to": "2026-09-19", "median_minutes": null, "nights": 0},
          "previous": {"from": "2026-09-06", "to": "2026-09-12", "median_minutes": null, "nights": 0},
          "delta_minutes": null,
          "wakeup": {"avg": 1.33, "count": 3},
          "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}'::jsonb THEN
    RAISE EXCEPTION 'FAIL: (12) 目覚め評価だけの成立が期待と異なる: % / % / %', r.state, r.severity, r.payload;
  END IF;

  -- (12) 登録直後（J = 09-16）: 直近の窓は 09-16 から、前の窓は from（09-16）が to（09-12）より後で nights 0。
  --      評価 [1, 1, 1] で成立する
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000016' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'detected'
     OR r.payload IS DISTINCT FROM
        '{"v": 1,
          "triggers": ["wakeup"],
          "recent":   {"from": "2026-09-16", "to": "2026-09-19", "median_minutes": null, "nights": 0},
          "previous": {"from": "2026-09-16", "to": "2026-09-12", "median_minutes": null, "nights": 0},
          "delta_minutes": null,
          "wakeup": {"avg": 1.00, "count": 3},
          "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}'::jsonb THEN
    RAISE EXCEPTION 'FAIL: (12) 登録直後の目覚め評価の成立・窓の from が期待と異なる: % / %', r.state, r.payload;
  END IF;
  RAISE NOTICE 'OK: delta_minutes は round(340.5 − 400) = −60 で unknown。目覚め評価だけで detected（triggers ["wakeup"]・前の窓 nights 0。登録直後は from が実際の期間）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(13)(14)(15): 目覚め評価の境界・両方成立・§4.4 の表
-- -----------------------------------------------------------------------------
\echo '--- case 13-15: 目覚め評価 1.5 ちょうどは保留・2.0 は解消 / 両方成立 / §4.4 の表の組み合わせ'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s（%s）: %s / %s（期待 %s / triggers %s / wakeup %s）',
                           x.n, x.label, e.state, e.payload, x.exp_state, x.exp_triggers, x.exp_wakeup), E'\n')
    INTO v_bad
    FROM (VALUES
      -- (13) 平均ちょうど 1.5 は保留（睡眠時間なし + 目覚め評価が保留 → unknown）
      ('17', '睡眠時間なし + 目覚め評価 保留（1.5 ちょうど）', 'unknown',  '[]',                     '{"avg": 1.50, "count": 4}'),
      -- (13) [2, 2, 2] は解消（§4.4: 睡眠時間なし + 目覚め評価 解消 → cleared）
      ('18', '睡眠時間なし + 目覚め評価 解消（2.0 ちょうど）', 'cleared',  '[]',                     '{"avg": 2.00, "count": 3}'),
      -- (14) 両方成立
      ('19', '睡眠時間 成立 + 目覚め評価 成立',                'detected', '["duration", "wakeup"]', '{"avg": 1.25, "count": 4}'),
      -- (15) §4.4 の表
      ('20', '睡眠時間 成立 + 目覚め評価 解消',                'detected', '["duration"]',           '{"avg": 3.00, "count": 3}'),
      ('21', '睡眠時間 解消 + 目覚め評価 保留',                'unknown',  '[]',                     '{"avg": 1.67, "count": 3}'),
      ('22', '睡眠時間 解消 + 目覚め評価 なし',                'cleared',  '[]',                     '{"avg": null, "count": 0}'),
      ('23', '睡眠時間 解消 + 目覚め評価 不足',                'cleared',  '[]',                     '{"avg": 1.00, "count": 2}'),
      ('24', '睡眠時間 不足 + 目覚め評価 解消',                'unknown',  '[]',                     '{"avg": 3.00, "count": 3}'),
      ('25', '睡眠時間 なし + 目覚め評価 不足',                'unknown',  '[]',                     '{"avg": 1.00, "count": 2}')
    ) AS x(n, label, exp_state, exp_triggers, exp_wakeup)
    LEFT JOIN pg_temp.eval_0920 e
      ON e.client_id = ('cccccccc-1003-0001-0000-0000000000' || x.n)::uuid
     AND e.alert_type = 'sleep_decline'
   WHERE (e.state, e.payload->'triggers', e.payload->'wakeup')
         IS DISTINCT FROM (x.exp_state, x.exp_triggers::jsonb, x.exp_wakeup::jsonb);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (13)-(15) 目覚め評価・全体の状態が期待と異なる:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: 目覚め評価 1.5 は保留・2.0 は解消、両方成立は triggers ["duration","wakeup"]、§4.4 の表の7通りが期待どおり（不足 + 解消は unknown）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(16): 監視対象と行の数・全行の不変条件
-- -----------------------------------------------------------------------------
\echo '--- case 16: no_account・self には行が無く、データの無い監視対象には unknown の行がある（1名3行）。全行の不変条件'

DO $$
DECLARE
  r     record;
  cnt   int;
  v_bad text;
BEGIN
  -- 26 NOAUTH（auth.users に行が無い）と XS（自己登録）は、成立する形のデータがあっても評価しない
  SELECT count(*) INTO cnt FROM pg_temp.eval_0920 e
   WHERE e.client_id IN ('cccccccc-1003-0001-0000-000000000026', 'aaaaaaaa-1003-0001-0000-00000000000d');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (16) 監視対象でない顧客（no_account / self）が % 行評価されている', cnt;
  END IF;

  -- 27 NODATA: 睡眠の記録が無い監視対象にも unknown の行が1行ある（窓は登録日 09-15 から）
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000027' AND e.alert_type = 'sleep_decline';
  IF r.client_id IS NULL OR r.state IS DISTINCT FROM 'unknown' OR r.severity IS NOT NULL
     OR r.trainer_id IS DISTINCT FROM 'aaaaaaaa-1003-0001-0000-00000000000a'::uuid
     OR r.payload IS DISTINCT FROM
        '{"v": 1,
          "triggers": [],
          "recent":   {"from": "2026-09-15", "to": "2026-09-19", "median_minutes": null, "nights": 0},
          "previous": {"from": "2026-09-15", "to": "2026-09-12", "median_minutes": null, "nights": 0},
          "delta_minutes": null,
          "wakeup": {"avg": null, "count": 0},
          "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}'::jsonb THEN
    RAISE EXCEPTION 'FAIL: (16) データの無い監視対象（27）の sleep_decline 行が期待と異なる: %', row_to_json(r);
  END IF;

  -- 監視対象の顧客は3行（weight_change・record_gap・sleep_decline）ずつ
  SELECT string_agg(format('%s: %s', g.client_id, g.types), E'\n') INTO v_bad
    FROM (
      SELECT e.client_id, array_agg(e.alert_type ORDER BY e.alert_type) AS types
        FROM pg_temp.eval_0920 e
       GROUP BY e.client_id
    ) g
   WHERE g.types IS DISTINCT FROM ARRAY['record_gap', 'sleep_decline', 'weight_change'];
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (16) 種別ごとに1行ずつ（3行）になっていない顧客がある:\n%', v_bad;
  END IF;
  SELECT count(DISTINCT e.client_id) INTO cnt FROM pg_temp.eval_0920 e;
  IF cnt <> 27 THEN
    RAISE EXCEPTION 'FAIL: (16) 評価された試験用顧客が % 名（期待 27 名 = 01〜25・27・28）', cnt;
  END IF;

  -- 全行の不変条件: detected ⇔ severity = medium ⇔ triggers が空でない。severity_reason は入れない。v = 1
  SELECT string_agg(format('%s: %s / %s / %s', e.client_id, e.state, e.severity, e.payload), E'\n') INTO v_bad
    FROM pg_temp.eval_0920 e
   WHERE e.alert_type = 'sleep_decline'
     AND (   (e.state = 'detected') IS DISTINCT FROM (e.severity IS NOT DISTINCT FROM 'medium')
          OR (e.state = 'detected') IS DISTINCT FROM (jsonb_array_length(e.payload->'triggers') > 0)
          OR (e.state <> 'detected' AND e.severity IS NOT NULL)
          OR e.payload ? 'severity_reason'
          OR (e.payload->>'v')::int IS DISTINCT FROM 1);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (16) sleep_decline の行の不変条件（detected ⇔ medium ⇔ triggers あり・severity_reason なし）が崩れている:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: no_account・self は評価せず、データの無い監視対象は unknown。監視対象は3行ずつ、全行で detected ⇔ medium ⇔ triggers あり';
END $$;

-- 第1部の顧客を片付ける（CASCADE で睡眠の記録・alerts も消える）
DELETE FROM public.clients
 WHERE client_id::text LIKE 'cccccccc-1003-0001-%'
    OR client_id = 'aaaaaaaa-1003-0001-0000-00000000000d';

ROLLBACK;

\echo ''
\echo 'ALL SLEEP DECLINE ALERT TESTS PASSED'
```

- [ ] **Step 2: テストが失敗することを確かめる**

隔離スタックは今 `20260923000000` まで適用済みで、新しい migration は入っていない。テストだけを流す。

Run:
```bash
docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/sleep_decline_alert_test.sql
```
Expected: CHECK で拒まれて FAIL（終了コード 3）。最後の行は次のとおり（行番号は環境で変わってよい）:
```
psql:<stdin>:321: ERROR:  FAIL: (23) alerts が alert_type = 'sleep_decline' を拒んだ（new row for relation "alerts" violates check constraint "alerts_alert_type_check"）
```

- [ ] **Step 3: migration を書く**

`supabase/migrations/20261003000000_alert_sleep_decline.sql` を次の内容で作る。ヘッダーは migration 全体（Task 2 で足す 4・5 を含む）を説明している。

```sql
-- =============================================================================
-- Migration: alert_sleep_decline
-- フェーズ9.1 拡張 ③: 異常検知に睡眠悪化（sleep_decline）を3つ目の種別として足す。
-- alerts.alert_type の CHECK を作り直し、evaluate_client_alerts に睡眠の判定を、
-- run_client_alert_detection に睡眠の期限切れと stats の集計キーを足す
--
-- 仕様出典: docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md
--   「4. 検知ルールの仕様」「5. DB の変更」「9. リリースとロールバック」
--   土台: docs/tasks/2026-09-13-trainer-intervention-plan.md（9.1 の共通定義・状態遷移）
--
-- 背景:
--   - 9.1 の検知（20260914000200）は体重急変（weight_change）と記録途絶（record_gap）の2種別。
--     カタログ 1-A ③ の睡眠悪化を同じ評価関数の3本目の UNION ALL として足し、監視対象の判定・
--     状態遷移・冪等性・対応済みの操作・「今日の対応」の表示をそのまま使う（設計 §3）
--   - 本番の睡眠データは実質テストデータで、閾値の妥当性は確かめられない（設計 §2）。判定の正しさは
--     supabase/tests/sleep_decline_alert_test.sql の合成データで固定する
--
-- 検知ルール（定数と根拠は evaluate_client_alerts の DECLARE、詳細は設計 §4）:
--   - 晩 = sleep_records の1行。recorded_date（JST の起床日）が [max(D−14, J), D−1] で、
--     created_at が締め時刻以前の行だけを使う
--   - 睡眠時間: 120〜960 分の晩だけを数え、直近 [max(D−7, J), D−1] と前 [max(D−14, J), D−8] の
--     中央値を比べる。両方の窓に 4 晩以上で評価し、Δ ≤ −60 分で成立、Δ > −48 分で解消、間は保留
--   - 目覚め評価: 直近の窓の wakeup_rating の平均（睡眠時間が範囲外・NULL の行も数える）。
--     3 回以上で評価し、平均 < 1.5 で成立、≥ 2.0 で解消、間は保留
--   - 全体: どちらかが成立 → detected / 睡眠時間が保留・不足か目覚め評価が保留 → unknown /
--     どちらかが解消 → cleared / それ以外 → unknown（設計 §4.4 の表）
--   - 重大度は detected のとき常に medium。payload に severity_reason は入れない
--     （run_client_alert_detection の severity_lowered が種別を問わずこのキーを数えるため）
--   - 期限切れ: 生きている sleep_decline で last_detected_on ≤ D − 14 → resolved（expired）
--
-- 変更（この順に実行する。どれかが失敗すると migration 全体が巻き戻る）:
--   0. ドリフトガード: 両関数の本体（prosrc）の md5 が 20260914000200 の定義と一致することを確かめる
--   1. CHECK alerts_alert_type_check を DROP → ADD（'sleep_decline' を足す）
--   2. alerts の列 COMMENT（alert_type / severity / payload / last_detected_on / resolved_reason）
--   3. evaluate_client_alerts を全文で再定義（睡眠の CTE と3本目の UNION ALL）
--   4. run_client_alert_detection を全文で再定義（期限切れ 3-3 と stats の detected.sleep_decline）
--   5. 末尾の検査: 両関数が SECURITY DEFINER・search_path = ''・EXECUTE は service_role だけ
--   変えないもの: client_activity_snapshot / get_alert_detection_status / cron / alerts の索引と RLS
--
-- push 前の確認（オーナー）:
--   `supabase migration list --linked` と `supabase db push --dry-run` で、未適用が
--   20261003000000 の1本だけであることを確かめる。06:00 JST の直前は避ける
--
-- push 後の確認（postgres で実行。件数だけ）:
--   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
--    WHERE c.conrelid = 'public.alerts'::regclass AND c.conname = 'alerts_alert_type_check';
--   SELECT p.oid::regprocedure, p.prosecdef, p.proconfig, p.proacl,
--          has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated,
--          has_function_privilege('service_role',  p.oid, 'EXECUTE') AS service_role
--     FROM pg_proc p
--    WHERE p.oid IN ('public.evaluate_client_alerts(date, timestamptz)'::regprocedure,
--                    'public.run_client_alert_detection(date)'::regprocedure);
--   SELECT e.alert_type, e.state, count(*) FROM public.evaluate_client_alerts() e
--    GROUP BY 1, 2 ORDER BY 1, 2;
--
-- ロールバック（必要になったときだけ、新しい migration で。設計 §9）:
--   sleep_decline の行を resolved も含めてすべて DELETE → 両関数を 20260914000200 の定義に戻す →
--   CHECK を2種別に戻す（CHECK の ADD は全行を検証するので、resolved にするだけでは戻せない）
--
-- 冪等性: 1回だけ適用する前提。適用後にもう一度流すと、両関数の本体が変わっているので
--   0 のドリフトガードで止まる（REMOTE_DRIFT_SINCE_CAPTURE）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. ドリフトガード
--    本 migration は evaluate_client_alerts と run_client_alert_detection を 20260914000200 の
--    定義を土台に全文で作り直す。リモートで誰かが（migration を経ずに）本体を直していた場合に、
--    それを黙って上書きしないよう、作り直す前に本体（pg_proc.prosrc）の md5 を確かめ、
--    一致しなければ例外で migration 全体を止める。関数が存在しない場合も同じ例外で止める。
--
--    期待値（2026-10-03 に隔離ローカルとリモートの両方で一致を確認済み）:
--      evaluate_client_alerts     : 9c553a939d98fb60d58022897f6a5d4c
--      run_client_alert_detection : 0e80baea1335f09889edac7fc584836f
--    20260914000200 より後の migration は両関数に触れていないので、ローカルで全 migration を
--    流す順序（fresh DB）でもガードは通る。比較するのは本体だけ（SECURITY DEFINER /
--    search_path / ACL は本 migration が明示的に書き直し、5 の末尾の検査で確かめる）
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_fn  record;
  v_oid oid;
  v_md5 text;
BEGIN
  FOR v_fn IN
    SELECT t.signature, t.expected_md5
      FROM (VALUES
        (1, 'public.evaluate_client_alerts(date, timestamptz)', '9c553a939d98fb60d58022897f6a5d4c'),
        (2, 'public.run_client_alert_detection(date)',          '0e80baea1335f09889edac7fc584836f')
      ) AS t(ord, signature, expected_md5)
     ORDER BY t.ord
  LOOP
    v_oid := to_regprocedure(v_fn.signature);

    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
        USING ERRCODE = 'P0001',
              DETAIL  = format(
                'function %s does not exist (expected md5(prosrc)=%s, the definition of 20260914000200)',
                v_fn.signature, v_fn.expected_md5
              ),
              HINT    = '20260914000200 で作った関数がありません。リモートの現状を確かめてから migration を直してください。';
    END IF;

    SELECT md5(p.prosrc)
      INTO v_md5
      FROM pg_catalog.pg_proc p
     WHERE p.oid = v_oid;

    IF v_md5 IS DISTINCT FROM v_fn.expected_md5 THEN
      RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
        USING ERRCODE = 'P0001',
              DETAIL  = format(
                'function %s has md5(prosrc)=%s, expected %s (the definition of 20260914000200)',
                v_fn.signature, v_md5, v_fn.expected_md5
              ),
              HINT    = '関数本体が 20260914000200 の定義から変わっています。このまま適用すると CREATE OR REPLACE がその変更を上書きするため中止しました。リモートの関数の差分を調べてから migration を直してください。';
    END IF;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. alerts.alert_type の CHECK を作り直す（20260914000000 の方針どおり DROP → ADD）
--    ADD は既存の全行を検証するが、既存の値（weight_change / record_gap）はそのまま通る。
--    IF EXISTS は付けない（制約名が想定と違えば、ここで止めて気づけるようにする）
-- -----------------------------------------------------------------------------
ALTER TABLE public.alerts DROP CONSTRAINT alerts_alert_type_check;
ALTER TABLE public.alerts ADD CONSTRAINT alerts_alert_type_check
  CHECK (alert_type IN ('weight_change', 'record_gap', 'sleep_decline'));

-- -----------------------------------------------------------------------------
-- 2. alerts の列 COMMENT に睡眠悪化の説明を足す（全文で書き直す）
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN public.alerts.alert_type IS
  'weight_change（体重急変）/ record_gap（記録途絶）/ sleep_decline（睡眠悪化）。'
  '種別を増やすときは CHECK を DROP → ADD し、既存の値を落とさない';
COMMENT ON COLUMN public.alerts.severity IS
  'high / medium / low（low は将来用）。体重急変は high（purpose=diet の減少だけ medium）、'
  '記録途絶は途絶日数 3〜6 日が medium、7 日以上が high、睡眠悪化は常に medium';
COMMENT ON COLUMN public.alerts.payload IS
  '判定時点の値・閾値・期間・変種（v でバージョンを持つ。日付だけで時刻は持たない）。'
  'weight_change: {v:1, direction, recent:{from,to,avg_kg,days}, previous:{from,to,avg_kg,days}, '
  'delta_kg, delta_pct, threshold:{pct,kg}, severity_reason?}。'
  'record_gap: {v:1, variant:not_started|no_data|no_record, gap_from, gap_to, '
  'last_activity_on, last_record_on, threshold_days}（日数は gap_to − gap_from + 1 で表示時に出す）。'
  'sleep_decline: {v:1, triggers:[duration|wakeup], recent:{from,to,median_minutes,nights}, '
  'previous:{from,to,median_minutes,nights}, delta_minutes, wakeup:{avg,count}, '
  'threshold:{drop_minutes,min_nights,wakeup_avg,min_ratings}}'
  '（from は窓の実際の始まりで、登録直後は前の窓の from が to より後になる。窓が空なら median_minutes は null）。'
  '表示用の文字列は入れない';
COMMENT ON COLUMN public.alerts.last_detected_on IS
  '条件の成立を最後に確かめた対象日（JST の暦日）。weight_change と sleep_decline はこれが'
  '対象日の 14 日前以前になると resolved（expired）';
COMMENT ON COLUMN public.alerts.resolved_reason IS
  'cleared（条件が解消）/ expired（weight_change と sleep_decline は 14 日間再確認されない。'
  'record_gap は顧客が監視対象外 = 登録から 14 日を過ぎた未開始・最終到着から 14 日超 になって'
  '監視を打ち切った）/ reassigned（担当替え）/ ineligible（アプリ未登録・自己登録になった、'
  'または登録日が不正で評価できない）';

-- -----------------------------------------------------------------------------
-- 3. evaluate_client_alerts(p_target_date, p_as_of)
--    監視対象（client_activity_snapshot の exclusion_reason IS NULL）の顧客ごとに、
--    weight_change・record_gap・sleep_decline の3行を返す。state は
--      detected（成立）/ cleared（解消）/ unknown（評価できない・成立値と解消値の間。状態を変えない）
--    severity は detected のときだけ入る。payload は判定時点の値（alerts.payload の形）。
--
--    締め時刻の範囲: D の JST 0:00 以降、かつ now() 以前。範囲外は例外にする
--    （未来の対象日は、既定の締め時刻 now() が D の 0:00 より前になるのでここで弾かれる）。
--    過去の日 d に p_as_of = d の 06:00 JST を渡すと、「その朝に見えていたデータ」に近い状態を
--    再現できる（バックテスト）。監視対象は alerts に依らない（snapshot は登録日・記録・
--    メッセージだけで決まる）ので、バックテストは本実行の前後どちらで取っても同じになる
--
--    plpgsql にしたのは、定数を冒頭1箇所にまとめるのと、締め時刻の範囲を例外にするため。
--    戻り列名（client_id など）と表の列名が重なるので #variable_conflict use_column を付け、
--    そのうえで列はすべて別名で修飾する
--
--    20260914000200 からの変更は睡眠悪化（sleep_decline）の追加だけ:
--      - DECLARE に ③ の定数
--      - g_eval の後ろに s_night / s_window / s_eval / s_cond / s_state の CTE
--      - 3本目の UNION ALL
--    体重急変・記録途絶の判定と payload は変えない
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.evaluate_client_alerts(
  p_target_date date DEFAULT ((now() AT TIME ZONE 'Asia/Tokyo')::date),
  p_as_of timestamptz DEFAULT NULL
)
RETURNS TABLE (
  client_id uuid,
  trainer_id uuid,
  alert_type text,
  state text,
  severity text,
  payload jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
DECLARE
  -- ===== 定数（閾値・窓の長さ・日数はここ1箇所。根拠は計画書「検知ルールの仕様」と睡眠悪化の設計 §4）=====
  -- payload の形のバージョン（形を変えたら上げ、Web の describeAlert を合わせる）
  c_payload_version      constant integer := 1;

  -- ---- ① 体重急変 weight_change ----
  -- 見る期間は D−14〜D−1（登録日より前の計測は使わない）。直近の窓 D−7〜D−1 と前の窓
  -- D−14〜D−8 を比べる（カタログ 1-A）。06:00 時点では当日の計測はほとんど届かないので D−1 で閉じる
  c_weight_span_days     constant integer := 14;
  c_weight_recent_days   constant integer := 7;
  -- 各窓に代表値が 3 日以上あるときだけ評価する（実データでは窓の日数条件を外すと ±3% 超が
  -- 9日出るが、すべて1〜2日しかない窓だった）。登録日の下限と合わせ、評価できるのは D ≥ J + 10 から
  c_weight_min_days      constant integer := 3;
  -- 値の範囲（誤入力・単位違いを除く）
  c_weight_min_kg        constant numeric := 20;
  c_weight_max_kg        constant numeric := 300;
  -- 日ごとの代表値はその JST 日の中央値（1日に最大10件・20kg 幅の日がある）。さらに 14日分の
  -- 代表値の中央値から ±15% を超える日は外れ値として除く（60kg の人に誤計測の 80kg が1日混ざると、
  -- 7日平均が約 2.9kg 動いて閾値を超える）
  c_weight_outlier_ratio constant numeric := 0.15;
  -- 成立: |Δ%| ≥ 3.0 または |Δkg| ≥ 2.0（カタログの初期値のまま。実データ 42 client-day の
  -- 最大は 2.62% / 1.67kg で、±3% / ±2kg 超は0件）
  c_weight_pct           constant numeric := 3.0;
  c_weight_kg            constant numeric := 2.0;
  -- 解消: 評価でき、かつ |Δkg| と |Δ%| の両方が成立値の 8 割未満（1.6kg / 2.4%）。
  -- 成立値と解消値の間の日と、評価できない日は unknown（状態を変えない = ヒステリシス）
  c_weight_clear_ratio   constant numeric := 0.8;
  -- 重大度は high。purpose = 'diet' の減少だけ medium に下げる（設計判断10。検知は残す）
  c_weight_severity      constant text := 'high';
  c_weight_diet_severity constant text := 'medium';

  -- ---- ② 記録途絶 record_gap ----
  -- 3日以上で成立（カタログどおり）。3〜6日は medium、7日以上は high
  c_gap_days             constant integer := 3;
  c_gap_high_days        constant integer := 7;

  -- ---- ③ 睡眠悪化 sleep_decline（設計 docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md §4）----
  -- 晩 = sleep_records の1行（recorded_date は JST の起床日）。見る期間は起床日 D−14〜D−1 で、
  -- 直近の窓 D−7〜D−1 と前の窓 D−14〜D−8 を比べる。当日 D の晩は 06:00 時点ではほとんど届かない
  -- （到着遅れの中央値は約35時間）ので使わない。登録日より前の晩も使わない（初回連携で入る
  -- 過去30日分で、担当になる前の変化を検知しないため。体重と同じ理由）
  c_sleep_span_days      constant integer := 14;
  c_sleep_recent_days    constant integer := 7;
  -- 睡眠時間（total_sleep_minutes。HealthKit の値で覚醒時間を含む）は 120〜960 分（2〜16時間、
  -- 両端を含む）の晩だけを数える。範囲外は時計を外して寝た晩などの計測ミスとして除き、
  -- 晩の数にも入れない（実データは 273〜571 分で、範囲外は0件）
  c_sleep_min_minutes    constant integer := 120;
  c_sleep_max_minutes    constant integer := 960;
  -- 両方の窓に有効な晩が 4 晩以上あるときだけ睡眠時間を評価する（3晩どうしの比較は揺れが大きい。
  -- HealthKit の睡眠は毎晩入るので「週の半分以上」で満たしやすい）。評価できるのは D ≥ J + 11 から
  c_sleep_min_nights     constant integer := 4;
  -- 成立: 直近の窓の中央値 − 前の窓の中央値 ≤ −60 分（カタログの初期値）。窓ごとの代表値は
  -- 1晩の外れ値に強い中央値にする（平均だと、毎晩 383 分の人の前の窓に 803 分が1晩あるだけで
  -- 差がちょうど −60 になる。体重の ±15% の外れ値除外は、日ごとの揺れが大きい睡眠では普通の晩まで
  -- 除いてしまう）。判定は丸める前の差で行う（中央値は 0.5 分刻み。−59.5 は成立しない）
  c_sleep_drop_minutes   constant integer := 60;
  -- 解消: 差 > −48 分（成立値の 8 割。体重と同じヒステリシス）。−60 < 差 ≤ −48 は保留
  c_sleep_clear_ratio    constant numeric := 0.8;
  -- 目覚め評価（1 = だるい、2 = まあまあ、3 = すっきり）は直近の窓の平均を使う。3 回以上あるときだけ
  -- 評価し、平均 < 1.5 で成立（カタログどおり）、平均 ≥ 2.0（まあまあ以上）で解消、間は保留。
  -- 睡眠時間が範囲外・NULL の行の評価も数える（評価は顧客の申告で、睡眠時間とは独立）
  c_sleep_min_ratings    constant integer := 3;
  c_sleep_wakeup_avg     constant numeric := 1.5;
  c_sleep_wakeup_clear   constant numeric := 2.0;
  -- 重大度は常に medium（生活の兆候で、体重の急変ほど急ぎではない。上がることが無いので、
  -- 対応済みの行が再浮上することもない）
  c_sleep_severity       constant text := 'medium';

  v_d0    timestamptz;
  v_as_of timestamptz;
BEGIN
  IF p_target_date IS NULL THEN
    RAISE EXCEPTION 'evaluate_client_alerts: 対象日（p_target_date）が NULL です'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- D の JST 0:00（列に関数を掛けずに範囲比較するための境界）
  v_d0 := p_target_date::timestamp AT TIME ZONE 'Asia/Tokyo';
  v_as_of := coalesce(
    p_as_of,
    LEAST(now(), (p_target_date + 1)::timestamp AT TIME ZONE 'Asia/Tokyo')
  );

  IF v_as_of < v_d0 OR v_as_of > now() THEN
    RAISE EXCEPTION 'evaluate_client_alerts: 締め時刻 % が範囲外です（対象日 % の JST 0:00 以降、かつ現在時刻以前）',
      v_as_of, p_target_date
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  RETURN QUERY
  WITH snap AS MATERIALIZED (
    SELECT s.client_id, s.trainer_id, s.join_on, s.purpose,
           s.last_activity_on, s.last_record_on
      FROM public.client_activity_snapshot(p_target_date, v_as_of) AS s
     WHERE s.exclusion_reason IS NULL
  ),
  -- ---- ① 体重急変 ----
  -- 日ごとの代表値 = その JST 日の中央値。[max(D−14, J) の 0:00, D の 0:00) に計測され、
  -- 締め時刻までに届いた 20〜300kg の値だけを使う（source は問わない）
  w_day AS (
    SELECT sn.client_id,
           (w.recorded_at AT TIME ZONE 'Asia/Tokyo')::date AS day,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY w.weight))::numeric AS rep
      FROM snap sn
      JOIN public.weight_records w ON w.client_id = sn.client_id
     WHERE w.recorded_at >= (GREATEST(p_target_date - c_weight_span_days, sn.join_on)::timestamp
                             AT TIME ZONE 'Asia/Tokyo')
       AND w.recorded_at < v_d0
       AND coalesce(w.created_at, w.recorded_at) <= v_as_of
       AND w.weight >= c_weight_min_kg
       AND w.weight <= c_weight_max_kg
     GROUP BY sn.client_id, (w.recorded_at AT TIME ZONE 'Asia/Tokyo')::date
  ),
  w_median AS (
    SELECT d.client_id,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY d.rep))::numeric AS med
      FROM w_day d
     GROUP BY d.client_id
  ),
  -- 外れ値の日を除いてから、直近・前の窓ごとに日数と平均を出す
  w_window AS (
    SELECT d.client_id,
           count(*) FILTER (WHERE d.day >= p_target_date - c_weight_recent_days)  AS recent_days,
           avg(d.rep) FILTER (WHERE d.day >= p_target_date - c_weight_recent_days) AS recent_avg,
           count(*) FILTER (WHERE d.day <  p_target_date - c_weight_recent_days)  AS previous_days,
           avg(d.rep) FILTER (WHERE d.day <  p_target_date - c_weight_recent_days) AS previous_avg
      FROM w_day d
      JOIN w_median m ON m.client_id = d.client_id
     WHERE abs(d.rep - m.med) <= m.med * c_weight_outlier_ratio
     GROUP BY d.client_id
  ),
  w_eval AS (
    SELECT sn.client_id, sn.trainer_id, sn.purpose, sn.join_on,
           coalesce(ww.recent_days, 0)::integer   AS recent_days,
           ww.recent_avg,
           coalesce(ww.previous_days, 0)::integer AS previous_days,
           ww.previous_avg,
           -- Δkg = 直近の窓の平均 − 前の窓の平均、Δ% = Δkg ÷ 前の窓の平均 × 100（numeric で計算する）
           ww.recent_avg - ww.previous_avg                           AS delta_kg,
           (ww.recent_avg - ww.previous_avg) / ww.previous_avg * 100 AS delta_pct
      FROM snap sn
      LEFT JOIN w_window ww ON ww.client_id = sn.client_id
  ),
  w_state AS (
    SELECT we.*,
           CASE
             WHEN we.recent_days < c_weight_min_days
               OR we.previous_days < c_weight_min_days THEN 'unknown'
             WHEN abs(we.delta_pct) >= c_weight_pct
               OR abs(we.delta_kg) >= c_weight_kg THEN 'detected'
             WHEN abs(we.delta_pct) < c_weight_pct * c_weight_clear_ratio
              AND abs(we.delta_kg) < c_weight_kg * c_weight_clear_ratio THEN 'cleared'
             ELSE 'unknown'
           END AS st,
           coalesce(we.purpose = 'diet' AND we.delta_kg < 0, false) AS diet_decrease
      FROM w_eval we
  ),
  -- ---- ② 記録途絶 ----
  -- 上から1つだけ当てる（J = 登録日、R = 最終到着日、L = 最終記録日）
  --   1. L が NULL                → not_started: J 〜 D−1（N = D − J）
  --   2. (D−1) − R ≥ 3            → no_data    : R+1 〜 D−1
  --   3. それ以外                  → no_record  : max(L, J−1)+1 〜 min(R, D)−1
  --      （R より前は同期済みと見なせるので、そこで記録が無い日は「記録が無い」と確定できる。
  --        登録日より前は数えない）
  --   N = gap_to − gap_from + 1 が 3 以上なら detected、そうでなければ cleared
  g_base AS (
    SELECT sn.client_id, sn.trainer_id,
           sn.join_on          AS j,
           sn.last_activity_on AS r,
           sn.last_record_on   AS l,
           CASE
             WHEN sn.last_record_on IS NULL                                  THEN 'not_started'
             WHEN (p_target_date - 1) - sn.last_activity_on >= c_gap_days THEN 'no_data'
             ELSE 'no_record'
           END AS variant
      FROM snap sn
  ),
  g_span AS (
    SELECT g.*,
           CASE g.variant
             WHEN 'not_started' THEN g.j
             WHEN 'no_data'     THEN g.r + 1
             ELSE GREATEST(g.l, g.j - 1) + 1
           END AS gap_from,
           CASE g.variant
             WHEN 'no_record' THEN LEAST(g.r, p_target_date) - 1
             ELSE p_target_date - 1
           END AS gap_to
      FROM g_base g
  ),
  g_eval AS (
    SELECT gs.*, (gs.gap_to - gs.gap_from + 1) AS gap_days
      FROM g_span gs
  ),
  -- ---- ③ 睡眠悪化 ----
  -- 晩: 起床日が [max(D−14, J), D−1] で、締め時刻までに届いた行（source は問わない）。
  -- recorded_date は日付なので、体重のような JST 0:00 の境界への変換は要らない（±infinity の
  -- 日付も比較だけで落ちる）。valid = 睡眠時間が 120〜960 分（NULL・範囲外は false / NULL になり、
  -- 睡眠時間の集計の FILTER から外れる）
  s_night AS (
    SELECT sn.client_id,
           s.recorded_date       AS day,
           s.total_sleep_minutes AS minutes,
           s.wakeup_rating       AS rating,
           (s.total_sleep_minutes >= c_sleep_min_minutes
            AND s.total_sleep_minutes <= c_sleep_max_minutes) AS valid
      FROM snap sn
      JOIN public.sleep_records s ON s.client_id = sn.client_id
     WHERE s.recorded_date >= GREATEST(p_target_date - c_sleep_span_days, sn.join_on)
       AND s.recorded_date <= p_target_date - 1
       AND s.created_at <= v_as_of
  ),
  -- 窓ごとの有効な晩の数と中央値、直近の窓の目覚め評価の回数と平均。
  -- percentile_cont は double precision を返すので numeric にキャストしてから差・丸めを計算する
  -- （double precision の round は偶数丸めで、round(x, 2) も書けない）
  s_window AS (
    SELECT n.client_id,
           count(*) FILTER (WHERE n.valid AND n.day >= p_target_date - c_sleep_recent_days) AS recent_nights,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY n.minutes)
              FILTER (WHERE n.valid AND n.day >= p_target_date - c_sleep_recent_days))::numeric AS recent_median,
           count(*) FILTER (WHERE n.valid AND n.day < p_target_date - c_sleep_recent_days) AS previous_nights,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY n.minutes)
              FILTER (WHERE n.valid AND n.day < p_target_date - c_sleep_recent_days))::numeric AS previous_median,
           count(n.rating) FILTER (WHERE n.day >= p_target_date - c_sleep_recent_days) AS rating_count,
           avg(n.rating)   FILTER (WHERE n.day >= p_target_date - c_sleep_recent_days) AS rating_avg
      FROM s_night n
     GROUP BY n.client_id
  ),
  s_eval AS (
    SELECT sn.client_id, sn.trainer_id, sn.join_on,
           coalesce(sw.recent_nights, 0)::integer   AS recent_nights,
           sw.recent_median,
           coalesce(sw.previous_nights, 0)::integer AS previous_nights,
           sw.previous_median,
           -- Δ = 直近の窓の中央値 − 前の窓の中央値（分。丸める前の値。どちらかの窓が空なら NULL）
           sw.recent_median - sw.previous_median    AS delta_minutes,
           coalesce(sw.rating_count, 0)::integer    AS rating_count,
           sw.rating_avg
      FROM snap sn
      LEFT JOIN s_window sw ON sw.client_id = sn.client_id
  ),
  -- 条件ごとの状態: none（なし）/ insufficient（不足）/ met（成立）/ pending（保留）/ cleared（解消）
  s_cond AS (
    SELECT se.*,
           CASE
             WHEN se.recent_nights + se.previous_nights = 0                    THEN 'none'
             WHEN se.recent_nights < c_sleep_min_nights
               OR se.previous_nights < c_sleep_min_nights                      THEN 'insufficient'
             WHEN se.delta_minutes <= -c_sleep_drop_minutes                    THEN 'met'
             WHEN se.delta_minutes > -c_sleep_drop_minutes * c_sleep_clear_ratio THEN 'cleared'
             ELSE 'pending'
           END AS duration_st,
           CASE
             WHEN se.rating_count = 0                    THEN 'none'
             WHEN se.rating_count < c_sleep_min_ratings  THEN 'insufficient'
             WHEN se.rating_avg < c_sleep_wakeup_avg     THEN 'met'
             WHEN se.rating_avg >= c_sleep_wakeup_clear  THEN 'cleared'
             ELSE 'pending'
           END AS wakeup_st
      FROM s_eval se
  ),
  -- 全体の状態（上から順に当てる。設計 §4.4 の表）
  --   1. どちらかが成立 → detected
  --   2. 睡眠時間が保留・不足、または目覚め評価が保留 → unknown
  --      （睡眠時間の不足で解消させない: 到着遅れで直近の窓が3晩になる日に目覚め評価だけで解消すると、
  --        翌日に遅れた晩が届いて行が作り直される）
  --   3. どちらかが解消 → cleared（睡眠時間が解消なら、目覚め評価のなし・不足は解消を止めない）
  --   4. それ以外（どちらもなし、睡眠時間がなしで目覚め評価が不足など）→ unknown
  s_state AS (
    SELECT sc.*,
           CASE
             WHEN sc.duration_st = 'met' OR sc.wakeup_st = 'met'         THEN 'detected'
             WHEN sc.duration_st IN ('pending', 'insufficient')
               OR sc.wakeup_st = 'pending'                               THEN 'unknown'
             WHEN sc.duration_st = 'cleared' OR sc.wakeup_st = 'cleared' THEN 'cleared'
             ELSE 'unknown'
           END AS st
      FROM s_cond sc
  )
  SELECT ws.client_id,
         ws.trainer_id,
         'weight_change'::text,
         ws.st,
         CASE WHEN ws.st = 'detected' THEN
           CASE WHEN ws.diet_decrease THEN c_weight_diet_severity ELSE c_weight_severity END
         END,
         jsonb_build_object(
           'v', c_payload_version,
           'direction', CASE WHEN ws.delta_kg > 0 THEN 'increase'
                             WHEN ws.delta_kg < 0 THEN 'decrease' END,
           'recent', jsonb_build_object(
             'from',   p_target_date - c_weight_recent_days,
             'to',     p_target_date - 1,
             'avg_kg', round(ws.recent_avg, 2),
             'days',   ws.recent_days),
           'previous', jsonb_build_object(
             'from',   GREATEST(p_target_date - c_weight_span_days, ws.join_on),
             'to',     p_target_date - c_weight_recent_days - 1,
             'avg_kg', round(ws.previous_avg, 2),
             'days',   ws.previous_days),
           'delta_kg',  round(ws.delta_kg, 2),
           'delta_pct', round(ws.delta_pct, 2),
           'threshold', jsonb_build_object('pct', c_weight_pct, 'kg', c_weight_kg)
         )
         || CASE WHEN ws.st = 'detected' AND ws.diet_decrease
                 THEN jsonb_build_object('severity_reason', 'diet_decrease')
                 ELSE '{}'::jsonb END
    FROM w_state ws
  UNION ALL
  SELECT ge.client_id,
         ge.trainer_id,
         'record_gap'::text,
         CASE WHEN ge.gap_days >= c_gap_days THEN 'detected' ELSE 'cleared' END,
         CASE WHEN ge.gap_days >= c_gap_high_days THEN 'high'
              WHEN ge.gap_days >= c_gap_days      THEN 'medium' END,
         jsonb_build_object(
           'v',                c_payload_version,
           'variant',          ge.variant,
           'gap_from',         ge.gap_from,
           'gap_to',           ge.gap_to,
           'last_activity_on', ge.r,
           'last_record_on',   ge.l,
           'threshold_days',   c_gap_days
         )
    FROM g_eval ge
  UNION ALL
  SELECT ss.client_id,
         ss.trainer_id,
         'sleep_decline'::text,
         ss.st,
         CASE WHEN ss.st = 'detected' THEN c_sleep_severity END,
         jsonb_build_object(
           'v', c_payload_version,
           -- 成立した条件（並びは duration → wakeup）。detected のときだけ1つ以上入り、それ以外は []
           'triggers', to_jsonb(array_remove(ARRAY[
             CASE WHEN ss.duration_st = 'met' THEN 'duration' END,
             CASE WHEN ss.wakeup_st   = 'met' THEN 'wakeup'   END
           ]::text[], NULL)),
           -- from は窓の実際の始まり（登録直後は前の窓の from が to より後になり、nights は 0）。
           -- 中央値は整数に丸める（numeric の round は 0 から遠い方へ: 340.5 → 341）。窓が空なら null
           'recent', jsonb_build_object(
             'from',           GREATEST(p_target_date - c_sleep_recent_days, ss.join_on),
             'to',             p_target_date - 1,
             'median_minutes', round(ss.recent_median),
             'nights',         ss.recent_nights),
           'previous', jsonb_build_object(
             'from',           GREATEST(p_target_date - c_sleep_span_days, ss.join_on),
             'to',             p_target_date - c_sleep_recent_days - 1,
             'median_minutes', round(ss.previous_median),
             'nights',         ss.previous_nights),
           -- 丸める前の中央値どうしの差を丸めたもの（丸めた値どうしの差ではない。−59.5 → −60）
           'delta_minutes', round(ss.delta_minutes),
           'wakeup', jsonb_build_object(
             'avg',   round(ss.rating_avg, 2),
             'count', ss.rating_count),
           'threshold', jsonb_build_object(
             'drop_minutes', c_sleep_drop_minutes,
             'min_nights',   c_sleep_min_nights,
             'wakeup_avg',   c_sleep_wakeup_avg,
             'min_ratings',  c_sleep_min_ratings)
         )
    FROM s_state ss;
END;
$$;

COMMENT ON FUNCTION public.evaluate_client_alerts(date, timestamptz) IS
  '異常検知の評価（読み取り専用。dry run とバックテストを兼ねる）。'
  '監視対象（client_activity_snapshot の exclusion_reason IS NULL）の顧客ごとに、'
  'weight_change・record_gap・sleep_decline の3行 (client_id, trainer_id, alert_type, state, severity, payload) を返す。'
  'state: detected / cleared / unknown（評価できない・成立値と解消値の間。状態を変えない）。'
  'severity は detected のときだけ。p_target_date は JST の暦日（既定は JST の今日）、'
  'p_as_of は締め時刻（既定は LEAST(now(), D+1 の JST 0:00)。D の JST 0:00 より前・now() より後は例外）。'
  '閾値・窓・日数の定数は関数の冒頭1箇所にある。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「検知ルールの仕様」、'
  '睡眠悪化は docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md §4';

REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_client_alerts(date, timestamptz) TO service_role;
```

- [ ] **Step 3b: 既存テスト `client_alert_detection_test.sql` の case (e) を直す**（評価が1顧客3行になるため。直さないと Task 1 のコミットで既存テストが落ちる）

(e) 631〜637 行目:

old:
```sql
  -- 監視対象の顧客は2行（weight_change と record_gap）ずつ返る
  SELECT count(*) INTO cnt FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000001';
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: (e) 監視対象の顧客の評価が % 行（期待 2 行 = 種別ごと）', cnt;
  END IF;
  RAISE NOTICE 'OK: 対象外（auth 無し / 自己登録 / 最終到着 D−15）は評価せず、監視対象は種別ごとに2行';
```
new:
```sql
  -- 監視対象の顧客は3行（weight_change・record_gap・sleep_decline）ずつ返る
  SELECT count(*) INTO cnt FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000001';
  IF cnt <> 3 THEN
    RAISE EXCEPTION 'FAIL: (e) 監視対象の顧客の評価が % 行（期待 3 行 = 種別ごと）', cnt;
  END IF;
  RAISE NOTICE 'OK: 対象外（auth 無し / 自己登録 / 最終到着 D−15）は評価せず、監視対象は種別ごとに3行';
```

- [ ] **Step 4: 適用してテストが通ることを確かめる**

Run:
```bash
SP=/private/tmp/claude-501/-Users-hoshidayuuya-Documents-FIT-CONNECT/ab68eea9-a74a-49fb-b328-1a51c801b004/scratchpad
rsync -a --delete supabase/migrations/ $SP/sleep-stack/supabase/migrations/
(cd $SP/sleep-stack && supabase db reset)   # 隔離スタック fitconnect-sleep101 だけが作り直される。リポジトリ内で実行しないこと
docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/sleep_decline_alert_test.sql
docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/client_alert_detection_test.sql 2>&1 | grep -E "FAIL|ERROR|PASSED"
```
Expected:
- 既存の検知テストは `ALL CLIENT ALERT DETECTION TESTS PASSED` だけが出る（case (e) は3行、run の stats はまだ変えていないので case (j) も通る）
- `supabase db reset` の出力に `Applying migration 20261003000000_alert_sleep_decline.sql...` が出て、エラー無しで終わる（エラーが出たら migration の書き写し間違い。ドリフトガードの `REMOTE_DRIFT_SINCE_CAPTURE` なら、`sleep-stack` の migrations に古いファイルが残っていないか `rsync --delete` を確かめる）
- テストは終了コード 0 で、`WARNING` / `ERROR` が無く、次の行が出る（行頭の `psql:<stdin>:NNN: ` は省略）:
```
--- setup: 共通の試験データ作成 (trainer T・XS)
--- 第1部 setup: evaluate 用の試験用顧客 01〜28 と XS
--- case 23: alerts.alert_type の CHECK が sleep_decline を受け付け、未知の値を拒むこと
NOTICE:  OK: CHECK は weight_change / record_gap / sleep_decline を受け付け、未知の値（sleep_quality）を alerts_alert_type_check で拒む
--- case 1: 睡眠時間が成立（前 7晩・直近 5晩、Δ −70）→ detected・medium・triggers ["duration"]・payload の全体
NOTICE:  OK: 前 7晩（中央値 400）・直近 5晩（330）で Δ −70 → detected・medium、payload は設計 §4.6 の形
--- case 2-4: Δ −60 は成立・−59.5 は保留 / −47 は解消・−48 は保留 / 直近3晩は評価しない
NOTICE:  OK: Δ −60 は detected、−59.5 は unknown（delta_minutes −60）、−47 は cleared、−48 は unknown、直近3晩は unknown
--- case 5-7: 119 / 961 分は数えず 120 / 960 分は数える / 1晩の外れ値では成立しない / D−8 は前・D−7 は直近・D−15 は外
NOTICE:  OK: 範囲は 120〜960 分（両端を含む）、1晩の外れ値は中央値で吸収、窓の境界は D−14 / D−8 / D−7 / D−1
--- case 8-10: 登録日より前の晩は数えない（J+10 は評価しない・J+11 は評価する）/ 締め時刻より後に届いた晩・当日と未来の晩・顧客が書いた異常値は数えない
NOTICE:  OK: 登録前の晩は数えず J+10 は unknown・J+11 は detected。締め時刻より後に届いた晩・当日 D と未来の晩・±infinity の晩は数えない
--- case 11-12: delta_minutes は丸める前の差を丸める / 目覚め評価だけで成立（前の窓は nights 0、登録直後も）
NOTICE:  OK: delta_minutes は round(340.5 − 400) = −60 で unknown。目覚め評価だけで detected（triggers ["wakeup"]・前の窓 nights 0。登録直後は from が実際の期間）
--- case 13-15: 目覚め評価 1.5 ちょうどは保留・2.0 は解消 / 両方成立 / §4.4 の表の組み合わせ
NOTICE:  OK: 目覚め評価 1.5 は保留・2.0 は解消、両方成立は triggers ["duration","wakeup"]、§4.4 の表の7通りが期待どおり（不足 + 解消は unknown）
--- case 16: no_account・self には行が無く、データの無い監視対象には unknown の行がある（1名3行）。全行の不変条件
NOTICE:  OK: no_account・self は評価せず、データの無い監視対象は unknown。監視対象は3行ずつ、全行で detected ⇔ medium ⇔ triggers あり
ALL SLEEP DECLINE ALERT TESTS PASSED
```

補足: 一字一句この計画どおりなら、適用後の `SELECT md5(prosrc) FROM pg_proc WHERE proname = 'evaluate_client_alerts'` は `f9da5a2ab0ed75c6e3eb6cede096f41b`（`run_client_alert_detection` は `0e80baea1335f09889edac7fc584836f` のまま）。テストでは固定しない参考値（ロールバック用 migration のドリフトガードに使える）。

- [ ] **Step 5: コミットする**

```bash
git add supabase/migrations/20261003000000_alert_sleep_decline.sql supabase/tests/sleep_decline_alert_test.sql supabase/tests/client_alert_detection_test.sql
git commit -m "$(cat <<'EOF'
feat(supabase): 睡眠悪化アラートの評価と alert_type の CHECK を追加（フェーズ9.1 拡張）

evaluate_client_alerts に睡眠時間（中央値の比較）と目覚め評価の判定を3本目の種別として足し、
alerts.alert_type の CHECK に sleep_decline を加える。先頭に関数本体のドリフトガードを置く。

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 本実行の関数と既存テスト

**Files:**
- Modify: `supabase/migrations/20261003000000_alert_sleep_decline.sql`（580 行目の後ろに追記 → 581-987: 4 `run_client_alert_detection`・5 末尾の検査）
- Modify: `supabase/tests/sleep_decline_alert_test.sql:24`・`:48`・`:62`（ヘッダー）と `:654-659`（最後の `ROLLBACK;` の前に第2部・第3部を挿入。完成後 976 行）
- Modify: `supabase/tests/client_alert_detection_test.sql:1346`（case (j)）

**Interfaces:**
- Consumes: Task 1 の `public.evaluate_client_alerts(date, timestamptz)` の戻り（`alert_type = 'sleep_decline'`、`state`、`severity`、`payload`）と CHECK `alerts_alert_type_check`
- Produces:
  - `public.run_client_alert_detection(p_target_date date) RETURNS jsonb` — 戻り値 `{target_date, as_of, stats}`。`stats.detected.sleep_decline` は detected の件数（数値）。他の stats のキーは変えない
  - 期限切れ: 生きている `sleep_decline` で `last_detected_on <= p_target_date - 14` → `status = 'resolved'`、`resolved_reason = 'expired'`（`stats.resolved.expired` に数える）
  - alerts の `sleep_decline` の行（`severity = 'medium'`、`payload` は Task 1 の形）。Web の「今日の対応」がそのまま読む

**`run_client_alert_detection` の既存（`20260914000200`）からの差分**（本体の他の行は一字一句同じ）:
- DECLARE に `c_sleep_expire_days constant integer := 14;` と `n_sleep_expired integer;`
- 期限切れの段に 3-3（`alert_type = 'sleep_decline'` かつ `last_detected_on <= p_target_date - c_sleep_expire_days` → resolved（expired））。件数は `n_expired` に足す
- `v_detected` の `jsonb_build_object` に `'sleep_decline', count(*) FILTER (WHERE e.alert_type = 'sleep_decline' AND e.state = 'detected')`
- 関数の COMMENT に `detected.sleep_decline` と、expired の対象に `sleep_decline` を足し、睡眠悪化の設計への参照を足した
- 関数の前のブロックコメントに 3-3 と差分の説明を足した
- 新しいセクション 5（末尾の検査の DO ブロック）を足した

- [ ] **Step 1: 新しいテストに本実行のケースを足す**

`supabase/tests/sleep_decline_alert_test.sql` を次の4か所で直す。

(1) 24 行目（方針）:

old:
```sql
--   - 関数は postgres（cron と同じ実行ロール）で呼ぶ
```
new:
```sql
--   - 関数は postgres（cron と同じ実行ロール）で呼ぶ
--   - 本実行のシナリオ（第2部）は、シナリオごとに顧客を作り、終わったら顧客（CASCADE で睡眠の記録・
--     alerts も）と alert_detection_runs を消してから次へ進む（「最後の本実行より前は例外」のガードと、
--     他のシナリオの本実行で状態が動かないようにするため）
```

(2) 48 行目（検証ケースの一覧の最後）:

old:
```sql
--        （監視対象1名につき3行）。全行で「detected ⇔ medium ⇔ triggers が空でない」・severity_reason なし
```
new:
```sql
--        （監視対象1名につき3行）。全行で「detected ⇔ medium ⇔ triggers が空でない」・severity_reason なし
--   第2部 run
--   (17) 新規 → open・medium・surfaced_on = D。同じ D の再実行は件数が増えない
--   (18) 保留（unknown）の日は status・last_detected_on・payload が変わらない
--   (19) 後の日に cleared → resolved（cleared）
--   (20) 期限切れ: last_detected_on = D − 14 の生きている行は expired、D − 13 は残る（評価は unknown）。
--        評価されない（inactive）顧客の古い行も expired
--   (21) 対応済みの行は、成立が続いても対応済みのまま
--   (22) stats に detected.sleep_decline（数値）がある
--   第3部 登録内容
--   (24) 再定義の後も両関数が SECURITY DEFINER・search_path = ''、EXECUTE は service_role だけ（proacl と PUBLIC を含めて）
```

(3) 62 行目:

old:
```sql
--   client  NN : cccccccc-1003-0001-0000-0000000000NN（第1部 01〜28）
```
new:
```sql
--   client  NN : cccccccc-1003-0001-0000-0000000000NN（第1部 01〜28、第2部 41・51〜53）
```

(4) 「第1部の顧客を片付ける」の DELETE 文（654〜657 行目）の直後、最後の `ROLLBACK;`（659 行目）の直前に、次のブロックをそのまま挿入する。つまり

old:
```sql
    OR client_id = 'aaaaaaaa-1003-0001-0000-00000000000d';

ROLLBACK;
```
new: 1行目（`    OR client_id = 'aaaaaaaa-1003-0001-0000-00000000000d';`）→ 空行 → 次のブロック → 空行 → `ROLLBACK;` の順

```sql
-- =============================================================================
-- 第2部-1: 状態遷移（ケース 17・18・19・21・22）
--   41 S1: 登録 07-01。09-06〜09-12 は 400、09-13〜09-19 は 330、09-26〜09-29 は 400（どれも起床日の 08:00 JST に届く）
--   本実行: 09-20 → 09-20（再実行）→ 対応済み → 09-21 → 09-26 → 09-30
--     09-20: 前 400×7・直近 330×7 → detected（新規）
--     09-21: 前 [400×6, 330]（400）・直近 330×6 → detected（対応済みのまま継続）
--     09-26: 直近の窓（09-19〜09-25）は 09-19 の1晩だけ → unknown（何も変えない）
--     09-30: 前（09-16〜09-22）330×4・直近（09-23〜09-29）400×4 → Δ +70 で cleared
-- =============================================================================
\echo '--- 第2部-1 setup: 状態遷移用の顧客 S1'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('cccccccc-1003-0001-0000-000000000041', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sleep-alert-test-c41@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('cccccccc-1003-0001-0000-000000000041', '睡眠テスト顧客41',
   'aaaaaaaa-1003-0001-0000-00000000000a', '2026-07-01 12:00+09');

INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT 'cccccccc-1003-0001-0000-000000000041', g.d::date, r.minutes, NULL, 'healthkit',
       (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo',
       (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'
  FROM (VALUES
    ('2026-09-06', '2026-09-12', 400),
    ('2026-09-13', '2026-09-19', 330),
    ('2026-09-26', '2026-09-29', 400)
  ) AS r(from_day, to_day, minutes)
 CROSS JOIN LATERAL generate_series(r.from_day::date, r.to_day::date, interval '1 day') AS g(d);

\echo '--- case 17・22: 新規は open・medium・surfaced_on = D、stats に detected.sleep_decline。同じ D の再実行で件数が増えない'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  v_res := public.run_client_alert_detection('2026-09-20');

  -- (22) stats の detected に sleep_decline（数値。S1 の1件以上）
  IF NOT (v_res->'stats'->'detected' ? 'sleep_decline')
     OR jsonb_typeof(v_res->'stats'->'detected'->'sleep_decline') IS DISTINCT FROM 'number'
     OR (v_res->'stats'->'detected'->>'sleep_decline')::int < 1 THEN
    RAISE EXCEPTION 'FAIL: (22) stats に detected.sleep_decline（数値・1以上）が無い: %', v_res->'stats';
  END IF;

  -- (17) 新規: open・medium・first_detected_on = surfaced_on = last_detected_on = D
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000041' AND a.alert_type = 'sleep_decline';
  IF r.id IS NULL OR r.status <> 'open' OR r.severity <> 'medium'
     OR r.trainer_id <> 'aaaaaaaa-1003-0001-0000-00000000000a'
     OR (r.first_detected_on, r.surfaced_on, r.last_detected_on)
        IS DISTINCT FROM ('2026-09-20'::date, '2026-09-20'::date, '2026-09-20'::date)
     OR r.reopened_count <> 0 OR r.acknowledged_at IS NOT NULL OR r.resolved_at IS NOT NULL
     OR r.payload->'triggers' IS DISTINCT FROM '["duration"]'::jsonb
     OR (r.payload->>'delta_minutes')::numeric IS DISTINCT FROM -70
     OR (r.payload->'recent'->>'median_minutes')::numeric IS DISTINCT FROM 330
     OR (r.payload->'previous'->>'median_minutes')::numeric IS DISTINCT FROM 400 THEN
    RAISE EXCEPTION 'FAIL: (17) 睡眠悪化の新規行が期待と異なる: %', row_to_json(r);
  END IF;
  PERFORM set_config('sleep_test.s1_id', r.id::text, true);

  -- (17) 同じ D の再実行: 行は増えず同じ行のまま、新規 0
  v_res := public.run_client_alert_detection('2026-09-20');
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000041' AND a.alert_type = 'sleep_decline';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (17) 同じ D の再実行で sleep_decline の行が % 件になった（期待 1 件）', cnt;
  END IF;
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000041' AND a.alert_type = 'sleep_decline';
  IF r.id <> current_setting('sleep_test.s1_id')::uuid OR r.status <> 'open' OR r.surfaced_on <> '2026-09-20' THEN
    RAISE EXCEPTION 'FAIL: (17) 同じ D の再実行で行が変わった: %', row_to_json(r);
  END IF;
  IF (v_res->'stats'->>'opened')::int <> 0 THEN
    RAISE EXCEPTION 'FAIL: (17) 同じ D の再実行で新規が % 件（期待 0）: %', v_res->'stats'->>'opened', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: 09-20 に open・medium・surfaced_on 09-20 で作成、stats.detected.sleep_decline = %。再実行で件数は増えない', v_res->'stats'->'detected'->>'sleep_decline';
END $$;

-- ---- トレーナーが S1 を「対応済み」にする（API Route の条件付き UPDATE と同じ形）----
DO $$
DECLARE n int;
BEGIN
  UPDATE public.alerts
     SET status = 'acknowledged', acknowledged_at = now()
   WHERE id = current_setting('sleep_test.s1_id')::uuid AND status = 'open';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: S1 を対応済みにできない（% 行）', n;
  END IF;
END $$;

\echo '--- case 21・18: 対応済みは成立が続いても対応済みのまま / 保留（unknown）の日は status・last_detected_on・payload が変わらない'

DO $$
DECLARE
  r         record;
  v_payload jsonb;
  v_state   text;
BEGIN
  -- (21) 09-21 も成立（重大度は medium のまま上がらない）→ acknowledged のまま、last_detected_on と payload だけ進む
  PERFORM public.run_client_alert_detection('2026-09-21');
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('sleep_test.s1_id')::uuid;
  IF r.status <> 'acknowledged' OR r.acknowledged_at IS NULL OR r.reopened_count <> 0
     OR r.severity <> 'medium' OR r.surfaced_on <> '2026-09-20' OR r.last_detected_on <> '2026-09-21'
     OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 6
     OR r.payload->'recent'->>'from' IS DISTINCT FROM '2026-09-14' THEN
    RAISE EXCEPTION 'FAIL: (21) 成立が続いた対応済みの S1 が期待と異なる（acknowledged のまま・last_detected_on 09-21）: %', row_to_json(r);
  END IF;
  v_payload := r.payload;

  -- (18) 09-26 は直近の窓が1晩で評価できない（unknown）
  SELECT e.state INTO v_state FROM public.evaluate_client_alerts('2026-09-26') e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000041' AND e.alert_type = 'sleep_decline';
  IF v_state IS DISTINCT FROM 'unknown' THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — 09-26 の S1 の評価が %（期待 unknown）', v_state;
  END IF;
  PERFORM public.run_client_alert_detection('2026-09-26');
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('sleep_test.s1_id')::uuid;
  IF r.status <> 'acknowledged' OR r.resolved_at IS NOT NULL OR r.last_detected_on <> '2026-09-21'
     OR r.payload IS DISTINCT FROM v_payload THEN
    RAISE EXCEPTION 'FAIL: (18) 保留（unknown）の日に S1 が変わった: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'OK: 対応済みの S1 は 09-21 の成立でも acknowledged のまま（last_detected_on 09-21）。09-26 の unknown では何も変わらない';
END $$;

\echo '--- case 19: 後の日に cleared → resolved（cleared）'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  v_res := public.run_client_alert_detection('2026-09-30');
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('sleep_test.s1_id')::uuid;
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'cleared' OR r.resolved_at IS NULL
     OR r.last_detected_on <> '2026-09-21' THEN
    RAISE EXCEPTION 'FAIL: (19) 睡眠が戻った S1 が resolved（cleared）になっていない: %', row_to_json(r);
  END IF;
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000041' AND a.alert_type = 'sleep_decline'
     AND a.resolved_at IS NULL;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (19) 解消した後も S1 に生きている sleep_decline が % 件ある', cnt;
  END IF;
  IF (v_res->'stats'->'resolved'->>'cleared')::int < 1 THEN
    RAISE EXCEPTION 'FAIL: (19) stats の resolved.cleared が 1 未満: %', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: 09-30 に Δ +70 で S1 は resolved（cleared）';
END $$;

-- 第2部-1 の片付け
DELETE FROM public.clients WHERE client_id::text LIKE 'cccccccc-1003-0001-%';
DELETE FROM public.alert_detection_runs;

-- =============================================================================
-- 第2部-2: 期限切れ（ケース 20。D = 2026-09-30、D−14 = 09-16、D−13 = 09-17）
--   51: 監視対象・直近の窓が2晩（09-27・09-28）で unknown。生きている sleep_decline（open）、
--       last_detected_on = 09-16（D−14）→ expired
--   52: 51 と同じデータ。生きている sleep_decline（acknowledged）、last_detected_on = 09-17（D−13）→ 残る
--   53: inactive（最終到着 08-01）で評価されない。生きている sleep_decline（open）、
--       last_detected_on = 09-10 → expired（監視対象から外れた顧客の行も閉じる）
--   どれも評価は cleared にならない（cleared だと期限切れの前に解消で閉じてしまう）
-- =============================================================================
\echo '--- 第2部-2 setup: 期限切れ用の顧客 51・52・53'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-1003-0001-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'sleep-alert-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['51','52','53']) AS n;

INSERT INTO public.clients (client_id, name, trainer_id, created_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || n)::uuid, '睡眠テスト顧客' || n,
       'aaaaaaaa-1003-0001-0000-00000000000a', '2026-07-01 12:00+09'
  FROM unnest(ARRAY['51','52','53']) AS n;

INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || v.n)::uuid, v.day::date, 400, NULL, 'healthkit',
       (v.day::date + time '08:00') AT TIME ZONE 'Asia/Tokyo',
       (v.day::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'
  FROM (VALUES
    ('51', '2026-09-27'), ('51', '2026-09-28'),
    ('52', '2026-09-27'), ('52', '2026-09-28'),
    ('53', '2026-08-01')
  ) AS v(n, day);

INSERT INTO public.alerts (
  trainer_id, client_id, alert_type, severity, status, payload,
  first_detected_on, surfaced_on, last_detected_on, acknowledged_at
) VALUES
  ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000051',
   'sleep_decline', 'medium', 'open', '{"v":1}', '2026-09-10', '2026-09-10', '2026-09-16', NULL),
  ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000052',
   'sleep_decline', 'medium', 'acknowledged', '{"v":1}', '2026-09-10', '2026-09-10', '2026-09-17', now()),
  ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000053',
   'sleep_decline', 'medium', 'open', '{"v":1}', '2026-09-05', '2026-09-05', '2026-09-10', NULL);

\echo '--- case 20: last_detected_on = D−14 の生きている sleep_decline は expired、D−13 は残る（評価は unknown）。評価されない顧客の行も expired'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  v_bad text;
BEGIN
  -- 前提: 51・52 の評価は unknown（cleared ではない）、53 は評価されない（inactive）
  SELECT string_agg(format('%s: %s', e.client_id, e.state), ', ') INTO v_bad
    FROM public.evaluate_client_alerts('2026-09-30') e
   WHERE e.alert_type = 'sleep_decline'
     AND ((e.client_id IN ('cccccccc-1003-0001-0000-000000000051', 'cccccccc-1003-0001-0000-000000000052')
           AND e.state <> 'unknown')
          OR e.client_id = 'cccccccc-1003-0001-0000-000000000053');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — 期限切れ用の顧客の評価が期待（51・52 は unknown、53 は評価なし）と異なる: %', v_bad;
  END IF;

  v_res := public.run_client_alert_detection('2026-09-30');

  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000051';
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'expired' OR r.last_detected_on <> '2026-09-16' THEN
    RAISE EXCEPTION 'FAIL: (20) last_detected_on = D−14 の sleep_decline が expired になっていない: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000052';
  IF r.resolved_at IS NOT NULL OR r.status <> 'acknowledged' OR r.last_detected_on <> '2026-09-17' THEN
    RAISE EXCEPTION 'FAIL: (20) last_detected_on = D−13 の sleep_decline が閉じられた / 変わった: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000053';
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'expired' THEN
    RAISE EXCEPTION 'FAIL: (20) 評価されない（inactive）顧客の古い sleep_decline が expired になっていない: %', row_to_json(r);
  END IF;
  IF (v_res->'stats'->'resolved'->>'expired')::int < 2 THEN
    RAISE EXCEPTION 'FAIL: (20) stats の resolved.expired が 2 未満（51 と 53）: %', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: D−14 の sleep_decline は expired、D−13 は acknowledged のまま。inactive の顧客の古い行も expired';
END $$;

-- 第2部-2 の片付け
DELETE FROM public.clients WHERE client_id::text LIKE 'cccccccc-1003-0001-%';
DELETE FROM public.alert_detection_runs;

-- =============================================================================
-- 第3部: 登録内容（ケース 24）
-- =============================================================================
\echo '--- case 24: 両関数が SECURITY DEFINER・search_path = ""、EXECUTE は service_role だけ（proacl と PUBLIC を含めて）'

DO $$
DECLARE
  v_fn       regprocedure;
  r          record;
  v_grantees text[];
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.evaluate_client_alerts(date, timestamptz)'::regprocedure,
    'public.run_client_alert_detection(date)'::regprocedure
  ] LOOP
    SELECT p.prosecdef, p.proconfig, p.proacl INTO r FROM pg_proc p WHERE p.oid = v_fn;
    IF NOT r.prosecdef THEN
      RAISE EXCEPTION 'FAIL: (24) % が SECURITY DEFINER になっていない', v_fn;
    END IF;
    IF r.proconfig IS NULL OR NOT ('search_path=""' = ANY (r.proconfig)) THEN
      RAISE EXCEPTION 'FAIL: (24) % の search_path が空文字に固定されていない（proconfig=%）',
        v_fn, coalesce(r.proconfig::text, 'NULL');
    END IF;
    -- proacl が NULL = 既定権限（PUBLIC に EXECUTE）
    IF r.proacl IS NULL THEN
      RAISE EXCEPTION 'FAIL: (24) % の proacl が NULL（既定権限 = PUBLIC に EXECUTE が付いたまま）', v_fn;
    END IF;
    -- EXECUTE を持つのはオーナー（postgres）と service_role だけ（PUBLIC = grantee 0 を含めて数える）
    SELECT array_agg(g.grantee_name ORDER BY g.grantee_name) INTO v_grantees
      FROM (
        SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END AS grantee_name
          FROM pg_proc p, aclexplode(p.proacl) AS a
         WHERE p.oid = v_fn AND a.privilege_type = 'EXECUTE'
      ) g;
    IF v_grantees IS DISTINCT FROM ARRAY['postgres', 'service_role'] THEN
      RAISE EXCEPTION 'FAIL: (24) % の EXECUTE の付与先が %（期待 {postgres,service_role}）', v_fn, v_grantees;
    END IF;
    IF has_function_privilege('anon', v_fn, 'EXECUTE')
       OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL: (24) % の EXECUTE 権限が期待（anon・authenticated なし、service_role あり）と異なる', v_fn;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: evaluate_client_alerts・run_client_alert_detection は SECURITY DEFINER + search_path = ""、EXECUTE は postgres と service_role だけ';
END $$;
```

- [ ] **Step 2: 既存テスト `client_alert_detection_test.sql` の case (j) を直す**（case (e) は Task 1 の Step 3b で直し済み）

(j) 1346 行目:

old:
```sql
     OR NOT (v_stats->'detected' ?& ARRAY['weight_change', 'record_gap'])
```
new:
```sql
     OR NOT (v_stats->'detected' ?& ARRAY['weight_change', 'record_gap', 'sleep_decline'])
     OR jsonb_typeof(v_stats->'detected'->'sleep_decline') IS DISTINCT FROM 'number'
```

（同じファイルの他の `cnt <> 2`（855・1288・1474 行目）は別の件数なので変えない）

- [ ] **Step 3: 両方のテストが失敗することを確かめる**

隔離スタックには Task 1 の migration だけが入っている（Task 1 の Step 4 で reset 済み）。テストだけを流す。

Run:
```bash
docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/sleep_decline_alert_test.sql
docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/client_alert_detection_test.sql
```
Expected（どちらも終了コード 3）:
- 1本目: 第1部（case 23・1〜16）の NOTICE がすべて出たあと、
  ```
  ERROR:  FAIL: (22) stats に detected.sleep_decline（数値・1以上）が無い: {"opened": 1, "updated": 0, "detected": {"record_gap": {...}, "weight_change": 0}, ...}
  ```
- 2本目: case (e) は Task 1 で直し済みなので通り、
  ```
  ERROR:  FAIL: (j) stats のキーが期待と異なる: {...}
  ```

- [ ] **Step 4: migration に本実行の関数と末尾の検査を追記する**

`supabase/migrations/20261003000000_alert_sleep_decline.sql` の末尾（Task 1 の最後の行 `GRANT EXECUTE ON FUNCTION public.evaluate_client_alerts(date, timestamptz) TO service_role;` の後ろ）に、次の内容をそのまま追記する（先頭は空行）。

```sql
-- -----------------------------------------------------------------------------
-- 4. run_client_alert_detection(p_target_date)
--    本実行。evaluate_client_alerts(p_target_date, 締め時刻) の結果で alerts の状態を遷移させ、
--    alert_detection_runs に1行残して jsonb のサマリーを返す。
--    締め時刻は LEAST(now(), D+1 の JST 0:00) 固定（引数では受け取らない）。
--
--    ガード（例外にするのはこの3つだけ）:
--      - 対象日が NULL
--      - 対象日が JST の今日より未来
--      - 対象日が、最後に成功した本実行の対象日より前（古い窓で新しい状態を上書きしないため）
--      同じ対象日の再実行は許す（同じ状態に収束する。今日の対象日なら後から届いたデータの分だけ新しくなる）
--    pg_advisory_xact_lock で直列に実行する（cron と手動実行が重なっても片方ずつ）
--
--    状態遷移（すべて条件付き UPDATE。API と同時に走っても片方しか通らない）:
--      遷移の前に生きている行を FOR UPDATE でロックする。継続（4-1〜4-3）は条件の違う3本の UPDATE で、
--      READ COMMITTED では文ごとに見える状態が変わるため、その間に API の「対応済み」「元に戻す」が
--      コミットされると昇格の再浮上を取りこぼす（4-1 では open、4-2 では acknowledged に見えて
--      どちらにも当たらない）。ロックすれば API の条件付き UPDATE は本実行のコミットまで待つ
--      1. 対象外: 生きている行の顧客が no_account / self、または snapshot に居ない（登録日が
--         締め時刻より後・有限でない = 顧客本人が clients を書き換えた）→ resolved（ineligible）
--      2. 担当替え: 生きている行の trainer_id が今の clients.trainer_id と違う → resolved（reassigned）
--      3. 期限切れ（expired）:
--         3-1. 生きている weight_change で last_detected_on ≤ D − 14（評価されなかった顧客の行にも掛かる）
--         3-2. 生きている record_gap の顧客が not_started（登録から 14 日を過ぎた未開始）/
--              inactive（最終到着から 14 日超）になった。監視を打ち切り、以後は理由別の人数だけに数える
--              （オーナー決定 (1)。未開始は最大 14 日、記録・同期なしは最大 13 日で打ち切られる）
--         3-3. 生きている sleep_decline で last_detected_on ≤ D − 14（3-1 と同じ形。監視対象から外れた
--              顧客は evaluate に行が出ず cleared にならないので、これが無いと生きている行が残り続ける。
--              睡眠時間も目覚め評価も評価できないまま 14 日たった行もここで閉じる）
--      4. 継続: detected で生きている行がある → payload・severity・last_detected_on を更新。
--         重大度が上がったとき、open なら surfaced_on = D、acknowledged で reopened_count = 0 なら
--         open に戻す（acknowledged_at = NULL、reopened_count = 1、surfaced_on = D）
--      5. 新規: detected で生きている行が無い → open で INSERT（first_detected_on = surfaced_on =
--         last_detected_on = D）。生きている行の二重作成は alerts_live_client_type_key が防ぎ、
--         違反したら実行全体がロールバックされる
--      6. 解消: cleared → resolved（cleared）
--      unknown の行は何もしない。resolved は終端で、再発したら新しい行を作る
--
--    評価結果と snapshot は一時表（ON COMMIT DROP）に置いて各段で使い回す。
--    同じトランザクションで2回呼ばれても作り直せるよう、残っていれば先に DROP する
--
--    20260914000200 からの変更は睡眠悪化（sleep_decline）の追加だけ:
--      - DECLARE に c_sleep_expire_days と n_sleep_expired
--      - 期限切れの段 3-3（n_expired に足す）
--      - stats の detected.sleep_decline（detected の件数）
--    それ以外の段・ガード・stats のキーは変えない
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_client_alert_detection(p_target_date date)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- weight_change は 14 日間再確認できなければ期限切れ（last_detected_on ≤ D − 14）
  c_weight_expire_days constant integer := 14;
  -- sleep_decline も 14 日間再確認できなければ期限切れ（体重と同じ。設計 §4.7）
  c_sleep_expire_days  constant integer := 14;
  -- 重大度の順位（昇格の判定に使う。右ほど重い）
  c_severity_order     constant text[] := ARRAY['low', 'medium', 'high'];

  v_started_at   timestamptz := clock_timestamp();
  v_today        date := (now() AT TIME ZONE 'Asia/Tokyo')::date;
  v_last_target  date;
  v_as_of        timestamptz;
  v_reopened     uuid[];
  v_escalated    uuid[];
  n_continued    integer;
  n_opened       integer;
  n_ineligible   integer;
  n_reassigned   integer;
  n_expired      integer;
  n_gap_expired  integer;
  n_sleep_expired integer;
  n_cleared      integer;
  n_lowered      integer;
  v_population   jsonb;
  v_detected     jsonb;
  v_stats        jsonb;
BEGIN
  -- ---- ガード ----
  IF p_target_date IS NULL THEN
    RAISE EXCEPTION 'run_client_alert_detection: 対象日（p_target_date）が NULL です'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'run_client_alert_detection: 対象日 % が JST の今日（%）より未来です',
      p_target_date, v_today
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- 同時実行を直列化する（ロックを取ってから「最後に成功した本実行」を読む）
  PERFORM pg_advisory_xact_lock(hashtext('public.run_client_alert_detection'));

  SELECT max(r.target_date) INTO v_last_target FROM public.alert_detection_runs r;
  IF v_last_target IS NOT NULL AND p_target_date < v_last_target THEN
    RAISE EXCEPTION 'run_client_alert_detection: 対象日 % が、最後に成功した本実行の対象日（%）より前です',
      p_target_date, v_last_target
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_as_of := LEAST(now(), (p_target_date + 1)::timestamp AT TIME ZONE 'Asia/Tokyo');

  -- ---- 評価結果と snapshot を一時表に置く ----
  -- （DROP TABLE IF EXISTS だとセッションに一時スキーマがまだ無いときに NOTICE が出るので、
  --   to_regclass で有無を確かめてから落とす）
  IF to_regclass('pg_temp.client_alert_eval') IS NOT NULL THEN
    DROP TABLE pg_temp.client_alert_eval;
  END IF;
  CREATE TEMP TABLE client_alert_eval ON COMMIT DROP AS
    SELECT e.client_id, e.trainer_id, e.alert_type, e.state, e.severity, e.payload
      FROM public.evaluate_client_alerts(p_target_date, v_as_of) AS e;

  IF to_regclass('pg_temp.client_alert_snap') IS NOT NULL THEN
    DROP TABLE pg_temp.client_alert_snap;
  END IF;
  CREATE TEMP TABLE client_alert_snap ON COMMIT DROP AS
    SELECT s.client_id, s.exclusion_reason
      FROM public.client_activity_snapshot(p_target_date, v_as_of) AS s;

  -- ---- 生きている行をロックしてから遷移させる（上のコメント参照。API は本実行のコミットまで待つ）----
  PERFORM 1 FROM public.alerts a WHERE a.resolved_at IS NULL FOR UPDATE;

  -- ---- 1. 対象外（アプリ未登録・自己登録になった / snapshot に居ない）----
  -- snapshot に居ないのは、登録日が締め時刻より後か有限でない顧客（顧客本人が clients を書き換えた）。
  -- 評価も解消もされないまま残り続けないよう、ここで閉じる
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'ineligible'
   WHERE a.resolved_at IS NULL
     AND (
       EXISTS (
         SELECT 1
           FROM pg_temp.client_alert_snap s
          WHERE s.client_id = a.client_id
            AND s.exclusion_reason IN ('no_account', 'self')
       )
       OR NOT EXISTS (
         SELECT 1 FROM pg_temp.client_alert_snap s WHERE s.client_id = a.client_id
       )
     );
  GET DIAGNOSTICS n_ineligible = ROW_COUNT;

  -- ---- 2. 担当替え（新しい担当の分は下の「新規」で同じ実行の中に作る）----
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'reassigned'
    FROM public.clients c
   WHERE a.resolved_at IS NULL
     AND c.client_id = a.client_id
     AND c.trainer_id <> a.trainer_id;
  GET DIAGNOSTICS n_reassigned = ROW_COUNT;

  -- ---- 3. 期限切れ ----
  -- 3-1. weight_change: 14 日間再確認できない（評価されなかった顧客の行にも掛ける）
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'expired'
   WHERE a.resolved_at IS NULL
     AND a.alert_type = 'weight_change'
     AND a.last_detected_on <= p_target_date - c_weight_expire_days;
  GET DIAGNOSTICS n_expired = ROW_COUNT;

  -- 3-2. record_gap: 顧客が監視対象外（not_started / inactive）になった → 監視を打ち切る。
  --      生きている行を理由に監視を延ばすと、「登録から42日・記録なし」のような行が対応済みに
  --      しない限り並び続け、対象外の人数にも数えられない（オーナー決定 (1) に反する）
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'expired'
    FROM pg_temp.client_alert_snap s
   WHERE a.resolved_at IS NULL
     AND a.alert_type = 'record_gap'
     AND s.client_id = a.client_id
     AND s.exclusion_reason IN ('not_started', 'inactive');
  GET DIAGNOSTICS n_gap_expired = ROW_COUNT;
  n_expired := n_expired + n_gap_expired;

  -- 3-3. sleep_decline: 14 日間再確認できない（3-1 と同じ形。評価されなかった顧客の行にも掛ける）
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'expired'
   WHERE a.resolved_at IS NULL
     AND a.alert_type = 'sleep_decline'
     AND a.last_detected_on <= p_target_date - c_sleep_expire_days;
  GET DIAGNOSTICS n_sleep_expired = ROW_COUNT;
  n_expired := n_expired + n_sleep_expired;

  -- ---- 4. 継続（生きている行がある detected）----
  -- 4-1. 対応済みのまま重大度が上がり、まだ再浮上していない行 → open に戻す（1回の発生につき1回だけ）
  WITH moved AS (
    UPDATE public.alerts a
       SET status = 'open',
           acknowledged_at = NULL,
           reopened_count = 1,
           surfaced_on = p_target_date,
           severity = e.severity,
           payload = e.payload,
           last_detected_on = GREATEST(a.last_detected_on, p_target_date)
      FROM pg_temp.client_alert_eval e
     WHERE e.state = 'detected'
       AND a.client_id = e.client_id
       AND a.alert_type = e.alert_type
       AND a.trainer_id = e.trainer_id
       AND a.resolved_at IS NULL
       AND a.status = 'acknowledged'
       AND a.reopened_count = 0
       AND array_position(c_severity_order, e.severity) > array_position(c_severity_order, a.severity)
    RETURNING a.id
  )
  SELECT coalesce(array_agg(moved.id), '{}'::uuid[]) INTO v_reopened FROM moved;

  -- 4-2. open のまま重大度が上がった行 → surfaced_on = D（後で push の対象を選ぶ列なので漏らさない）
  WITH moved AS (
    UPDATE public.alerts a
       SET surfaced_on = p_target_date,
           severity = e.severity,
           payload = e.payload,
           last_detected_on = GREATEST(a.last_detected_on, p_target_date)
      FROM pg_temp.client_alert_eval e
     WHERE e.state = 'detected'
       AND a.client_id = e.client_id
       AND a.alert_type = e.alert_type
       AND a.trainer_id = e.trainer_id
       AND a.resolved_at IS NULL
       AND a.status = 'open'
       AND array_position(c_severity_order, e.severity) > array_position(c_severity_order, a.severity)
    RETURNING a.id
  )
  SELECT coalesce(array_agg(moved.id), '{}'::uuid[]) INTO v_escalated FROM moved;

  -- 4-3. それ以外の継続（重大度が同じ・下がった・再浮上済みの昇格）→ 値だけ更新し、status は変えない
  UPDATE public.alerts a
     SET severity = e.severity,
         payload = e.payload,
         last_detected_on = GREATEST(a.last_detected_on, p_target_date)
    FROM pg_temp.client_alert_eval e
   WHERE e.state = 'detected'
     AND a.client_id = e.client_id
     AND a.alert_type = e.alert_type
     AND a.trainer_id = e.trainer_id
     AND a.resolved_at IS NULL
     AND a.id <> ALL (v_reopened || v_escalated);
  GET DIAGNOSTICS n_continued = ROW_COUNT;

  -- ---- 5. 新規（生きている行が無い detected）----
  INSERT INTO public.alerts (
    trainer_id, client_id, alert_type, severity, status, payload,
    first_detected_on, surfaced_on, last_detected_on
  )
  SELECT e.trainer_id, e.client_id, e.alert_type, e.severity, 'open', e.payload,
         p_target_date, p_target_date, p_target_date
    FROM pg_temp.client_alert_eval e
   WHERE e.state = 'detected'
     AND NOT EXISTS (
       SELECT 1
         FROM public.alerts a
        WHERE a.client_id = e.client_id
          AND a.alert_type = e.alert_type
          AND a.resolved_at IS NULL
     );
  GET DIAGNOSTICS n_opened = ROW_COUNT;

  -- ---- 6. 解消 ----
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'cleared'
    FROM pg_temp.client_alert_eval e
   WHERE e.state = 'cleared'
     AND a.client_id = e.client_id
     AND a.alert_type = e.alert_type
     AND a.trainer_id = e.trainer_id
     AND a.resolved_at IS NULL;
  GET DIAGNOSTICS n_cleared = ROW_COUNT;

  -- ---- 実行記録（件数だけ。client_id や健康に関する値は入れない）----
  SELECT jsonb_build_object(
           'monitored', count(*) FILTER (WHERE s.exclusion_reason IS NULL),
           'excluded', jsonb_build_object(
             'no_account',  count(*) FILTER (WHERE s.exclusion_reason = 'no_account'),
             'self',        count(*) FILTER (WHERE s.exclusion_reason = 'self'),
             'not_started', count(*) FILTER (WHERE s.exclusion_reason = 'not_started'),
             'inactive',    count(*) FILTER (WHERE s.exclusion_reason = 'inactive')))
    INTO v_population
    FROM pg_temp.client_alert_snap s;

  SELECT jsonb_build_object(
           'weight_change',
             count(*) FILTER (WHERE e.alert_type = 'weight_change' AND e.state = 'detected'),
           'record_gap', jsonb_build_object(
             'not_started', count(*) FILTER (WHERE e.alert_type = 'record_gap' AND e.state = 'detected'
                                              AND e.payload->>'variant' = 'not_started'),
             'no_data',     count(*) FILTER (WHERE e.alert_type = 'record_gap' AND e.state = 'detected'
                                              AND e.payload->>'variant' = 'no_data'),
             'no_record',   count(*) FILTER (WHERE e.alert_type = 'record_gap' AND e.state = 'detected'
                                              AND e.payload->>'variant' = 'no_record')),
           'sleep_decline',
             count(*) FILTER (WHERE e.alert_type = 'sleep_decline' AND e.state = 'detected')),
         count(*) FILTER (WHERE e.state = 'detected' AND e.payload->>'severity_reason' IS NOT NULL)
    INTO v_detected, n_lowered
    FROM pg_temp.client_alert_eval e;

  v_stats := v_population || jsonb_build_object(
    'detected',  v_detected,
    'opened',    n_opened,
    'updated',   cardinality(v_reopened) + cardinality(v_escalated) + n_continued,
    'escalated', cardinality(v_escalated),
    'reopened',  cardinality(v_reopened),
    'resolved',  jsonb_build_object(
      'cleared',    n_cleared,
      'expired',    n_expired,
      'reassigned', n_reassigned,
      'ineligible', n_ineligible),
    'severity_lowered', n_lowered
  );

  INSERT INTO public.alert_detection_runs (target_date, as_of, started_at, finished_at, stats)
  VALUES (p_target_date, v_as_of, v_started_at, clock_timestamp(), v_stats);

  RETURN jsonb_build_object(
    'target_date', p_target_date,
    'as_of',       v_as_of,
    'stats',       v_stats
  );
END;
$$;

COMMENT ON FUNCTION public.run_client_alert_detection(date) IS
  '異常検知の本実行（cron detect-client-alerts が 06:00 JST に JST の今日を渡して呼ぶ）。'
  'evaluate_client_alerts の結果で alerts を状態遷移させ（対象外 → 担当替え → 期限切れ → 継続 → 新規 → 解消）、'
  'alert_detection_runs に1行残して {target_date, as_of, stats} を返す。'
  '対象日は必須（既定値なし）、締め時刻は LEAST(now(), D+1 の JST 0:00) 固定。dry run は evaluate を使う。'
  '例外は「対象日が NULL / JST の今日より未来 / 最後に成功した本実行の対象日より前」の3つだけで、同じ対象日の再実行は許す。'
  'stats のキー: monitored（監視数）/ excluded.{no_account,self,not_started,inactive} / '
  'detected.weight_change / detected.record_gap.{not_started,no_data,no_record} / detected.sleep_decline / '
  'opened（新規）/ updated（継続した行すべて。escalated・reopened を含む）/ '
  'escalated（open のまま重大度が上がり surfaced_on を更新）/ reopened（対応済みから再浮上）/ '
  'resolved.{cleared,expired,reassigned,ineligible}（expired は 14 日再確認されない weight_change・sleep_decline と、'
  '顧客が not_started / inactive になった record_gap。ineligible は no_account / self / snapshot に居ない顧客）/ '
  'severity_lowered（diet の減少で medium に下げた検知数）。'
  '件数だけで client_id や健康に関する値は入れない。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「状態遷移」「冪等性とガード」、'
  '睡眠悪化は docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md §4.7・§4.8';

REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM anon;
REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.run_client_alert_detection(date) TO service_role;

-- -----------------------------------------------------------------------------
-- 5. 末尾の検査（設計 §5 の 8）
--    REVOKE は自分が付与した権限しか剥がさない（lessons「SECURITY DEFINER 関数の権限是正
--    （フェーズ5.6）」）ので、作り直した後の実際の状態を確かめ、違えば例外で migration 全体を止める:
--      - SECURITY DEFINER のまま
--      - proconfig に search_path=""（既存テストと同じ '= ANY (proconfig)' で比べる。proconfig::text では比べない）
--      - PUBLIC に EXECUTE が無い（proacl が NULL = 既定権限 = PUBLIC に EXECUTE、なので acldefault で補う）
--      - anon / authenticated に EXECUTE が無く、service_role にある（has_function_privilege）
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_fn     regprocedure;
  v_secdef boolean;
  v_config text[];
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.evaluate_client_alerts(date, timestamptz)'::regprocedure,
    'public.run_client_alert_detection(date)'::regprocedure
  ] LOOP
    SELECT p.prosecdef, p.proconfig
      INTO v_secdef, v_config
      FROM pg_catalog.pg_proc p
     WHERE p.oid = v_fn;

    IF v_secdef IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'ALERT_FUNCTION_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('function %s is not SECURITY DEFINER', v_fn);
    END IF;

    IF v_config IS NULL OR NOT ('search_path=""' = ANY (v_config)) THEN
      RAISE EXCEPTION 'ALERT_FUNCTION_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('function %s does not pin search_path to '''' (proconfig=%s)',
                               v_fn, coalesce(v_config::text, 'NULL'));
    END IF;

    IF EXISTS (
      SELECT 1
        FROM pg_catalog.pg_proc p,
             aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
       WHERE p.oid = v_fn
         AND a.grantee = 0  -- 0 = PUBLIC
         AND a.privilege_type = 'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'ALERT_FUNCTION_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('function %s is still executable by PUBLIC', v_fn);
    END IF;

    IF has_function_privilege('anon', v_fn, 'EXECUTE')
       OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'ALERT_FUNCTION_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('function %s EXECUTE: anon=%s authenticated=%s service_role=%s (expected f / f / t)',
                               v_fn,
                               has_function_privilege('anon', v_fn, 'EXECUTE'),
                               has_function_privilege('authenticated', v_fn, 'EXECUTE'),
                               has_function_privilege('service_role', v_fn, 'EXECUTE'));
    END IF;
  END LOOP;
END $$;
```

- [ ] **Step 5: 適用して、新しいテストと回帰テストが通ることを確かめる**

Run:
```bash
SP=/private/tmp/claude-501/-Users-hoshidayuuya-Documents-FIT-CONNECT/ab68eea9-a74a-49fb-b328-1a51c801b004/scratchpad
rsync -a --delete supabase/migrations/ $SP/sleep-stack/supabase/migrations/
(cd $SP/sleep-stack && supabase db reset)   # 隔離スタック fitconnect-sleep101 だけが作り直される。リポジトリ内で実行しないこと
docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/sleep_decline_alert_test.sql
for f in client_alert_detection_test client_alerts_rls_test client_activity_snapshot_test cron_jobs_test function_search_path_privileges_test definer_functions_privileges_test; do
  echo "=== $f"
  docker exec -i supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/$f.sql 2>&1 | grep -E "FAIL|ERROR|PASSED"
done
```
Expected:
- `supabase db reset` がエラー無しで終わる（末尾の検査が通らなければ `ERROR:  ALERT_FUNCTION_POSTCHECK_FAILED` と DETAIL が出て reset が失敗する）
- 新しいテストは終了コード 0 で、Task 1 の Step 4 の行に続いて次の行が出る（行頭の `psql:<stdin>:NNN: ` は省略）:
```
--- 第2部-1 setup: 状態遷移用の顧客 S1
--- case 17・22: 新規は open・medium・surfaced_on = D、stats に detected.sleep_decline。同じ D の再実行で件数が増えない
NOTICE:  OK: 09-20 に open・medium・surfaced_on 09-20 で作成、stats.detected.sleep_decline = 1。再実行で件数は増えない
--- case 21・18: 対応済みは成立が続いても対応済みのまま / 保留（unknown）の日は status・last_detected_on・payload が変わらない
NOTICE:  OK: 対応済みの S1 は 09-21 の成立でも acknowledged のまま（last_detected_on 09-21）。09-26 の unknown では何も変わらない
--- case 19: 後の日に cleared → resolved（cleared）
NOTICE:  OK: 09-30 に Δ +70 で S1 は resolved（cleared）
--- 第2部-2 setup: 期限切れ用の顧客 51・52・53
--- case 20: last_detected_on = D−14 の生きている sleep_decline は expired、D−13 は残る（評価は unknown）。評価されない顧客の行も expired
NOTICE:  OK: D−14 の sleep_decline は expired、D−13 は acknowledged のまま。inactive の顧客の古い行も expired
--- case 24: 両関数が SECURITY DEFINER・search_path = ""、EXECUTE は service_role だけ（proacl と PUBLIC を含めて）
NOTICE:  OK: evaluate_client_alerts・run_client_alert_detection は SECURITY DEFINER + search_path = ""、EXECUTE は postgres と service_role だけ
ALL SLEEP DECLINE ALERT TESTS PASSED
```
- 回帰テストは6本とも `FAIL` / `ERROR` が無く、次の行だけが出る:
```
=== client_alert_detection_test
ALL CLIENT ALERT DETECTION TESTS PASSED
=== client_alerts_rls_test
ALL CLIENT ALERTS RLS TESTS PASSED
=== client_activity_snapshot_test
ALL CLIENT ACTIVITY SNAPSHOT TESTS PASSED
=== cron_jobs_test
ALL CRON JOBS TESTS PASSED
=== function_search_path_privileges_test
ALL FUNCTION SEARCH_PATH PRIVILEGE TESTS PASSED
=== definer_functions_privileges_test
ALL DEFINER FUNCTION PRIVILEGE TESTS PASSED
```

補足: 一字一句この計画どおりなら、適用後の `md5(prosrc)` は `evaluate_client_alerts` = `f9da5a2ab0ed75c6e3eb6cede096f41b`、`run_client_alert_detection` = `8204524cb8882d68e7314d318e9af9cd`。テストでは固定しない参考値。

- [ ] **Step 6: コミットする**

```bash
git add supabase/migrations/20261003000000_alert_sleep_decline.sql supabase/tests/sleep_decline_alert_test.sql supabase/tests/client_alert_detection_test.sql
git commit -m "$(cat <<'EOF'
feat(supabase): 睡眠悪化アラートの期限切れと実行記録の件数を本実行に追加（フェーズ9.1 拡張）

run_client_alert_detection に sleep_decline の期限切れ（14日再確認されない行）と
stats.detected.sleep_decline を足し、migration の末尾に両関数の DEFINER・search_path・
EXECUTE の検査を置く。既存の検知テストを3種別に合わせる。

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: アラートの型と表示内容（`sleep_decline`）

**Files:**
- Modify: `fit-connect/src/types/alert.ts:12`（`ClientAlertType`）、`:86`（`ClientAlertPayload` の前に睡眠の型）
- Create: `fit-connect/src/lib/sleep/formatSleepMinutes.ts`
- Modify: `fit-connect/src/lib/sleep/sleepQuote.ts:6`（import を足す）、`:18-25`（関数を再 export に置き換える）
- Modify: `fit-connect/src/lib/alerts/describeAlert.ts:4-5`（冒頭の説明）、`:13-17`（import・`AlertRecordTab`）、`:32-33`（`AlertDescription`）、`:153-155`（`toCount`）、`:226-228`（睡眠の payload の読み取り）、`:242,253,267,282,293,315,327,340`（既存の8つの return に `messageRef: null`）、`:334`（`describeSleepDecline`）、`:346-356`（`describeAlert`）
- Test: `fit-connect/src/lib/alerts/describeAlert.test.ts:12-17, 58-60, 63-73, 156-166, 288-290, 293-303, 341-342, 369`

**Interfaces:**
- Consumes:
  - Task 1 が作る payload（設計書 §4.6）: `{ v: 1, triggers: ('duration'|'wakeup')[], recent: { from, to, median_minutes: number|null, nights }, previous: { 同じ }, delta_minutes: number|null, wakeup: { avg: number|null, count }, threshold: {...} }`
  - `formatSleepMinutes(totalMinutes: number): string`（9.3。今は `@/lib/sleep/sleepQuote`。このタスクで `@/lib/sleep/formatSleepMinutes` に移し、`sleepQuote` からも引き続き import できるようにする）
  - `type RecordQuoteRef = { kind: 'sleep_night'; date: string } | { kind: 'sleep_week' }`（`@/lib/message/recordQuoteRef`。Task 4 で `@/lib/message/recordQuoteLink` に移るが型は同じ）
- Produces:
  - `type ClientAlertType = 'weight_change' | 'record_gap' | 'sleep_decline'`
  - `type SleepDeclineTrigger = 'duration' | 'wakeup'`
  - `type SleepDeclineWindow = { from: string; to: string; median_minutes: number | null; nights: number }`
  - `type SleepDeclinePayload = { v: 1; triggers: SleepDeclineTrigger[]; recent: SleepDeclineWindow; previous: SleepDeclineWindow; delta_minutes: number | null; wakeup: { avg: number | null; count: number }; threshold: { drop_minutes: number; min_nights: number; wakeup_avg: number; min_ratings: number } }`
  - `type AlertRecordTab = 'weight' | 'summary' | 'sleep'`
  - `AlertDescription.messageRef: RecordQuoteRef | null`（`sleep_decline` は payload に依らず `{ kind: 'sleep_week' }`、それ以外の種別は `null`）
  - `describeAlert({ alert_type: 'sleep_decline', severity, payload }): AlertDescription`（kindLabel・title「睡眠の悪化」、tab `'sleep'`）
  - `formatSleepMinutes` を `@/lib/sleep/formatSleepMinutes` から export

- [ ] **Step 1: 失敗するテストを書く（`describeAlert.test.ts`）**

1-1. 型の import に `SleepDeclinePayload` を足す（12〜17行目）。

変更前:
```ts
import type {
  WeightChangePayload,
  RecordGapNotStartedPayload,
  RecordGapNoDataPayload,
  RecordGapNoRecordPayload,
} from '@/types/alert'
```
変更後:
```ts
import type {
  WeightChangePayload,
  RecordGapNotStartedPayload,
  RecordGapNoDataPayload,
  RecordGapNoRecordPayload,
  SleepDeclinePayload,
} from '@/types/alert'
```

1-2. `noRecord` の定義（50〜58行目）の後、`describe('describeAlert: weight_change', () => {`（60行目）の前に、睡眠の payload を足す。
```ts
// 設計書 §4.6 の例（対象日 D = 2026-10-03）
const sleepBoth: SleepDeclinePayload = {
  v: 1,
  triggers: ['duration', 'wakeup'],
  recent: { from: '2026-09-26', to: '2026-10-02', median_minutes: 330, nights: 5 },
  previous: { from: '2026-09-19', to: '2026-09-25', median_minutes: 402, nights: 7 },
  delta_minutes: -72,
  wakeup: { avg: 1.33, count: 3 },
  threshold: { drop_minutes: 60, min_nights: 4, wakeup_avg: 1.5, min_ratings: 3 },
}

const sleepDuration: SleepDeclinePayload = {
  ...sleepBoth,
  triggers: ['duration'],
  wakeup: { avg: null, count: 0 },
}

// 目覚め評価だけで成立（登録日 J = 9/28 の直後。睡眠時間の無い評価だけの行で、前の窓は空・from が to より後）
const sleepWakeupOnly: SleepDeclinePayload = {
  ...sleepBoth,
  triggers: ['wakeup'],
  recent: { from: '2026-09-28', to: '2026-10-02', median_minutes: null, nights: 0 },
  previous: { from: '2026-09-28', to: '2026-09-25', median_minutes: null, nights: 0 },
  delta_minutes: null,
  wakeup: { avg: 1.33, count: 3 },
}

const SLEEP_DURATION_DETAIL =
  '直近の睡眠 5時間30分（中央値）。前の週より1時間12分短くなっています。9/26〜10/2（5晩）と 9/19〜9/25（7晩）の比較'

```

1-3. オブジェクト全体を比べている既存の3箇所に `messageRef: null` を足す（`tab` の次の行）。

63〜73行目（weight_change「増加」）の変更後:
```ts
    expect(d).toEqual({
      kindLabel: '体重の変化',
      chip: '体重 +2.4kg',
      title: '体重の急な変化',
      detail: '7日平均 +2.4kg（+3.4%）。9/6〜9/12 と 8/30〜9/5 の比較',
      severity: 'high',
      severityLabel: '要確認',
      tab: 'weight',
      messageRef: null,
      gapDays: null,
      recognized: true,
    })
```
156〜166行目（record_gap「not_started」）の変更後:
```ts
    expect(d).toEqual({
      kindLabel: '記録開始前',
      chip: '登録から5日・記録なし',
      title: '記録開始前',
      detail: '9/8 に登録してから、記録もメッセージもありません',
      severity: 'medium',
      severityLabel: '注意',
      tab: 'summary',
      messageRef: null,
      gapDays: 5,
      recognized: true,
    })
```
293〜303行目（未知の alert_type）の変更後:
```ts
    expect(d).toEqual({
      kindLabel: '自動チェックの検知',
      chip: '自動チェックの検知',
      title: '自動チェックの検知',
      detail: 'この項目の詳しい内容は表示できません。顧客の記録を確認してください。',
      severity: 'high',
      severityLabel: '要確認',
      tab: 'summary',
      messageRef: null,
      gapDays: null,
      recognized: false,
    })
```

1-4. `describe('describeAlert: record_gap', …)` の閉じ（288行目の `})`）の後、`describe('describeAlert: 未知の種別・重要度', () => {`（290行目）の前に足す。
```ts
describe('describeAlert: sleep_decline', () => {
  it('睡眠時間だけで成立: 短くなった分のチップ・中央値と比較期間の詳細・注意・睡眠タブ・直近7日の引用', () => {
    const d = describeAlert({ alert_type: 'sleep_decline', severity: 'medium', payload: sleepDuration })
    expect(d).toEqual({
      kindLabel: '睡眠の悪化',
      chip: '睡眠 -1時間12分',
      title: '睡眠の悪化',
      detail: SLEEP_DURATION_DETAIL,
      severity: 'medium',
      severityLabel: '注意',
      tab: 'sleep',
      messageRef: { kind: 'sleep_week' },
      gapDays: null,
      recognized: true,
    })
  })

  it('目覚め評価だけで成立: 前の窓が空（from が to より後・中央値 null）でも正しい payload として扱う', () => {
    const d = describeAlert({ alert_type: 'sleep_decline', severity: 'medium', payload: sleepWakeupOnly })
    expect(d.recognized).toBe(true)
    expect(d.chip).toBe('目覚め評価 1.3')
    expect(d.detail).toBe('目覚め評価の平均 1.3（9/28〜10/2 に3回。1 = だるい、3 = すっきり）')
    expect(d.title).toBe('睡眠の悪化')
    expect(d.kindLabel).toBe('睡眠の悪化')
    expect(d.severityLabel).toBe('注意')
    expect(d.tab).toBe('sleep')
    expect(d.messageRef).toEqual({ kind: 'sleep_week' })
  })

  it('両方成立: チップは睡眠時間、詳細は睡眠時間の文のあとに目覚め評価の文', () => {
    const d = describeAlert({ alert_type: 'sleep_decline', severity: 'medium', payload: sleepBoth })
    expect(d.recognized).toBe(true)
    expect(d.chip).toBe('睡眠 -1時間12分')
    expect(d.detail).toBe(
      `${SLEEP_DURATION_DETAIL}。目覚め評価の平均 1.3（9/26〜10/2 に3回。1 = だるい、3 = すっきり）`
    )
  })

  it('triggers の並び・未知の値に依らず、既知の条件を duration → wakeup の順で出す', () => {
    const d = describeAlert({
      alert_type: 'sleep_decline',
      severity: 'medium',
      payload: { ...sleepBoth, triggers: ['heart_rate', 'wakeup', 'duration'] },
    })
    expect(d.recognized).toBe(true)
    expect(d.chip).toBe('睡眠 -1時間12分')
    expect(d.detail.startsWith('直近の睡眠 5時間30分（中央値）')).toBe(true)
    expect(d.detail.endsWith('1 = だるい、3 = すっきり）')).toBe(true)
  })

  it('分は「H時間M分」（ちょうどの時間は「H時間」）。符号は ASCII の -', () => {
    const d = describeAlert({
      alert_type: 'sleep_decline',
      severity: 'medium',
      payload: {
        ...sleepDuration,
        recent: { ...sleepDuration.recent, median_minutes: 360 },
        previous: { ...sleepDuration.previous, median_minutes: 420 },
        delta_minutes: -60,
      },
    })
    expect(d.chip).toBe('睡眠 -1時間')
    expect(d.detail).toBe(
      '直近の睡眠 6時間（中央値）。前の週より1時間短くなっています。9/26〜10/2（5晩）と 9/19〜9/25（7晩）の比較'
    )
    expect(d.chip).not.toContain('−') // U+2212 ではない
  })

  it('目覚め評価だけの行は、睡眠時間の項目が欠けていても読める（triggers にある条件だけを確かめる）', () => {
    const d = describeAlert({
      alert_type: 'sleep_decline',
      severity: 'medium',
      payload: { ...sleepWakeupOnly, previous: undefined, delta_minutes: 'broken' },
    })
    expect(d.recognized).toBe(true)
    expect(d.chip).toBe('目覚め評価 1.3')
  })

  it('壊れた payload・v が 1 でない・triggers が空や未知だけ・条件の項目の欠けは、睡眠の汎用文言（引用とタブは残す）', () => {
    expect(describeAlert({ alert_type: 'sleep_decline', severity: 'medium', payload: { ...sleepBoth, v: 2 } })).toEqual({
      kindLabel: '睡眠の悪化',
      chip: '睡眠の悪化',
      title: '睡眠の悪化',
      detail: '睡眠の自動チェックで変化を検知しました。睡眠タブで記録を確認してください。',
      severity: 'medium',
      severityLabel: '注意',
      tab: 'sleep',
      messageRef: { kind: 'sleep_week' },
      gapDays: null,
      recognized: false,
    })

    const broken: unknown[] = [
      null,
      undefined,
      'sleep',
      [],
      {},
      { ...sleepBoth, v: undefined },
      { ...sleepBoth, triggers: [] },
      { ...sleepBoth, triggers: ['heart_rate'] },
      { ...sleepBoth, triggers: 'duration' },
      { ...sleepBoth, triggers: undefined },
      // duration の項目の欠け
      { ...sleepDuration, delta_minutes: null },
      { ...sleepDuration, delta_minutes: 12 }, // 成立は Δ ≤ −60。0 以上は「短くなっています」と書けない
      { ...sleepDuration, recent: undefined },
      { ...sleepDuration, recent: { ...sleepDuration.recent, median_minutes: null } },
      { ...sleepDuration, previous: { ...sleepDuration.previous, median_minutes: null } },
      { ...sleepDuration, previous: { ...sleepDuration.previous, nights: undefined } },
      { ...sleepDuration, recent: { ...sleepDuration.recent, nights: 2.5 } },
      { ...sleepDuration, previous: { ...sleepDuration.previous, from: '2026-09-26' } }, // from > to
      { ...sleepDuration, recent: { ...sleepDuration.recent, to: '2026-02-30' } },
      // wakeup の項目の欠け
      { ...sleepWakeupOnly, wakeup: undefined },
      { ...sleepWakeupOnly, wakeup: { avg: null, count: 3 } },
      { ...sleepWakeupOnly, wakeup: { avg: 1.33 } },
      { ...sleepWakeupOnly, recent: { ...sleepWakeupOnly.recent, from: '2026-10-03' } }, // from > to
      // 両方が triggers にあるのに片方の項目が欠けている
      { ...sleepBoth, wakeup: { avg: null, count: 0 } },
      { ...sleepBoth, delta_minutes: null },
    ]
    for (const payload of broken) {
      const d = describeAlert({ alert_type: 'sleep_decline', severity: 'medium', payload })
      expect(d.recognized).toBe(false)
      expect(d.kindLabel).toBe('睡眠の悪化')
      expect(d.title).toBe('睡眠の悪化')
      expect(d.chip).toBe('睡眠の悪化')
      expect(d.detail).toBe('睡眠の自動チェックで変化を検知しました。睡眠タブで記録を確認してください。')
      expect(d.tab).toBe('sleep')
      expect(d.messageRef).toEqual({ kind: 'sleep_week' })
      expect(d.severityLabel).toBe('注意')
    }
  })
})

```

1-5. `describe('日付の表示（JST の暦日）', …)` の中、`it('時刻付きの値は JST の暦日に直す（JST 9/8 0:30 = UTC 9/7 15:30 は 9/8）', () => {`（342行目）の直前に足す（Review Focus 3。`afterEach` が TZ を戻す）。
```ts
  it('睡眠悪化の比較期間も、UTC より西のタイムゾーンで前日にならない', () => {
    process.env.TZ = 'America/Los_Angeles'
    expect(describeAlert({ alert_type: 'sleep_decline', severity: 'medium', payload: sleepBoth }).detail).toBe(
      `${SLEEP_DURATION_DETAIL}。目覚め評価の平均 1.3（9/26〜10/2 に3回。1 = だるい、3 = すっきり）`
    )
  })

```

1-6. 「リンク先」の「記録を見る」のテスト（367〜370行目）に睡眠タブを足す。

変更後:
```ts
  it('記録を見る: /clients/<id>?tab=…', () => {
    expect(clientRecordHref('c-1', 'weight')).toBe('/clients/c-1?tab=weight')
    expect(clientRecordHref('c-1', 'summary')).toBe('/clients/c-1?tab=summary')
    expect(clientRecordHref('c-1', 'sleep')).toBe('/clients/c-1?tab=sleep')
  })
```

- [ ] **Step 2: 失敗を確かめる**

Run: `npx -y pnpm@10.32.1 exec vitest run src/lib/alerts/describeAlert.test.ts`

Expected: `Tests  11 failed | 22 passed (33)`。落ちるのは次の11件（既存3件は `messageRef` が無いため、睡眠の8件は `sleep_decline` が未知の種別として「自動チェックの検知」になるため）
```
× 増加: チップ・見出し・詳細（窓の日数と比較期間）・要確認・体重タブ
× not_started: 「登録から N日・記録なし」（N = gap_to − gap_from + 1 = D − J）
× 睡眠時間だけで成立: 短くなった分のチップ・中央値と比較期間の詳細・注意・睡眠タブ・直近7日の引用
× 目覚め評価だけで成立: 前の窓が空（from が to より後・中央値 null）でも正しい payload として扱う
× 両方成立: チップは睡眠時間、詳細は睡眠時間の文のあとに目覚め評価の文
× triggers の並び・未知の値に依らず、既知の条件を duration → wakeup の順で出す
× 分は「H時間M分」（ちょうどの時間は「H時間」）。符号は ASCII の -
× 目覚め評価だけの行は、睡眠時間の項目が欠けていても読める（triggers にある条件だけを確かめる）
× 壊れた payload・v が 1 でない・triggers が空や未知だけ・条件の項目の欠けは、睡眠の汎用文言（引用とタブは残す）
× 未知の alert_type は汎用の文言で、サマリータブへ
× 睡眠悪化の比較期間も、UTC より西のタイムゾーンで前日にならない
```
（`clientRecordHref('c-1', 'sleep')` は実行時には通る。型の誤りは Step 8 の tsc で消えることを確かめる）

- [ ] **Step 3: `formatSleepMinutes` を依存の無いモジュールに移す（振る舞いは変えない）**

理由（Review Focus 4）: `describeAlert.ts` は `(user_console)/layout.tsx` → `triageLabels` → `detectionStatus` 経由で全ページに読み込まれる。`sleepQuote.ts` は date-fns・ja ロケール・`sleepSummary` を読むので、そこから import するとルートをまたいで共有されるモジュールごと全ページに載る（tree-shaking はページ単位では効かない）。

`fit-connect/src/lib/sleep/formatSleepMinutes.ts` を新規作成:
```ts
/**
 * 分 → 'H時間M分'（ゼロ埋めなし。分が 0 なら 'H時間'、60分未満は 'M分'）。負の数は 0 に丸める。
 *
 * 依存の無い小さなモジュールに分けてある。lib/alerts/describeAlert.ts が使い、describeAlert は
 * (user_console)/layout.tsx から triageLabels → detectionStatus 経由で全ページに読み込まれるため、
 * date-fns とロケールを読む sleepQuote.ts を経由させない（sleepQuote.ts はこれを再 export する）
 */
export function formatSleepMinutes(totalMinutes: number): string {
  const minutes = Math.max(0, Math.round(totalMinutes))
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return `${m}分`
  return m === 0 ? `${h}時間` : `${h}時間${m}分`
}
```

`fit-connect/src/lib/sleep/sleepQuote.ts` の6行目の後に import を足す。

変更前（3〜6行目）:
```ts
import type { SleepRecord } from '@/types/client'
import { WAKEUP_RATING_OPTIONS } from '@/types/client'
import { summarizeRecentSleep } from '@/lib/sleep/sleepSummary'
import type { RecordQuoteRef } from '@/lib/message/recordQuoteRef'
```
変更後:
```ts
import type { SleepRecord } from '@/types/client'
import { WAKEUP_RATING_OPTIONS } from '@/types/client'
import { summarizeRecentSleep } from '@/lib/sleep/sleepSummary'
import type { RecordQuoteRef } from '@/lib/message/recordQuoteRef'
import { formatSleepMinutes } from '@/lib/sleep/formatSleepMinutes'
```

18〜25行目の関数の定義を再 export に置き換える。

変更前:
```ts
/** 分 → 'H時間M分'（ゼロ埋めなし。分が 0 なら 'H時間'、60分未満は 'M分'） */
export function formatSleepMinutes(totalMinutes: number): string {
  const minutes = Math.max(0, Math.round(totalMinutes))
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return `${m}分`
  return m === 0 ? `${h}時間` : `${h}時間${m}分`
}
```
変更後:
```ts
// 分 → 'H時間M分'。実体は依存の無い lib/sleep/formatSleepMinutes.ts（既存の import 先を変えないよう再 export する）
export { formatSleepMinutes }
```

- [ ] **Step 4: 既存の `sleepQuote` のテストが再 export 経由で通ることを確かめる**

Run: `npx -y pnpm@10.32.1 exec vitest run src/lib/sleep/sleepQuote.test.ts`

Expected: `Tests  16 passed (16)`（`formatSleepMinutes` の既存テストを含む）

- [ ] **Step 5: 型を足す（`types/alert.ts`）**

12行目:
```ts
export type ClientAlertType = 'weight_change' | 'record_gap'
```
を次に置き換える:
```ts
export type ClientAlertType = 'weight_change' | 'record_gap' | 'sleep_decline'
```

86行目:
```ts
export type ClientAlertPayload = WeightChangePayload | RecordGapPayload
```
を次に置き換える:
```ts
/** ③ 睡眠悪化の成立した条件（並びは duration → wakeup） */
export type SleepDeclineTrigger = 'duration' | 'wakeup'

/** 睡眠の比較窓（直近 = GREATEST(D − 7, 登録日)〜D − 1 / 前 = GREATEST(D − 14, 登録日)〜D − 8） */
export type SleepDeclineWindow = {
  /** 窓の実際の始まり。登録直後は前の窓の from が to より後になることがある（そのとき nights は 0） */
  from: string
  to: string
  /** 有効な晩（120〜960分）の睡眠時間の中央値を整数に丸めたもの。窓が空なら null */
  median_minutes: number | null
  /** 有効な晩（120〜960分）の数 */
  nights: number
}

/** ③ 睡眠悪化（重大度は常に medium） */
export type SleepDeclinePayload = {
  v: 1
  /** 成立した条件。detected のときは1つ以上 */
  triggers: SleepDeclineTrigger[]
  recent: SleepDeclineWindow
  previous: SleepDeclineWindow
  /** 丸める前の中央値どうしの差（直近 − 前）を整数に丸めたもの。どちらかの窓が空なら null */
  delta_minutes: number | null
  /** 直近の窓の目覚め評価（1 = だるい、3 = すっきり）。avg は小数2桁。評価が0回なら avg は null・count は 0 */
  wakeup: { avg: number | null; count: number }
  threshold: { drop_minutes: number; min_nights: number; wakeup_avg: number; min_ratings: number }
}

export type ClientAlertPayload = WeightChangePayload | RecordGapPayload | SleepDeclinePayload
```

- [ ] **Step 6: `describeAlert.ts` を実装する**

6-a. 冒頭の説明（4〜5行目）。

変更前:
```ts
 * - 文言は DB に持たない（導出値は保存しない）。見出し・詳細文・理由のチップ・重要度のラベル・
 *   「記録を見る」のリンク先タブ・途絶の日数を、ここ1箇所で決める
```
変更後:
```ts
 * - 文言は DB に持たない（導出値は保存しない）。見出し・詳細文・理由のチップ・重要度のラベル・
 *   「記録を見る」のリンク先タブ・「メッセージ」に付ける記録の引用・途絶の日数を、ここ1箇所で決める
```

6-b. import と `AlertRecordTab`（13〜17行目）。

変更前:
```ts
import { toJstDateString } from '@/lib/payments/jstDate'
import type { AlertSeverity } from '@/types/alert'

/** 「記録を見る」の遷移先タブ（/clients/<id>?tab=…） */
export type AlertRecordTab = 'weight' | 'summary'
```
変更後:
```ts
import { toJstDateString } from '@/lib/payments/jstDate'
import { formatSleepMinutes } from '@/lib/sleep/formatSleepMinutes'
import type { RecordQuoteRef } from '@/lib/message/recordQuoteRef'
import type { AlertSeverity, SleepDeclineTrigger } from '@/types/alert'

/** 「記録を見る」の遷移先タブ（/clients/<id>?tab=…。顧客詳細は sleep も受け付ける） */
export type AlertRecordTab = 'weight' | 'summary' | 'sleep'
```
（`formatSleepMinutes` は必ず `@/lib/sleep/formatSleepMinutes` から読む。`@/lib/sleep/sleepQuote` から読まない）

6-c. `AlertDescription` に `messageRef` を足す（32〜33行目）。

変更前:
```ts
  tab: AlertRecordTab
  /** 記録途絶の日数（gap_to − gap_from + 1）。途絶以外・日付が壊れているときは null */
  gapDays: number | null
```
変更後:
```ts
  tab: AlertRecordTab
  /**
   * 「メッセージ」で開くときに付ける記録の引用（/message?clientId=…&record=…）。
   * 睡眠悪化は直近7日の睡眠（payload が壊れていても付ける。payload に依存しないため）。それ以外の種別は null
   */
  messageRef: RecordQuoteRef | null
  /** 記録途絶の日数（gap_to − gap_from + 1）。途絶以外・日付が壊れているときは null */
  gapDays: number | null
```

6-d. `toFiniteNumber`（146〜153行目）の後、`formatSigned` の説明（155行目）の前に `toCount` を足す。

変更前:
```ts
  return null
}

/** 小数1桁・符号付き（+2.4 / -2.4）。丸めて 0.0 になるときは符号を付けない */
function formatSigned(value: number): string {
```
変更後:
```ts
  return null
}

/** 0 以上の整数（晩の数・評価の回数）。それ以外は null */
function toCount(value: unknown): number | null {
  const parsed = toFiniteNumber(value)
  return parsed !== null && Number.isInteger(parsed) && parsed >= 0 ? parsed : null
}

/** 小数1桁・符号付き（+2.4 / -2.4）。丸めて 0.0 になるときは符号を付けない */
function formatSigned(value: number): string {
```

6-e. `readRecordGap` の閉じ（226行目）の後、`// 文言` の区切り（228〜230行目）の前に、睡眠の payload の読み取りを足す。

変更前:
```ts
    lastRecordBeforeGap: recordToGapDays !== null && recordToGapDays > 2,
  }
}

// ---------------------------------------------------------------------------
// 文言
```
変更後:
```ts
    lastRecordBeforeGap: recordToGapDays !== null && recordToGapDays > 2,
  }
}

type SleepDurationView = {
  /** 直近の窓の中央値（分） */
  recentMedian: number
  /** 前の窓より短くなった分（正の数。delta_minutes の絶対値） */
  dropMinutes: number
  recentRange: string
  recentNights: number
  previousRange: string
  previousNights: number
}

type SleepWakeupView = {
  avg: number
  count: number
  /** 直近の窓（登録直後は7日より短い。実際の期間を出す） */
  recentRange: string
}

/** 成立した条件の表示に要る値。少なくとも一方は必ずある */
type SleepDeclineView =
  | { duration: SleepDurationView; wakeup: SleepWakeupView | null }
  | { duration: null; wakeup: SleepWakeupView }

/** triggers のうち既知の条件だけを集める（未知の値は無視する） */
function readSleepTriggers(value: unknown): Set<SleepDeclineTrigger> {
  const triggers = new Set<SleepDeclineTrigger>()
  if (!Array.isArray(value)) return triggers
  for (const trigger of value) {
    if (trigger === 'duration' || trigger === 'wakeup') triggers.add(trigger)
  }
  return triggers
}

/** 睡眠時間の条件に要る項目: recent / previous の from・to・median_minutes・nights と delta_minutes */
function readSleepDuration(payload: Record<string, unknown>): SleepDurationView | null {
  const { recent, previous } = payload
  if (!isRecord(recent) || !isRecord(previous)) return null

  const recentMedian = toFiniteNumber(recent.median_minutes)
  const previousMedian = toFiniteNumber(previous.median_minutes)
  const recentNights = toCount(recent.nights)
  const previousNights = toCount(previous.nights)
  const deltaMinutes = toFiniteNumber(payload.delta_minutes)
  const recentRange = formatRange(recent.from, recent.to)
  const previousRange = formatRange(previous.from, previous.to)
  if (
    recentMedian === null ||
    previousMedian === null ||
    recentNights === null ||
    previousNights === null ||
    deltaMinutes === null ||
    recentRange === null ||
    previousRange === null
  ) {
    return null
  }
  // 成立は Δ ≤ −60。0 以上は壊れた payload（「短くなっています」と書けない）
  if (deltaMinutes >= 0) return null
  return {
    recentMedian,
    dropMinutes: -deltaMinutes,
    recentRange,
    recentNights,
    previousRange,
    previousNights,
  }
}

/** 目覚め評価の条件に要る項目: recent の from・to と wakeup の avg・count（前の窓は見ない） */
function readSleepWakeup(payload: Record<string, unknown>): SleepWakeupView | null {
  const { recent, wakeup } = payload
  if (!isRecord(recent) || !isRecord(wakeup)) return null
  const avg = toFiniteNumber(wakeup.avg)
  const count = toCount(wakeup.count)
  const recentRange = formatRange(recent.from, recent.to)
  if (avg === null || count === null || recentRange === null) return null
  return { avg, count, recentRange }
}

/**
 * payload の検証は triggers にある条件に要る項目だけを見る（設計書 §6.1）。
 * 目覚め評価だけで成立した行は、前の窓が空（from が to より後・median_minutes が null）でも読める。
 * v が 1 でない・triggers が空か未知の値だけ・triggers の条件の項目が1つでも欠けているときは null
 */
function readSleepDecline(payload: unknown): SleepDeclineView | null {
  if (!isRecord(payload) || payload.v !== 1) return null
  const triggers = readSleepTriggers(payload.triggers)
  if (triggers.size === 0) return null

  const duration = triggers.has('duration') ? readSleepDuration(payload) : null
  const wakeup = triggers.has('wakeup') ? readSleepWakeup(payload) : null
  if (triggers.has('duration') && duration === null) return null
  if (triggers.has('wakeup') && wakeup === null) return null

  if (duration !== null) return { duration, wakeup }
  if (wakeup !== null) return { duration: null, wakeup }
  return null
}

// ---------------------------------------------------------------------------
// 文言
```

6-f. 既存の8つの return（`describeWeightChange` の2つ・`describeRecordGap` の5つ・`describeUnknown` の1つ。元の242・253・267・282・293・315・327・340行目の `tab: 'weight',` / `tab: 'summary',`）の次の行に、同じ字下げで `messageRef: null,` を足す。手で足すか、次のコマンドで足す（`tab: 'sleep',` と型の `tab: AlertRecordTab` には当たらない）。
```bash
perl -0pi -e "s/(\n(\s+)tab: '(weight|summary)',\n)/\$1\$2messageRef: null,\n/g" src/lib/alerts/describeAlert.ts
grep -c "messageRef: null" src/lib/alerts/describeAlert.ts
```
Expected: `8`

例として `describeUnknown`（334〜344行目）の変更後:
```ts
function describeUnknown(): DescriptionBody {
  return {
    kindLabel: '自動チェックの検知',
    chip: '自動チェックの検知',
    title: '自動チェックの検知',
    detail: 'この項目の詳しい内容は表示できません。顧客の記録を確認してください。',
    tab: 'summary',
    messageRef: null,
    gapDays: null,
    recognized: false,
  }
}
```

6-g. `function describeUnknown(): DescriptionBody {`（334行目）の直前に `describeSleepDecline` を足す。
```ts
const SLEEP_GENERIC_DETAIL =
  '睡眠の自動チェックで変化を検知しました。睡眠タブで記録を確認してください。'

/** 目覚め評価の平均（小数1桁。9.3 の引用「目覚め評価 1.3/3」と同じ丸め） */
function formatWakeupAvg(avg: number): string {
  return avg.toFixed(1)
}

function describeSleepDecline(payload: unknown): DescriptionBody {
  const view = readSleepDecline(payload)
  if (view === null) {
    return {
      kindLabel: '睡眠の悪化',
      chip: '睡眠の悪化',
      title: '睡眠の悪化',
      detail: SLEEP_GENERIC_DETAIL,
      tab: 'sleep',
      messageRef: { kind: 'sleep_week' },
      gapDays: null,
      recognized: false,
    }
  }

  // 分は formatSleepMinutes（負の数は0に丸める）に絶対値を渡し、符号は文言側で付ける。
  // チップの符号は体重のチップと同じ ASCII の -
  const sentences: string[] = []
  if (view.duration !== null) {
    const { recentMedian, dropMinutes, recentRange, recentNights, previousRange, previousNights } =
      view.duration
    sentences.push(
      `直近の睡眠 ${formatSleepMinutes(recentMedian)}（中央値）。前の週より${formatSleepMinutes(dropMinutes)}短くなっています。${recentRange}（${recentNights}晩）と ${previousRange}（${previousNights}晩）の比較`
    )
  }
  if (view.wakeup !== null) {
    const { avg, count, recentRange } = view.wakeup
    sentences.push(
      `目覚め評価の平均 ${formatWakeupAvg(avg)}（${recentRange} に${count}回。1 = だるい、3 = すっきり）`
    )
  }
  const chip =
    view.duration !== null
      ? `睡眠 -${formatSleepMinutes(view.duration.dropMinutes)}`
      : `目覚め評価 ${formatWakeupAvg(view.wakeup.avg)}`

  return {
    kindLabel: '睡眠の悪化',
    chip,
    title: '睡眠の悪化',
    detail: sentences.join('。'),
    tab: 'sleep',
    messageRef: { kind: 'sleep_week' },
    gapDays: null,
    recognized: true,
  }
}

```

6-h. `describeAlert`（346〜356行目）で `sleep_decline` を振り分ける。

変更前:
```ts
/** アラート1件の表示内容。alert_type・severity・payload がどんな値でも例外にしない */
export function describeAlert(alert: DescribableAlert): AlertDescription {
  const severity = normalizeSeverity(alert.severity)
  const body =
    alert.alert_type === 'weight_change'
      ? describeWeightChange(alert.payload)
      : alert.alert_type === 'record_gap'
        ? describeRecordGap(alert.payload)
        : describeUnknown()
  return { ...body, severity, severityLabel: SEVERITY_LABELS[severity] }
}
```
変更後:
```ts
/** アラート1件の表示内容。alert_type・severity・payload がどんな値でも例外にしない */
export function describeAlert(alert: DescribableAlert): AlertDescription {
  const severity = normalizeSeverity(alert.severity)
  const body =
    alert.alert_type === 'weight_change'
      ? describeWeightChange(alert.payload)
      : alert.alert_type === 'record_gap'
        ? describeRecordGap(alert.payload)
        : alert.alert_type === 'sleep_decline'
          ? describeSleepDecline(alert.payload)
          : describeUnknown()
  return { ...body, severity, severityLabel: SEVERITY_LABELS[severity] }
}
```

- [ ] **Step 7: 通ることを確かめる**

Run: `npx -y pnpm@10.32.1 exec vitest run src/lib/alerts/describeAlert.test.ts src/lib/sleep/sleepQuote.test.ts`

Expected: `Test Files  2 passed (2)`、`Tests  49 passed (49)`（describeAlert 33・sleepQuote 16）

- [ ] **Step 8: 型を確かめる**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit`

Expected: 出力なし・終了コード 0（`buildTriageRows` / `TriageRow` は `AlertDescription` を作らないので、このタスクだけで型が通る）

- [ ] **Step 9: コミット**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/.claude/worktrees/sleep-decline-alert
git add fit-connect/src/types/alert.ts \
  fit-connect/src/lib/sleep/formatSleepMinutes.ts \
  fit-connect/src/lib/sleep/sleepQuote.ts \
  fit-connect/src/lib/alerts/describeAlert.ts \
  fit-connect/src/lib/alerts/describeAlert.test.ts
git commit -F - <<'EOF'
feat(web): 睡眠悪化アラートの型と表示内容（sleep_decline の文言・睡眠タブ・引用の参照）

- types/alert.ts に 'sleep_decline' と SleepDeclinePayload を足す
- describeAlert に睡眠悪化の chip・詳細文・tab=sleep・messageRef（直近7日）を足す。
  payload は triggers にある条件の項目だけを確かめ、壊れていれば汎用の文言に落とす
- 既存の種別の messageRef は null
- formatSleepMinutes を依存の無いモジュールに分け、sleepQuote から再 export する
  （describeAlert は layout 経由で全ページに載るため、date-fns を読ませない）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: 「今日の対応」の行の導線（純関数）

**Files:**
- Create: `fit-connect/src/lib/message/recordQuoteLink.ts`
- Modify: `fit-connect/src/lib/message/recordQuoteRef.ts:1-38`（型・`formatRecordQuoteRef`・`recordQuoteHref` を移して再 export。ファイル全体を置き換える）
- Modify: `fit-connect/src/types/triage.ts:9-10`（import）、`:79-80`（`messageRef`）
- Modify: `fit-connect/src/lib/triage/buildTriageRows.ts:168`
- Modify: `fit-connect/src/lib/alerts/describeAlert.ts`（Task 3 後の15行目の import、ファイル末尾の `clientMessageHref` の後）
- Modify: `fit-connect/src/lib/triage/triageLabels.ts:10-11`（import）、`:32-34`（`messageLinkLabel` の後）
- Test: `fit-connect/src/lib/alerts/describeAlert.test.ts`（import・「リンク先」）、`fit-connect/src/lib/triage/buildTriageRows.test.ts:26, 227, 339`、`fit-connect/src/lib/triage/triageLabels.test.ts:2-20, 65`、`fit-connect/src/lib/triage/triageListState.test.ts:328`（末尾）

**Interfaces:**
- Consumes（Task 3）: `AlertDescription.messageRef: RecordQuoteRef | null`、`AlertRecordTab`（`'sleep'` を含む）、`describeAlert` の `sleep_decline`
- Produces:
  - `@/lib/message/recordQuoteLink`: `type RecordQuoteRef`、`SLEEP_WEEK_PARAM = 'sleep:7d'`、`formatRecordQuoteRef(ref: RecordQuoteRef): string`、`recordQuoteHref(clientId: string, ref: RecordQuoteRef): string`（`@/lib/message/recordQuoteRef` からも今までどおり import できる）
  - `TriageRowModel.messageRef: RecordQuoteRef | null`（先頭の理由の `description.messageRef`。未返信だけの行は `null`）
  - `quotedMessageHref(clientId: string, messageRef: RecordQuoteRef | null): string`（`@/lib/alerts/describeAlert`。引用ありは `/message?clientId=<id>&record=sleep%3A7d`、なしは `clientMessageHref(clientId)` と同じ）
  - `SLEEP_QUOTE_LINK_TEXT = '睡眠の記録を引用してメッセージ'`（`@/lib/triage/triageLabels`）
  - `quotedMessageLinkLabel(clientName: string, messageRef: RecordQuoteRef | null): string`（引用あり「{名前}さんに睡眠の記録を引用してメッセージを書く」、なしは `messageLinkLabel(clientName)` と同じ「{名前}さんにメッセージを送る」。名前が空なら `clientHonorific` の「名前未設定の顧客」）

- [ ] **Step 1: 失敗するテストを書く**

1-1. `describeAlert.test.ts` の import（2〜11行目）に `quotedMessageHref` を足す。

変更前:
```ts
  clientRecordHref,
  clientMessageHref,
} from '@/lib/alerts/describeAlert'
```
変更後:
```ts
  clientRecordHref,
  clientMessageHref,
  quotedMessageHref,
} from '@/lib/alerts/describeAlert'
```

1-2. `describeAlert.test.ts` の末尾、「メッセージ: /message?clientId=<id>（値はエンコードする）」のテストの後（`describe('リンク先', …)` の閉じの前）に足す。期待値はエンコード済みの `record=sleep%3A7d` で書く。

変更後（`describe('リンク先', …)` の後半）:
```ts
  it('メッセージ: /message?clientId=<id>（値はエンコードする）', () => {
    expect(clientMessageHref('c-1')).toBe('/message?clientId=c-1')
    expect(clientMessageHref('a&b')).toBe('/message?clientId=a%26b')
  })

  it('メッセージ（引用付き）: messageRef があれば record=<参照> を付け、無ければ clientMessageHref と同じ', () => {
    expect(quotedMessageHref('c-1', { kind: 'sleep_week' })).toBe('/message?clientId=c-1&record=sleep%3A7d')
    expect(quotedMessageHref('a&b', { kind: 'sleep_week' })).toBe('/message?clientId=a%26b&record=sleep%3A7d')
    expect(quotedMessageHref('c-1', null)).toBe('/message?clientId=c-1')
    expect(quotedMessageHref('c-1', null)).toBe(clientMessageHref('c-1'))
  })
})
```

1-3. `buildTriageRows.test.ts` の `let seq = 0`（26行目）の直前に睡眠の payload を足す。
```ts
// 睡眠悪化（設計書 §4.6 の例。重大度は常に medium）
const sleepPayload = {
  v: 1,
  triggers: ['duration'],
  recent: { from: '2026-09-26', to: '2026-10-02', median_minutes: 330, nights: 5 },
  previous: { from: '2026-09-19', to: '2026-09-25', median_minutes: 402, nights: 7 },
  delta_minutes: -72,
  wakeup: { avg: null, count: 0 },
  threshold: { drop_minutes: 60, min_nights: 4, wakeup_avg: 1.5, min_ratings: 3 },
}

```

1-4. `buildTriageRows.test.ts` の行全体の比較（「未返信だけの顧客も1行にする」、227〜228行目）に `messageRef: null` を足す。

変更前:
```ts
        recordTab: 'summary',
        score: 36,
```
変更後:
```ts
        recordTab: 'summary',
        messageRef: null,
        score: 36,
```

1-5. `buildTriageRows.test.ts` の `describe('collectTriageClientIds', () => {`（339行目）の直前に足す。
```ts
describe('buildTriageRows（「メッセージ」の引用 messageRef）', () => {
  it('睡眠悪化が先頭の理由なら、「記録を見る」は睡眠タブ・「メッセージ」は直近7日の睡眠の引用', () => {
    const { rows } = buildTriageRows([
      makeAlert({ id: 'sleep', alert_type: 'sleep_decline', severity: 'medium', payload: sleepPayload }),
    ])
    expect(rows[0].recordTab).toBe('sleep')
    expect(rows[0].messageRef).toEqual({ kind: 'sleep_week' })
    expect(rows[0].reasons[0].description.chip).toBe('睡眠 -1時間12分')
    expect(rows[0].score).toBe(10) // medium 1件（スコアは変えない）
  })

  it('体重の急変（要確認）と睡眠悪化（注意）が同じ行なら、先頭は体重 → 「記録を見る」は体重タブ・引用なし', () => {
    const { rows } = buildTriageRows([
      makeAlert({ id: 'sleep', alert_type: 'sleep_decline', severity: 'medium', payload: sleepPayload, surfaced_on: '2026-10-03' }),
      makeAlert({ id: 'weight', alert_type: 'weight_change', severity: 'high', payload: weightPayload, surfaced_on: '2026-09-30' }),
    ])
    expect(rows[0].reasons.map((r) => r.alertId)).toEqual(['weight', 'sleep'])
    expect(rows[0].recordTab).toBe('weight')
    expect(rows[0].messageRef).toBeNull()
    // 睡眠への導線は詳細のリンクに任せる（理由の description には引用が残る）
    expect(rows[0].reasons[1].description.messageRef).toEqual({ kind: 'sleep_week' })
  })

  it('記録途絶と睡眠悪化（どちらも medium）は surfaced_on の新しい方が先頭になり、引用もそれで決まる', () => {
    const sleepNewer = buildTriageRows([
      makeAlert({ id: 'gap', surfaced_on: '2026-10-01' }),
      makeAlert({ id: 'sleep', alert_type: 'sleep_decline', payload: sleepPayload, surfaced_on: '2026-10-03' }),
    ]).rows[0]
    expect(sleepNewer.reasons.map((r) => r.alertId)).toEqual(['sleep', 'gap'])
    expect(sleepNewer.recordTab).toBe('sleep')
    expect(sleepNewer.messageRef).toEqual({ kind: 'sleep_week' })

    const gapNewer = buildTriageRows([
      makeAlert({ id: 'gap', surfaced_on: '2026-10-03' }),
      makeAlert({ id: 'sleep', alert_type: 'sleep_decline', payload: sleepPayload, surfaced_on: '2026-10-01' }),
    ]).rows[0]
    expect(gapNewer.reasons.map((r) => r.alertId)).toEqual(['gap', 'sleep'])
    expect(gapNewer.recordTab).toBe('summary')
    expect(gapNewer.messageRef).toBeNull()
  })

  it('medium どうしで surfaced_on も同じなら alert id の順（入力の順に依らない）', () => {
    const alerts = [
      makeAlert({ id: 'b-gap', surfaced_on: '2026-10-03' }),
      makeAlert({ id: 'a-sleep', alert_type: 'sleep_decline', payload: sleepPayload, surfaced_on: '2026-10-03' }),
    ]
    for (const input of [alerts, [...alerts].reverse()]) {
      const [row] = buildTriageRows(input).rows
      expect(row.reasons.map((r) => r.alertId)).toEqual(['a-sleep', 'b-gap'])
      expect(row.messageRef).toEqual({ kind: 'sleep_week' })
    }
  })

  it('未返信がある行でも messageRef は先頭の理由から取る（「返信する」に引用を付けないのは TriageRow の役目）', () => {
    const { rows } = buildTriageRows(
      [makeAlert({ client_id: 'client-u', alert_type: 'sleep_decline', payload: sleepPayload })],
      { unreplied: [makeUnreplied({ client_id: 'client-u' })], now: NOW }
    )
    expect(rows[0].unreplied).not.toBeNull()
    expect(rows[0].messageRef).toEqual({ kind: 'sleep_week' })
  })

  it('壊れた睡眠の payload でも引用と睡眠タブは残る', () => {
    const { rows } = buildTriageRows([
      makeAlert({ alert_type: 'sleep_decline', payload: { v: 2 } }),
    ])
    expect(rows[0].reasons[0].description.recognized).toBe(false)
    expect(rows[0].recordTab).toBe('sleep')
    expect(rows[0].messageRef).toEqual({ kind: 'sleep_week' })
  })

  it('記録途絶・体重だけの行は引用なし', () => {
    expect(buildTriageRows([makeAlert()]).rows[0].messageRef).toBeNull()
    expect(
      buildTriageRows([
        makeAlert({ alert_type: 'weight_change', severity: 'high', payload: weightPayload }),
      ]).rows[0].messageRef
    ).toBeNull()
  })
})

```

1-6. `triageLabels.test.ts` の import（2〜20行目）に2つ足す。

変更後:
```ts
import {
  acknowledgeButtonLabel,
  acknowledgedToastDescription,
  clientHonorific,
  detailToggleLabel,
  formatUnrepliedElapsed,
  messageLinkLabel,
  quotedMessageLinkLabel,
  recordLinkLabel,
  replyLinkLabel,
  showAllButtonLabel,
  SLEEP_QUOTE_LINK_TEXT,
  TRIAGE_HELP_TEXT,
  triageBadgeLabel,
  triageCountAnnouncement,
  triageEmptyMessage,
  triageTimingNote,
  unrepliedChipLabel,
  unrepliedDetailNote,
  unrepliedDetailText,
} from '@/lib/triage/triageLabels'
```

1-7. `triageLabels.test.ts` の `it('名前が空でも文として読める', () => {`（65行目）の直前に足す。
```ts
  it('睡眠の記録を引用して開く「メッセージ」と詳細のリンク（見える文字をどちらも含む）', () => {
    expect(SLEEP_QUOTE_LINK_TEXT).toBe('睡眠の記録を引用してメッセージ')
    const label = quotedMessageLinkLabel('田中', { kind: 'sleep_week' })
    expect(label).toBe('田中さんに睡眠の記録を引用してメッセージを書く')
    expect(label).toContain('メッセージ') // 行の「メッセージ」
    expect(label).toContain(SLEEP_QUOTE_LINK_TEXT) // 詳細の「睡眠の記録を引用してメッセージ」
    expect(quotedMessageLinkLabel('', { kind: 'sleep_week' })).toBe(
      '名前未設定の顧客に睡眠の記録を引用してメッセージを書く'
    )
  })

  it('引用が無ければ、今までの「メッセージ」の名前', () => {
    expect(quotedMessageLinkLabel('田中', null)).toBe('田中さんにメッセージを送る')
    expect(quotedMessageLinkLabel('田中', null)).toBe(messageLinkLabel('田中'))
  })

```

1-8. `triageListState.test.ts` の末尾（328行目の後）に足す（Review Focus 2）。
```ts

describe('「メッセージ」の引用（睡眠悪化）', () => {
  const sleepPayload = {
    v: 1,
    triggers: ['duration'],
    recent: { from: '2026-09-06', to: '2026-09-12', median_minutes: 330, nights: 5 },
    previous: { from: '2026-08-30', to: '2026-09-05', median_minutes: 402, nights: 7 },
    delta_minutes: -72,
    wakeup: { avg: null, count: 0 },
    threshold: { drop_minutes: 60, min_nights: 4, wakeup_avg: 1.5, min_ratings: 3 },
  }

  it('先頭の睡眠悪化を対応済みにすると引用が外れ（次の理由のタブになる）、元に戻すと付き直す', () => {
    const sleep = makeAlert('s', {
      client_id: 'client-x',
      alert_type: 'sleep_decline',
      payload: sleepPayload,
      surfaced_on: '2026-09-13',
    })
    const gap = makeAlert('g', { client_id: 'client-x', surfaced_on: '2026-09-12' })
    const s0 = createTriageListState([sleep, gap])
    expect(selectTriageListView(s0).rows[0].messageRef).toEqual({ kind: 'sleep_week' })
    expect(selectTriageListView(s0).rows[0].recordTab).toBe('sleep')

    const s1 = run(s0, { type: 'acknowledge', alertId: 's' })
    expect(selectTriageListView(s1).rows[0].messageRef).toBeNull()
    expect(selectTriageListView(s1).rows[0].recordTab).toBe('summary')

    const s2 = run(s1, { type: 'acknowledgeSucceeded', alertId: 's' }, { type: 'undo', alertId: 's' })
    expect(selectTriageListView(s2).rows[0].messageRef).toEqual({ kind: 'sleep_week' })
  })
})
```

- [ ] **Step 2: 失敗を確かめる**

Run（1ファイルずつ）:
```bash
npx -y pnpm@10.32.1 exec vitest run src/lib/alerts/describeAlert.test.ts
npx -y pnpm@10.32.1 exec vitest run src/lib/triage/buildTriageRows.test.ts
npx -y pnpm@10.32.1 exec vitest run src/lib/triage/triageLabels.test.ts
npx -y pnpm@10.32.1 exec vitest run src/lib/triage/triageListState.test.ts
```
Expected:
- describeAlert: `Tests  1 failed | 33 passed (34)`（`TypeError: quotedMessageHref is not a function`）
- buildTriageRows: `Tests  8 failed | 18 passed (26)`（`expected undefined to deeply equal { kind: 'sleep_week' }` / `expected undefined to be null` / 行全体の比較で `messageRef` が無い）
- triageLabels: `Tests  2 failed | 21 passed (23)`（`TypeError: quotedMessageLinkLabel is not a function` / `expected undefined to be '睡眠の記録を引用してメッセージ'`）
- triageListState: `Tests  1 failed | 22 passed (23)`（`expected undefined to deeply equal { kind: 'sleep_week' }`）

- [ ] **Step 3: `RecordQuoteRef` とリンクの組み立てを依存の無いモジュールに移す（振る舞いは変えない）**

理由（Review Focus 4）: `quotedMessageHref` は `describeAlert.ts` に置く（`clientMessageHref` の隣）。`recordQuoteRef.ts` は date-fns を読むので、そこから `recordQuoteHref` を import すると全ページに date-fns が載る（下書きの計測で /settings の First Load が 206 kB → 215 kB）。

`fit-connect/src/lib/message/recordQuoteLink.ts` を新規作成:
```ts
// /message?clientId=…&record=<ref> の <ref> の型と、リンクを組み立てる部分（依存なし）。
// 文法・解釈（parseRecordQuoteRef）・取得範囲は recordQuoteRef.ts にあり、そちらから再 export している。
// lib/alerts/describeAlert.ts は (user_console)/layout.tsx から triageLabels → detectionStatus 経由で
// 全ページに読み込まれるので、date-fns を読む recordQuoteRef.ts ではなくこちらを import する。

export type RecordQuoteRef =
  | { kind: 'sleep_night'; date: string } // 'yyyy-MM-dd'
  | { kind: 'sleep_week' }

/** 直近7日の参照（sleep:7d） */
export const SLEEP_WEEK_PARAM = 'sleep:7d'

export function formatRecordQuoteRef(ref: RecordQuoteRef): string {
  return ref.kind === 'sleep_week' ? SLEEP_WEEK_PARAM : `sleep:${ref.date}`
}

/** 顧客詳細・「今日の対応」→ メッセージ画面のリンク */
export function recordQuoteHref(clientId: string, ref: RecordQuoteRef): string {
  return `/message?clientId=${encodeURIComponent(clientId)}&record=${encodeURIComponent(formatRecordQuoteRef(ref))}`
}
```

`fit-connect/src/lib/message/recordQuoteRef.ts` をファイル全体で次に置き換える（`SLEEP_WEEK` を `SLEEP_WEEK_PARAM` に、`RecordQuoteRef`・`formatRecordQuoteRef`・`recordQuoteHref` は再 export に。`parseRecordQuoteRef` と `recordQuoteDateRange` は中身を変えない）:
```ts
import { format, isValid, parseISO, subDays } from 'date-fns'
import { SLEEP_WEEK_PARAM, type RecordQuoteRef } from '@/lib/message/recordQuoteLink'

// /message?clientId=…&record=<ref> の <ref> の文法。
//   sleep:YYYY-MM-DD … その日付（sleep_records.recorded_date）の1晩
//   sleep:7d         … 直近7日のサマリー（SummaryTab の睡眠カードと同じ計算）
// それ以外は受け付けない（拡張で weight: 等を足すときはここと recordQuoteLink.ts に追加する）。
// URL に載せるのは日付だけで、睡眠時間などの値は載せない。
// 型とリンクの組み立ては依存の無い recordQuoteLink.ts に置き、既存の import 先を変えないよう再 export する。

export { formatRecordQuoteRef, recordQuoteHref, type RecordQuoteRef } from '@/lib/message/recordQuoteLink'

const SLEEP_NIGHT_RE = /^sleep:(\d{4}-\d{2}-\d{2})$/

/** 'yyyy-MM-dd' が実在する暦日か（parseISO の検証 + 往復で桁ずれを弾く） */
function isCalendarDate(date: string): boolean {
  const parsed = parseISO(date)
  return isValid(parsed) && format(parsed, 'yyyy-MM-dd') === date
}

export function parseRecordQuoteRef(param: string | null | undefined): RecordQuoteRef | null {
  if (!param) return null
  if (param === SLEEP_WEEK_PARAM) return { kind: 'sleep_week' }
  const m = SLEEP_NIGHT_RE.exec(param)
  if (!m) return null
  const date = m[1]
  return isCalendarDate(date) ? { kind: 'sleep_night', date } : null
}

/**
 * 引用の対象を取るための recorded_date の範囲（両端含む、'yyyy-MM-dd'、ローカル日付）。
 * 7日は summarizeRecentSleep が「now - 7日 以降」を UTC 0:00 基準で判定するので、
 * 取りこぼさないよう 8 日前から今日まで取り、絞り込みは summarizeRecentSleep に任せる。
 */
export function recordQuoteDateRange(ref: RecordQuoteRef, now: Date = new Date()): { from: string; to: string } {
  if (ref.kind === 'sleep_night') return { from: ref.date, to: ref.date }
  return { from: format(subDays(now, 8), 'yyyy-MM-dd'), to: format(now, 'yyyy-MM-dd') }
}
```
（既存の import 元 `SummaryTab.tsx`・`SleepTab.tsx`・`message/page.tsx`・`sleepQuote.ts`・`recordQuoteRef.test.ts` は変えない）

- [ ] **Step 4: 既存の `recordQuoteRef` のテストが再 export 経由で通ることを確かめる**

Run: `npx -y pnpm@10.32.1 exec vitest run src/lib/message/recordQuoteRef.test.ts`

Expected: `Tests  10 passed (10)`

- [ ] **Step 5: 行に `messageRef` を持たせる（`types/triage.ts`・`buildTriageRows.ts`）**

`types/triage.ts` の import（9〜10行目）。

変更前:
```ts
import type { AlertDescription, AlertRecordTab } from '@/lib/alerts/describeAlert'
import type { AlertSeverity } from '@/types/alert'
```
変更後:
```ts
import type { AlertDescription, AlertRecordTab } from '@/lib/alerts/describeAlert'
import type { RecordQuoteRef } from '@/lib/message/recordQuoteLink'
import type { AlertSeverity } from '@/types/alert'
```

`types/triage.ts` の `TriageRowModel`（79〜80行目）。

変更前:
```ts
  /** 「記録を見る」の遷移先タブ（先頭の理由のタブ。未返信だけの行は summary） */
  recordTab: AlertRecordTab
```
変更後:
```ts
  /** 「記録を見る」の遷移先タブ（先頭の理由のタブ。未返信だけの行は summary） */
  recordTab: AlertRecordTab
  /**
   * 未返信が無い行の「メッセージ」に付ける記録の引用（先頭の理由の messageRef。未返信だけの行は null）。
   * recordTab と同じく先頭の理由から取り、「記録を見る」と「メッセージ」の対象をそろえる。
   * 未返信がある行の「返信する」には付けない（TriageRow が決める）
   */
  messageRef: RecordQuoteRef | null
```

`buildTriageRows.ts` の行の組み立て（168行目）。

変更前:
```ts
      recordTab: top?.description.tab ?? 'summary',
      score: triageScore({
```
変更後:
```ts
      recordTab: top?.description.tab ?? 'summary',
      messageRef: top?.description.messageRef ?? null,
      score: triageScore({
```
（理由の並びは既存の `compareReasons`（重要度 → surfaced_on の新しい順 → id）のまま。変えない）

- [ ] **Step 6: 引用付きの「メッセージ」の href（`describeAlert.ts`）**

import（Task 3 後の15行目）。

変更前:
```ts
import type { RecordQuoteRef } from '@/lib/message/recordQuoteRef'
```
変更後:
```ts
import { recordQuoteHref, type RecordQuoteRef } from '@/lib/message/recordQuoteLink'
```

ファイル末尾の `clientMessageHref` の後に足す。

変更後（ファイル末尾）:
```ts
/** 「メッセージ」の遷移先（message/page.tsx が ?clientId= を読む） */
export function clientMessageHref(clientId: string): string {
  return `/message?clientId=${encodeURIComponent(clientId)}`
}

/**
 * 記録の引用付きの「メッセージ」の遷移先。messageRef があれば /message?clientId=…&record=…（9.3 の引用。
 * 睡眠の直近7日は record=sleep%3A7d）、無ければ clientMessageHref と同じ
 */
export function quotedMessageHref(clientId: string, messageRef: RecordQuoteRef | null): string {
  return messageRef === null ? clientMessageHref(clientId) : recordQuoteHref(clientId, messageRef)
}
```

- [ ] **Step 7: 引用付きのアクセシブルな名前（`triageLabels.ts`）**

import（10〜11行目）。

変更前:
```ts
import { formatJstMonthDayTime, type DetectionState } from '@/lib/alerts/detectionStatus'
import type { TriageUnreplied } from '@/types/triage'
```
変更後:
```ts
import { formatJstMonthDayTime, type DetectionState } from '@/lib/alerts/detectionStatus'
import type { RecordQuoteRef } from '@/lib/message/recordQuoteLink'
import type { TriageUnreplied } from '@/types/triage'
```

`messageLinkLabel`（29〜32行目）の後、`replyLinkLabel` の説明（34行目）の前に足す。

変更後:
```ts
/** 「田中さんにメッセージを送る」（見える文字は「メッセージ」） */
export function messageLinkLabel(clientName: string): string {
  return `${clientHonorific(clientName)}にメッセージを送る`
}

/** 詳細の睡眠悪化の理由に出す、睡眠の記録を引用してメッセージ画面を開くリンクの見える文字 */
export const SLEEP_QUOTE_LINK_TEXT = '睡眠の記録を引用してメッセージ'

/**
 * 記録の引用付きで開く「メッセージ」の名前。
 * - 引用あり:「田中さんに睡眠の記録を引用してメッセージを書く」。行の「メッセージ」と詳細の
 *   「睡眠の記録を引用してメッセージ」のどちらの見える文字も含む（RecordQuoteRef は今は睡眠の参照だけ）
 * - 引用なし: messageLinkLabel と同じ「田中さんにメッセージを送る」
 */
export function quotedMessageLinkLabel(clientName: string, messageRef: RecordQuoteRef | null): string {
  if (messageRef === null) return messageLinkLabel(clientName)
  return `${clientHonorific(clientName)}に${SLEEP_QUOTE_LINK_TEXT}を書く`
}

/** 未返信のある行の主ボタン「田中さんに返信する」（見える文字は「返信する」） */
```

- [ ] **Step 8: 通ることを確かめる**

Run:
```bash
npx -y pnpm@10.32.1 exec vitest run src/lib/alerts/describeAlert.test.ts src/lib/triage/buildTriageRows.test.ts src/lib/triage/triageLabels.test.ts src/lib/triage/triageListState.test.ts src/lib/message/recordQuoteRef.test.ts
```
Expected: `Test Files  5 passed (5)`、`Tests  116 passed (116)`（34 + 26 + 23 + 23 + 10）

- [ ] **Step 9: 型を確かめる**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit`

Expected: 出力なし・終了コード 0（`TriageRow.tsx` はまだ `messageLinkLabel` を使っているが、関数は残しているので通る）

- [ ] **Step 10: コミット**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/.claude/worktrees/sleep-decline-alert
git add fit-connect/src/lib/message/recordQuoteLink.ts \
  fit-connect/src/lib/message/recordQuoteRef.ts \
  fit-connect/src/types/triage.ts \
  fit-connect/src/lib/triage/buildTriageRows.ts \
  fit-connect/src/lib/triage/buildTriageRows.test.ts \
  fit-connect/src/lib/alerts/describeAlert.ts \
  fit-connect/src/lib/alerts/describeAlert.test.ts \
  fit-connect/src/lib/triage/triageLabels.ts \
  fit-connect/src/lib/triage/triageLabels.test.ts \
  fit-connect/src/lib/triage/triageListState.test.ts
git commit -F - <<'EOF'
feat(web): 「今日の対応」の行に睡眠の引用の参照を持たせ、引用付きのリンク先と名前を足す

- TriageRowModel.messageRef: 先頭の理由の messageRef（recordTab と同じく先頭から取る）
- quotedMessageHref: 引用があれば /message?clientId=…&record=sleep%3A7d、無ければ従来の href
- quotedMessageLinkLabel / SLEEP_QUOTE_LINK_TEXT: 「{名前}さんに睡眠の記録を引用してメッセージを書く」
- RecordQuoteRef とリンクの組み立てを依存の無い recordQuoteLink.ts に分け、recordQuoteRef から再 export する
  （describeAlert は layout 経由で全ページに載るため、date-fns を読ませない）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: TriageRow の表示

**Files:**
- Modify: `fit-connect/src/components/dashboard/TriageRow.tsx:3-22`（import）、`:34-35`（詳細のテキストリンクの見た目）、`:61-77`（`TriageReasonDetail`）、`:137-143`（説明）、`:227-233`（未返信が無い行の「メッセージ」）

**Interfaces:**
- Consumes（Task 4）: `quotedMessageHref(clientId: string, messageRef: RecordQuoteRef | null): string`、`quotedMessageLinkLabel(clientName: string, messageRef: RecordQuoteRef | null): string`、`SLEEP_QUOTE_LINK_TEXT: string`、`TriageRowModel.messageRef`、`TriageReason.description.messageRef`（Task 3）
- Produces: なし（表示だけ）

コンポーネントのテスト基盤は無いので、振る舞いは Task 4 の純関数のテストで固定済み。このタスクは tsc・lint・vitest 全体・静的確認・`next build` で確かめる。画面の確認は設計書 §8.3 のタスクで行う。

- [ ] **Step 1: import を直す（3〜22行目）**

変更後:
```tsx
import { Check, ChevronDown, MessageCircle, MessageSquare } from 'lucide-react'
import { ProfileAvatar } from '@/components/clients/ProfileAvatar'
import {
  clientMessageHref,
  clientRecordHref,
  formatJstMonthDay,
  quotedMessageHref,
  severityLabel,
} from '@/lib/alerts/describeAlert'
import {
  acknowledgeButtonLabel,
  clientHonorific,
  detailToggleLabel,
  quotedMessageLinkLabel,
  recordLinkLabel,
  replyLinkLabel,
  SLEEP_QUOTE_LINK_TEXT,
  UNREPLIED_DETAIL_TITLE,
  unrepliedChipLabel,
  unrepliedDetailNote,
  unrepliedDetailText,
} from '@/lib/triage/triageLabels'
```
（`messageLinkLabel` はこのファイルで使わなくなるので import から外す。`clientMessageHref` は「返信する」で使い続ける）

- [ ] **Step 2: 詳細のテキストリンクの見た目を足す（34行目の `TRIAGE_SECONDARY_BUTTON` の後）**

変更前:
```tsx
export const TRIAGE_SECONDARY_BUTTON = `${BUTTON_BASE} border border-[#E2E8F0] bg-white text-[#475569] hover:bg-[#F8FAFC] hover:text-[#0F172A]`

// 重要度は色だけでなく「要確認」「注意」の文字でも示す（red / amber は重要度の表示だけに使う）
```
変更後:
```tsx
export const TRIAGE_SECONDARY_BUTTON = `${BUTTON_BASE} border border-[#E2E8F0] bg-white text-[#475569] hover:bg-[#F8FAFC] hover:text-[#0F172A]`

// 詳細の中のテキストリンク。色と hover は 9.3 の SummaryTab「メッセージで触れる」に合わせ、
// 押せる高さは隣の「対応済みにする」（BUTTON_BASE の px-3 py-2 text-sm）とそろえる
const TRIAGE_TEXT_LINK = `inline-flex items-center gap-1.5 rounded-md px-3 py-2 text-sm font-medium text-[#0F766E] transition-colors duration-150 hover:bg-[#F0FDFA] motion-reduce:transition-none ${TRIAGE_FOCUS_RING}`

// 重要度は色だけでなく「要確認」「注意」の文字でも示す（red / amber は重要度の表示だけに使う）
```

- [ ] **Step 3: 詳細の理由に「睡眠の記録を引用してメッセージ」のリンクを出す（`TriageReasonDetail`、61〜77行目）**

変更前:
```tsx
/** 行を開いたときの理由1件（詳細文・検知日・「対応済みにする」） */
function TriageReasonDetail({ row, reason, busy, onAcknowledge }: TriageReasonDetailProps) {
  const detectedOn = formatJstMonthDay(reason.firstDetectedOn)

  return (
    <li className="rounded-md border border-[#E2E8F0] bg-[#F8FAFC] p-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <SeverityBadge severity={reason.severity} />
            <p className="text-sm font-semibold text-[#0F172A]">{reason.description.title}</p>
          </div>
          <p className="mt-2 text-sm leading-6 text-[#475569] [overflow-wrap:anywhere]">
            {reason.description.detail}
          </p>
          {detectedOn && <p className="mt-1 text-xs text-[#475569]">検知日 {detectedOn}</p>}
        </div>
```
変更後:
```tsx
/**
 * 行を開いたときの理由1件（詳細文・検知日・「対応済みにする」）。
 * 引用の付く理由（睡眠悪化）には「睡眠の記録を引用してメッセージ」のリンクを出す
 * （未返信の有無・理由の順番を問わない。行の「メッセージ」は先頭の理由が睡眠悪化のときしか引用を付けないため）
 */
function TriageReasonDetail({ row, reason, busy, onAcknowledge }: TriageReasonDetailProps) {
  const detectedOn = formatJstMonthDay(reason.firstDetectedOn)
  const messageRef = reason.description.messageRef

  return (
    <li className="rounded-md border border-[#E2E8F0] bg-[#F8FAFC] p-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <SeverityBadge severity={reason.severity} />
            <p className="text-sm font-semibold text-[#0F172A]">{reason.description.title}</p>
          </div>
          <p className="mt-2 text-sm leading-6 text-[#475569] [overflow-wrap:anywhere]">
            {reason.description.detail}
          </p>
          {detectedOn && <p className="mt-1 text-xs text-[#475569]">検知日 {detectedOn}</p>}
          {messageRef !== null && (
            // -ml-3 で、アイコンの左端を詳細文の左端にそろえる（px-3 の分）
            <Link
              href={quotedMessageHref(row.clientId, messageRef)}
              aria-label={quotedMessageLinkLabel(row.clientName, messageRef)}
              className={`${TRIAGE_TEXT_LINK} -ml-3 mt-1`}
            >
              <MessageSquare aria-hidden="true" className="h-3.5 w-3.5 flex-shrink-0" />
              {SLEEP_QUOTE_LINK_TEXT}
            </Link>
          )}
        </div>
```
（その後の「対応済みにする」のボタン以降は変えない）

- [ ] **Step 4: `TriageRow` の説明を直す（137〜143行目）**

変更前:
```tsx
 * - 未返信がある行: 主ボタンは「返信する」（/message?clientId=）、副ボタンは「記録を見る」
 * - 未返信が無い行: 主ボタンは「記録を見る」、副ボタンは「メッセージ」（PR1 のまま）
```
変更後:
```tsx
 * - 未返信がある行: 主ボタンは「返信する」（/message?clientId=。引用は付けない）、副ボタンは「記録を見る」
 * - 未返信が無い行: 主ボタンは「記録を見る」、副ボタンは「メッセージ」。
 *   先頭の理由が睡眠悪化なら（row.messageRef）、直近7日の睡眠の引用付きで開く（&record=sleep%3A7d）
```

- [ ] **Step 5: 未返信が無い行の「メッセージ」を引用付きにする（227〜233行目）**

変更前:
```tsx
              <Link
                href={clientMessageHref(row.clientId)}
                aria-label={messageLinkLabel(row.clientName)}
                className={TRIAGE_SECONDARY_BUTTON}
              >
                メッセージ
              </Link>
```
変更後:
```tsx
              <Link
                href={quotedMessageHref(row.clientId, row.messageRef)}
                aria-label={quotedMessageLinkLabel(row.clientName, row.messageRef)}
                className={TRIAGE_SECONDARY_BUTTON}
              >
                メッセージ
              </Link>
```
（未返信がある行の「返信する」（204行目付近の `href={clientMessageHref(row.clientId)}` と `replyLinkLabel`）は変えない）

- [ ] **Step 6: 型を確かめる**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit`

Expected: 出力なし・終了コード 0

- [ ] **Step 7: lint**

Run:
```bash
npx -y pnpm@10.32.1 lint; echo "exit=$?"
npx -y pnpm@10.32.1 lint 2>&1 | grep -E "TriageRow|describeAlert|triageLabels|buildTriageRows|recordQuote|formatSleepMinutes|sleepQuote|types/(alert|triage)"
```
Expected: `exit=0`。警告は既存の6件（`ImageModal.tsx` などの `no-img-element`・`exhaustive-deps`）だけで、2つ目のコマンドは何も出さない

- [ ] **Step 8: 静的確認（Review Focus 1・4）**

Run:
```bash
grep -n "clientMessageHref(row.clientId)\|quotedMessageHref(" src/components/dashboard/TriageRow.tsx
grep -n "^import" src/lib/alerts/describeAlert.ts
```
Expected:
```
91:              href={quotedMessageHref(row.clientId, messageRef)}
227:                href={clientMessageHref(row.clientId)}
251:                href={quotedMessageHref(row.clientId, row.messageRef)}
```
（227行目が未返信がある行の「返信する」。引用の付かない `clientMessageHref` のまま）
```
13:import { toJstDateString } from '@/lib/payments/jstDate'
14:import { formatSleepMinutes } from '@/lib/sleep/formatSleepMinutes'
15:import { recordQuoteHref, type RecordQuoteRef } from '@/lib/message/recordQuoteLink'
16:import type { AlertSeverity, SleepDeclineTrigger } from '@/types/alert'
```
（`sleepQuote` / `recordQuoteRef` を import していない）

- [ ] **Step 9: テスト全体**

Run: `npx -y pnpm@10.32.1 test`

Expected: `Test Files  31 passed (31)`、`Tests  485 passed (485)`（変更前は 466。Task 3 で +8、Task 4 で +11）

- [ ] **Step 10: build（Review Focus 4 の初回読み込み量も見る）**

Run:
```bash
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 NEXT_PUBLIC_SUPABASE_ANON_KEY=dummy SUPABASE_SERVICE_ROLE_KEY=dummy npx -y pnpm@10.32.1 build 2>&1 | grep -E "Compiled|/dashboard |/settings |/message "
```
Expected: `✓ Compiled successfully` と、First Load JS がおおよそ次のとおり（変更前は /dashboard 326 kB・/settings 206 kB・/message 323 kB）
```
├ ○ /dashboard                              31.7 kB         327 kB
├ ○ /message                                17.4 kB         324 kB
├ ○ /settings                               12.4 kB         207 kB
```
/settings が 215 kB 以上なら、`describeAlert` か `triageLabels` が date-fns を読むモジュール（`sleepQuote` / `recordQuoteRef`）を import している。Step 8 の import を見直す

- [ ] **Step 11: コミット**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/.claude/worktrees/sleep-decline-alert
git add fit-connect/src/components/dashboard/TriageRow.tsx
git commit -F - <<'EOF'
feat(web): 「今日の対応」の「メッセージ」と詳細から睡眠の記録を引用してメッセージを開く

- 未返信が無い行の「メッセージ」: 先頭の理由が睡眠悪化なら直近7日の睡眠の引用付きで開く
- 未返信がある行の「返信する」は変えない（引用を付けない）
- 詳細の睡眠悪化の理由に「睡眠の記録を引用してメッセージ」のリンク（#0F766E、hover は SummaryTab と同じ）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: ドキュメント（手順書・計画書・タスク表・学び）

**Files:**
- Modify: `docs/tasks/2026-07-10-cron-vault-setup.md:285-290`（§5 の冒頭）、`:369-371`（§5-2 のバックテストの SQL）、`:391`（§5-2 の注記）、末尾（§5-10 を新設）
- Modify: `docs/tasks/2026-09-13-trainer-intervention-plan.md:161`（alerts の alert_type）、`:564`（拡張の優先順）
- Modify: `docs/tasks/IMPLEMENTATION_TASKS.md:6`（最終更新）、`:40`（フェーズ表）、`:500`・`:503`（9.1）、`:512`・`:517`（9.3）
- Modify: `docs/tasks/lessons.md`（末尾に節を追加）

**Interfaces:**
- Consumes: Task 1〜5 の成果（migration 名、関数名、例外名、Web の導線）。行番号は 2026-10-03 時点。ずれていたら old の文字列で探す
- Produces: なし（文書だけ）

- [ ] **Step 1: 実装後の関数本体の md5 を取る**（ロールバック用の期待値として手順書に書く）

Run（worktree のルートから。隔離スタックには Task 2 の migration が入っている）:
```bash
docker exec supabase_db_fitconnect-sleep101 psql -U postgres -d postgres -At -c "SELECT proname, md5(prosrc) FROM pg_proc WHERE proname IN ('evaluate_client_alerts','run_client_alert_detection') ORDER BY proname"
```
Expected（計画どおりに書いていれば）:
```
evaluate_client_alerts|f9da5a2ab0ed75c6e3eb6cede096f41b
run_client_alert_detection|8204524cb8882d68e7314d318e9af9cd
```
違う値が出たら、Step 2 (e) の §5-10「ロールバック」の2つの md5 を、出た値に置き換えて書く。

- [ ] **Step 2: 手順書 `docs/tasks/2026-07-10-cron-vault-setup.md` を直す**

(a) 285〜286 行目（関連 migration）

old:
```
`20260914000100_client_activity_snapshot.sql`（活動の定義）/ `20260914000200_client_alert_detection.sql`（評価・本実行・検知状態・cron）
```
new:
```
`20260914000100_client_activity_snapshot.sql`（活動の定義）/ `20260914000200_client_alert_detection.sql`（評価・本実行・検知状態・cron）/
`20261003000000_alert_sleep_decline.sql`（睡眠の悪化を追加。§5-10。設計: `docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md`）
```

(b) 289〜290 行目（ジョブの説明）

old:
```
毎日 06:00 JST（`0 21 * * *` = UTC 21:00）に、担当顧客の「体重の急な変化（weight_change）」と「記録途絶（record_gap）」を
判定して `public.alerts` に残すジョブです。
```
new:
```
毎日 06:00 JST（`0 21 * * *` = UTC 21:00）に、担当顧客の「体重の急な変化（weight_change）」「記録途絶（record_gap）」
「睡眠の悪化（sleep_decline、2026-10-03 追加）」を判定して `public.alerts` に残すジョブです。
```

(c) §5-2 のバックテストの SQL（369〜371 行目の `new_record_gap` の後に足す）

old:
```
       count(*) filter (where cur.state = 'detected' and prev.state is distinct from 'detected'
                          and cur.alert_type = 'record_gap')                                 as new_record_gap,
```
new:
```
       count(*) filter (where cur.state = 'detected' and prev.state is distinct from 'detected'
                          and cur.alert_type = 'record_gap')                                 as new_record_gap,
       count(*) filter (where cur.state = 'detected' and prev.state is distinct from 'detected'
                          and cur.alert_type = 'sleep_decline')                              as new_sleep_decline,
```

(d) §5-2 の注記（391 行目の後に足す）

old:
```
- 体重は成立値と解消値の間（unknown）の日を挟むと、翌日にもう一度「新規」に数えられることがある（ヒステリシスの分）
```
new:
```
- 体重は成立値と解消値の間（unknown）の日を挟むと、翌日にもう一度「新規」に数えられることがある（ヒステリシスの分）
- 睡眠の悪化も同じで、保留の日や、到着遅れで直近の窓が4晩に満たない日（不足 = unknown）を挟むと、翌日にもう一度「新規」に数えられる。
  睡眠は到着遅れが大きい（中央値 約35時間）ので、weight_change より**多めに出る方向**にずれる
```

(e) ファイルの末尾に次の節を足す（先頭は空行）

````
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
4. 想定外の件数が出たら、06:00 より前に §5-5 の停止 SQL で cron を止める（体重・途絶の検知も止まるので、原因を直したらすぐ戻す）
5. 翌朝、§5-6 の確認 SQL の runs の stats に `detected.sleep_decline` が入っていることを確かめる
6. ロールバック（必要なときだけ。新しい migration で、この順番で）:
   1. `delete from public.alerts where alert_type = 'sleep_decline';`（resolved の行も含めて全部。CHECK を ADD するときに全行が検証されるため、resolved にするだけでは戻せない）
   2. 両関数を `20260914000200` の定義に戻す。ドリフトガードの期待値は `evaluate_client_alerts` = `f9da5a2ab0ed75c6e3eb6cede096f41b`、
      `run_client_alert_detection` = `8204524cb8882d68e7314d318e9af9cd`（`md5(prosrc)`。2026-10-03 の実装の値）
   3. CHECK を `('weight_change', 'record_gap')` に戻す
````

- [ ] **Step 3: 計画書 `docs/tasks/2026-09-13-trainer-intervention-plan.md` を直す**

161 行目

old:
```
| alert_type | text NOT NULL、CHECK IN ('weight_change','record_gap') | 種別を増やすときは CHECK を DROP → ADD し、既存の値を落とさない |
```
new:
```
| alert_type | text NOT NULL、CHECK IN ('weight_change','record_gap','sleep_decline') | 種別を増やすときは CHECK を DROP → ADD し、既存の値を落とさない（sleep_decline は 2026-10-03 に追加。設計: `docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md`） |
```

564 行目の `5. ③睡眠悪化` を、次の文字列に置き換える（行の他の部分は変えない）:
```
5. ③睡眠悪化（2026-10-03 実装。ブランチ `feature/sleep-decline-alert`）
```

- [ ] **Step 4: タスク表 `docs/tasks/IMPLEMENTATION_TASKS.md` を直す**

(a) 6 行目: `**最終更新**: ` の直後に次の文を挿入する（既存の「2026年9月23日 - …」はその後ろに残す）

```
2026年10月3日 - フェーズ9.1 拡張③ 睡眠悪化アラート `sleep_decline` を実装（migration `20261003000000` 1本 + SQL テスト + Web の「今日の対応」表示と 9.3 の `sleep:7d` 引用への導線。Mobile 変更なし。ブランチ `feature/sleep-decline-alert`。リモート適用はオーナー作業待ち）。9.3 を #95 でマージし、Mobile で引用付きメッセージが平文のまま表示されることをオーナーが確認。
```

(b) 40 行目（フェーズ9の行）

old:
```
/ 9.3 MVP 完了（2026/09/23、ブランチ `feature/record-reply-quote`）。拡張（睡眠悪化・カロリー超過の検知、閾値設定、トレーナー向け push、消し込み、チャート点クリック、record_ref）は未着手 |
```
new:
```
/ 9.3 MVP 完了（#95、2026/10/03 マージ）/ 9.1 拡張③ 睡眠悪化を実装（2026/10/03、`feature/sleep-decline-alert`、リモート適用待ち）。拡張（カロリー超過の検知、閾値設定、トレーナー向け push、消し込み、チャート点クリック、record_ref）は未着手 |
```

(c) 500 行目の末尾

old:
```
拡張（睡眠悪化・カロリー超過・閾値のトレーナー設定・push）は未着手
```
new:
```
拡張③ 睡眠悪化は実装済み（2026-10-03、下記）。カロリー超過・閾値のトレーナー設定・push は未着手
```

(d) 503 行目を置き換え、その直後に2行足す

old:
```
  - [ ] 検知ルール: 体重急変・記録途絶 ✅（MVP）/ 睡眠悪化・カロリー超過・閾値のトレーナー設定は拡張
```
new:
```
  - [ ] 検知ルール: 体重急変・記録途絶 ✅（MVP）/ 睡眠悪化 ✅（2026-10-03）/ カロリー超過・閾値のトレーナー設定は拡張
  - [x] 拡張③ 睡眠悪化 `sleep_decline`（2026-10-03、ブランチ `feature/sleep-decline-alert`。設計: `docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md`、計画: `docs/superpowers/plans/2026-10-03-sleep-decline-alert.md`）: 直近7日と前の7日の睡眠時間の中央値を比べて1時間以上短い、または直近の目覚め評価の平均が1.5未満で「注意」。到着遅れで睡眠時間が足りない日は解消しない。migration `20261003000000`（ドリフトガード + 末尾の権限検査）+ SQL テスト。Web は「今日の対応」に「睡眠の悪化」を出し、睡眠タブと `sleep:7d` の引用付きメッセージへの導線。Mobile 変更なし
  - [ ] **オーナー作業**: develop へマージ後、`supabase migration list --linked` と `supabase db push --dry-run` で未適用が `20261003000000` の1本だけであることを確かめてから `supabase db push`（06:00 JST の直前は避ける）。適用後の確認と翌朝の確認は `docs/tasks/2026-07-10-cron-vault-setup.md` §5-10
```

(e) 512 行目（9.3 の見出し）

old:
```
— **MVP 完了**（2026-09-23、ブランチ `feature/record-reply-quote`。
```
new:
```
— **MVP 完了**（#95、2026-10-03 マージ。Mobile で引用付きメッセージが平文のまま表示されることをオーナーが確認。
```

(f) 517 行目

old:
```
  - [ ] 9.1 の睡眠悪化アラート（未実装）の行から `sleep:7d` の引用リンクへ接続
```
new:
```
  - [x] 9.1 の睡眠悪化アラートの行から `sleep:7d` の引用リンクへ接続（2026-10-03、`feature/sleep-decline-alert`。未返信が無い行の「メッセージ」と、行の詳細のリンク）
```

- [ ] **Step 5: 学び `docs/tasks/lessons.md` の末尾に節を足す**（先頭は空行）

```
## 睡眠悪化アラート（フェーズ9.1 拡張③、2026-10-03）で得た知見

### 睡眠の「平均の比較」は1晩の外れ値で成立してしまう
- カタログの「直近7日の平均睡眠が前週比 −1時間」をそのまま実装すると、範囲内の値（例: 前の窓に1晩だけ 803分）でも平均の差が −60 になる。体重の外れ値除去（14日の中央値 ±15%）は、日ごとの揺れが大きい睡眠（実データの p10〜p90 で ±約25%）では普通の晩まで落とす
- 窓ごとの代表値を中央値にすると、1晩の外れ値では動かず、直近の窓の半分以上が短くなったときだけ成立する。`percentile_cont` は double precision を返すので、`::numeric` にキャストしてから丸める（double のままだと偶数丸めになり、`round(x, 2)` も書けない）

### 複数条件の OR で検知するときは「解消」の条件を表にする
- 「どちらかが成立で detected、どれかが解消で cleared」と素直に書くと、到着遅れで睡眠時間が評価できない日（直近3晩）に目覚め評価だけで解消し、翌日に新しい行が作り直される（対応済みが閉じては開く）
- 条件ごとに「なし / 不足 / 成立 / 保留 / 解消」の5状態を持ち、全体を順序付きの規則と5×5の表で決めてテストで固定した。「データはあるが足りない」は解消を止め、「データが無い」は止めない

### 既存関数を CREATE OR REPLACE する migration はドリフトガードと末尾の権限検査で挟む
- 先頭で `md5(prosrc)` が期待値と一致することを確かめる（リモートで誰かが直していたら止まる）。期待値はローカルとリモート（MCP の読み取り）の両方で取って一致を確かめてから書く
- 末尾で `'search_path=""' = ANY (proconfig)` と `has_function_privilege`（PUBLIC / anon / authenticated / service_role）を検査する。`proconfig::text` で比べると失敗する
- ガードがあるので同じ DB に2回は流せない。開発中は scratch の隔離スタックで `rsync --delete` → `supabase db reset`（必ず scratch のディレクトリで実行）を回す。下書きの検証は `BEGIN;` + migration + テスト（テスト末尾の ROLLBACK で巻き戻る）でできる

### テストが「評価の行数」を数えていると、種別を足したときに落ちる
- 既存の検知テスト case (e) は「監視対象は2行」を数えていた。新しい種別を足すタスクで一緒に直さないと、そのコミットでは既存テストが落ちる

### 全ページの layout から読まれる純関数に、重い依存を足さない
- `describeAlert` は `(user_console)/layout.tsx` → `triageLabels` → `detectionStatus` 経由で全ページに載る。date-fns とロケールを読む `sleepQuote` / `recordQuoteRef` を import すると、/settings の First Load が 206 → 218 kB に増えた
- 依存の無い小さなモジュール（`formatSleepMinutes.ts` / `recordQuoteLink.ts`）に分け、元のファイルから再 export して 207 kB に抑えた。`next build` の First Load を変更の前後で比べる
```

- [ ] **Step 6: 置き換えを確かめる**

Run（worktree のルートから）:
```bash
grep -c "sleep_decline" docs/tasks/2026-07-10-cron-vault-setup.md docs/tasks/2026-09-13-trainer-intervention-plan.md docs/tasks/IMPLEMENTATION_TASKS.md
grep -n "5-10. 睡眠の悪化\|new_sleep_decline" docs/tasks/2026-07-10-cron-vault-setup.md
grep -n "睡眠悪化アラート（フェーズ9.1 拡張③" docs/tasks/lessons.md
grep -n "9.1 の睡眠悪化アラート（未実装）" docs/tasks/IMPLEMENTATION_TASKS.md
git diff --stat
```
Expected: 1行目は3ファイルとも1以上。2行目は `### 5-10.` の行と `as new_sleep_decline,` の行。3行目は1行。4行目は何も出ない（置き換え済み）。diff は docs の4ファイルだけ。

- [ ] **Step 7: コミット**

```bash
git add docs/tasks/2026-07-10-cron-vault-setup.md docs/tasks/2026-09-13-trainer-intervention-plan.md docs/tasks/IMPLEMENTATION_TASKS.md docs/tasks/lessons.md
git commit -m "docs: 睡眠悪化アラートの手順書・タスク表・学びを更新（フェーズ9.1 拡張）" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 実装後の確認（マネージャーが行う）

1. **全体の確認**: 隔離スタックを最終版の migration で作り直し（`rsync --delete` → `$SP/sleep-stack` で `supabase db reset`）、`sleep_decline_alert_test.sql` と回帰テスト6本を流す。Web は `test`・`tsc --noEmit`・`lint`・`build`
2. **画面の確認**（設計書 §8.3。chrome-web-qa の代わりに「隔離スタック + 合成 Cookie + 内蔵ブラウザ」。手順はメモリ `project_web_qa_env_quirks.md`）
   - 隔離スタック `fitconnect-sleep101`（API は `http://127.0.0.1:58821`）に、admin API でトレーナーと顧客を作り、`clients`・`sleep_records`（`created_at` を明示）を入れて `run_client_alert_detection`（JST の今日）で睡眠悪化の行を作る。体重の急変と睡眠悪化が同じ行にある顧客、未返信と睡眠悪化がある顧客も作る
   - dev server は worktree の `fit-connect` から `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:58821` で `pnpm dev -p 3100`
   - 確認すること: 「睡眠の悪化」「注意」と chip / 「記録を見る」で睡眠タブ / 「メッセージ」で「直近7日」の引用チップ入りのメッセージ画面 / 詳細の文言と「睡眠の記録を引用してメッセージ」のリンク / 体重の急変が先頭の行は「メッセージ」が引用なし / 未返信の行の「返信する」が引用なし / 「対応済み」と「元に戻す」・バッジの数
3. **ブランチ全体のレビュー**（別のエージェント）
4. `git reset --soft` で1コミットにまとめて push し、`develop/1.0.0` 向けの PR を作る。後片付け（dev server・隔離スタックの停止）


---

## 計画で決めた細部（設計書に無い・設計書から変えたもの）

SQL
- 設計書 §8.1 の case 2 と case 11 が同じデータ（340.5 対 400）だったので分けた。case 2 は前 400.5・直近 341、case 11 は直近 340.5・前 400
- どちらかの窓が4晩未満でも、両方の窓に晩があれば `delta_minutes` を入れる（null にするのは窓が空のときだけ。設計書 §4.6 のとおり）
- 目覚め評価が1〜2回でも `wakeup.avg` は値を入れる（null は0回のときだけ）
- 設計書に無いテストを2つ足した: 顧客が書ける異常値（起床日 ±infinity、睡眠時間 −5 / 0 / integer の最大値）で評価が落ちず数えないこと（顧客 28）、監視対象から外れた顧客の古い行も期限切れで閉じること（顧客 53）
- 既存テストの case (e)（1顧客3行）は Task 1 で直す。各コミットで既存テストが通るようにするため（case (j) の stats のキーは Task 2）
- CHECK の DROP に IF EXISTS を付けない（制約名が想定と違えば止まって気づける）
- 例外名はドリフトガードが lessons の慣例どおり `REMOTE_DRIFT_SINCE_CAPTURE`、末尾の検査が `ALERT_FUNCTION_POSTCHECK_FAILED`
- 新しいテストのヘッダーの実行コマンドは隔離スタック（`supabase_db_<project_id>`）を前提に書く（共有スタックに migration を当てないため）

Web
| 決めたこと | 理由 |
|---|---|
| 引用付きのアクセシブルな名前は「{名前}さんに睡眠の記録を引用してメッセージを書く」 | 設計書 §6.2 の文言。既存の「{名前}さんにメッセージを送る」と同じく動詞で終える。見えている文字「メッセージ」「睡眠の記録を引用してメッセージ」をどちらも含む |
| `formatSleepMinutes` と `recordQuoteHref`（+ 型）を依存の無いモジュールに分け、元のファイルから再 export | `describeAlert` は layout 経由で全ページに載る。分けないと /settings の First Load が 206 → 218 kB（計測）。分けると 207 kB |
| duration が triggers にあるのに `delta_minutes` が 0 以上なら汎用の文言 | 「短くなっています」と事実と違う文を出さない（SQL では Δ ≤ −60 のときだけ成立） |
| `nights` と `wakeup.count` は 0 以上の整数だけを受け付ける | 「2.5晩」のような表示を出さない |
| triggers の未知の値は無視し、既知の条件が1つでもあれば読む | 設計書は「未知の値だけ」のとき汎用の文言としている |
| 詳細のリンクは `px-3 py-2 text-sm`（「対応済みにする」と同じ高さ）、色と hover は SummaryTab と同じ | 押しやすさ（タップ領域）。SummaryTab の `text-xs px-2 py-1` はカード見出しの横に置く小さなリンクのため |
| 詳細のリンクを出す条件は `reason.description.messageRef !== null` | 今は睡眠悪化だけが non-null。表示条件を種別名でなくデータで決める |
| 関数名 `quotedMessageHref`・`quotedMessageLinkLabel`・定数 `SLEEP_QUOTE_LINK_TEXT` | 既存の `clientMessageHref`・`messageLinkLabel` と並べて意味が分かる名前 |

---

## 下書き時の検証の記録（2026-10-03）

### SQL（隔離スタック `supabase_db_fitconnect-sleep101`）

すべて `BEGIN;` + 下書きの migration + テストを1本の入力にして流し、テスト末尾の `ROLLBACK;`（または異常終了）で migration ごと巻き戻した。終了後も `evaluate_client_alerts` の `md5(prosrc)` は `9c553a939d98fb60d58022897f6a5d4c`、`run_client_alert_detection` は `0e80baea1335f09889edac7fc584836f`、CHECK は2種別のまま、alerts / alert_detection_runs / clients は 0 行のまま。

| 流したもの | 結果 |
|---|---|
| Task 1 のテストだけ（migration なし） | `FAIL: (23) … を拒んだ` |
| Task 1 の migration + Task 1 のテスト | `ALL SLEEP DECLINE ALERT TESTS PASSED` |
| Task 1 の migration + 完成版のテスト | `FAIL: (22) stats に detected.sleep_decline … が無い` |
| 完成版の migration + 完成版のテスト | `ALL SLEEP DECLINE ALERT TESTS PASSED`（NOTICE 13 行） |
| Task 1 の migration + 既存の検知テスト（未修正） | `FAIL: (e) … 3 行（期待 2 行 …）` |
| Task 1 の migration + 既存の検知テスト（修正版） | `FAIL: (j) stats のキーが期待と異なる` |
| 完成版の migration + 既存の検知テスト（修正版） | `ALL CLIENT ALERT DETECTION TESTS PASSED` |
| 完成版の migration + `client_alerts_rls_test` / `client_activity_snapshot_test` / `cron_jobs_test` / `function_search_path_privileges_test` / `definer_functions_privileges_test` | 5本とも `ALL … PASSED` |
| 完成版の migration を同じトランザクションで2回 | 2回目が `REMOTE_DRIFT_SINCE_CAPTURE` |

テストが実装の誤りを捕まえることも、migration を1か所ずつ壊して確かめた（どれも狙ったケースで FAIL）:
平均にする → (1) / `<=` を `<` に → (2) / 登録日の下限を外す → (8) / 当日 D を含める → (10) / 不足でも解消させる → (15) / 丸めた値どうしの差 → (11) / 120 分を含めない → (5) / 締め時刻の絞り込みを外す → (9) / 目覚め評価 `<=` 1.5 → (13) / D−7 を前の窓にも入れる → (1) / 有効な晩の評価だけ数える → (12) / 直近の from を D−7 に固定 → (12) / 3-3 を外す・`<` にする → (20) / anon・PUBLIC に GRANT・`SET search_path` を外す → 末尾の検査で `ALERT_FUNCTION_POSTCHECK_FAILED`

### Web（scratch に fit-connect をコピーし、使い捨ての git で base → Task 3 → 4 → 5 の順に当てて検証）

| 段階 | 結果 |
|---|---|
| Task 3 の失敗確認 | `describeAlert.test.ts` 11 failed / 33 |
| Task 3 の実装後 | describeAlert + sleepQuote 49 passed、tsc 0、lint 0 |
| Task 4 の失敗確認 | describeAlert 1 / buildTriageRows 8 / triageLabels 2 / triageListState 1 failed |
| Task 4 の実装後 | 5ファイル 116 passed、tsc 0 |
| Task 5 の後 | tsc 0、lint 0（警告は変更前からの6件だけ）、`pnpm test` 31 files / 485 passed（変更前 466）、`next build` 成功 |
| 初回読み込み量 | /settings の First Load: 分割しないと 206 → 218 kB、分割後 207 kB |

計画の ts / tsx のコードブロック65個が、検証した各段階のファイルにそのまま含まれることを機械的に照合した（不一致0）。
