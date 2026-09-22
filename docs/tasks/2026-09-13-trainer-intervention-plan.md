# フェーズ9 トレーナー介入（9.1 異常検知 → 9.2 デイリートリアージ）— 実装計画（確定版）

**作成**: 2026-09-13 / ブランチ（予定）: PR1 `feature/client-alerts` → PR2 `feature/daily-triage`（どちらも `develop/1.0.0` から切り、PR も `develop/1.0.0` に向ける）
**出典**: `IMPLEMENTATION_TASKS.md` フェーズ9 / `2026-07-08-solution-catalog.md` cat1 1-A（L33-53）・2-A（L83-99）・6-A（L213-228）、横断レビュー 1-2 / 1-3 / 1-6 / 1-7（L2039-2057）/ `2026-07-10-integration-decisions.md` 判断1（通知基盤）・判断7（横断標準）/ `lessons.md`。**カタログと食い違う箇所は統合判断に従う**
**オーナー決定（2026-09-13）**: 9.1 → 9.2 を続けて実装し、PR は2本。トレーナー宛の push は VAPID 設定（オーナー保留）が済むまで実装側から着手しない。当面は Web 内の表示（ダッシュボードとサイドバーのバッジ）で知らせ、ディスパッチャ経由の push は後から差し込める作りにする
**範囲外**: 9.3（睡眠→指導動線、6-A）。オーナー決定の範囲に入っていないので、`IMPLEMENTATION_TASKS.md` では未着手のまま残す
**着手条件**:
- 8.4（`fix/cron-retry-session-memo`。`_shared/retry.ts`、migration `20260913000200`・`000300`・`000400`）が develop にマージ済み
- リモートで 8.4 の `000400` が適用済み。`supabase db push` は未適用分をすべて流すので、000400（新しい Mobile ビルドを確認してから当てる約束）が残ったまま Phase 9 を push すると一緒に当たってしまう
- 作業は `.claude/worktrees` の worktree で行う（メインのチェックアウトは別セッションがブランチを切り替える）

## 実測で確定した前提（2026-09-13。リモートは SELECT で取った集計値だけ）

### 対象顧客とデータ規模
- 本番は実質テストデータ。トレーナー5名（顧客を持つのは1名）、顧客14名（全員が同じトレーナーの担当）
  - `auth.users` に行がある顧客は5名: 自己登録（`client_id = trainer_id`）1、記録あり・オンボーディング完了1、**記録ゼロ・オンボーディング未完了3（登録から31〜140日）**。5名のうち1名は別トレーナーの顧客になっているトレーナーアカウント（兼務）
  - 残り9名は旧フローの顧客でログインできない
- `clients.created_at` は NOT NULL DEFAULT now()。ログインできる顧客の行は Mobile が登録完了時に upsert する（`registration_provider.dart` L177-185）→ **登録日はサーバー時刻の痕跡として使える**
- `clients.trainer_id` は NOT NULL + FK trainers ON DELETE CASCADE（担当なしの状態は無い）
- 顧客数の上限は business 30 / pro 10 / free 3（`enforce_client_limit`）→ トレーナー単位の処理は最大30顧客
- 直近30日の記録は体重29件・睡眠53件（すべて healthkit）。食事・運動は0件、顧客の会話メッセージは1件
- 今のダッシュボードの「N日間記録なし」は14名中11名が「999日」（`getInactiveClients.ts` L129-134）
- 下の定義で今日（9/13）数えると、監視対象は1名（最終到着から6日）。アプリ未登録9・記録開始前3は対象外、自己登録は数えない

### 記録が届くタイミング（横断レビュー1-7の裏付け）
- データはアプリが前面にあるときしか届かない。HealthKit 同期は起動時・1時間以上たっての復帰時・60分タイマー・手動の4つで、毎回30日分を読み直す（`health_sync_provider.dart` L112-118、`app.dart` L96-156）。`UIBackgroundModes` も無い
- 到着遅れ（`created_at − 計測時刻`、初回の一括分を除く）: 体重は中央値 約19〜26時間・最大106時間。睡眠は中央値 約35時間・p90 約137〜147時間・最大170時間（15行中5行が72時間超）。標本は n=6 / 15 と小さい
- 初回連携で30日分がまとめて入る（体重47行中41行、睡眠74行中59行）。HealthKit 由来の体重は recorded_at がすべて JST 23:59
- 睡眠は同期のたびに約30行を upsert し、`updated_at` が同期時刻に変わる（`sleep_records_provider.dart` L31-63）。体重の healthkit 行は値が変わらない限り動かない。どちらの表にも `set_updated_at`（BEFORE UPDATE）トリガーがあり、一括 UPDATE をすると全行の updated_at が動く
- 「最後にアプリを起動した時刻」の列は無い（`device_tokens.last_seen_at` は端末の時計で、コールドスタート時だけ書かれる。行も1件）
- サーバー時刻で残る活動の痕跡: 登録（`clients.created_at`）、顧客の送信、トレーナー発メッセージの `read_at`、記録行の `created_at`、睡眠・体重の `updated_at`、`ai_estimation_logs.created_at`
  - messages の種別は client→trainer 305件と trainer→client 61件だけ（`sender_type` / `receiver_type` は NOT NULL）
  - Mobile の既読は `mark_messages_as_read` が `now()` で書く。Web の既読（`markMessagesAsRead.ts` L10）はブラウザの時計で書き、対象は `receiver_type='trainer'` の行 → 兼務アカウントの痕跡は type で分けられる
  - `mark_messages_as_read` はリモートにだけあり、migration に無い（ローカルのテストでは read_at を直接入れる）
- 60日分の日次シミュレーション（06:00 JST 時点・途絶3日）: 休眠中の旧顧客4名が毎日該当。新しい途絶の開始は2回で、うち1回は「計測はしていたがアプリを開いていなかった」だけ。「計測の途絶」と「アプリ未起動」は毎日一致した
- 同期・送信の時間帯（直近60日、14件・2名、JST）: 0〜6時3、6〜12時2、12〜18時4、18〜24時5

### 閾値の根拠になる分布
- 体重（JST の日ごとの代表値で、直近7日平均と前の7日平均を比べる。各窓3日以上のときだけ）: 評価できたのは42 client-day（2名）。最大 2.62% / 1.67kg、中央値 0.51%、p90 2.48% / 1.58kg。±3% / ±2kg 超は0件、±2% 超は2回（計8日、どちらも増加）。窓の日数条件を外すと ±3% 超が9日出るが、すべて1〜2日しかない窓
- 1日に最大10件、1日の中で最大20kg の幅がある日がある（2〜3月の message 由来のテストデータ）
- 目標の列は判定に使えない: 14名全員 `target_weight = 60`（NOT NULL DEFAULT 60 で未設定と区別できない）、`initial_weight` は全員 NULL、purpose は health_improvement 13 / contest 1 / diet 0、`goal_deadline` は1名（期限切れ）
- `calculate_achievement_rate` はリモートと migration で中身が違い、SECURITY DEFINER・search_path 未固定で anon から実行できる → Phase 9 からは呼ばない
- calories 入りの食事記録は0件、目標カロリーの列も無い → ルール④は計算も検証もできない

### メッセージ（9.2 用）
- 顧客→トレーナー305件のうち163件（53%）がタグ付きの記録投稿。タグの無い旧形式の記録メッセージ13件は、すべて 2026-02-07〜03-09
- Mobile はワークアウト達成もタグ `#運動:完了` 付きで送り、本文に「💬 感想」が入ることがある（`workout_screen.dart` L57-69）
- `tags IS NULL` が127件（判定では空として扱う）
- `read_at` は画面を開いただけで付く（既読 ≠ 返信）。既読の表示はすでにトレーナーに見えている（`MessageBubble.tsx` L70-71）
- sender / receiver に FK が無く、担当関係の無い孤児メッセージが66件
- RLS: messages の SELECT は `sender_id = auth.uid() OR receiver_id = auth.uid()`、clients は `trainer_id = auth.uid()`
- 今の担当顧客に絞ると、未返信の顧客は0名

### 通知基盤（push.ts の行番号は 8.4 で動くので関数名で参照する）
- `sendNotification` は dedup 行を先に INSERT してから設定・宛先を確かめる → skip でも行が残り、同じキーでは二度と送れない（8.4 で送り直せるのは resolve_error の行だけ）
- `resolveTargets` は user_id だけで引き、user_type で絞らない
- 今 push を配線しても届かない: トレーナーの `device_tokens` 0件、`push_subscriptions` の1件は未移行、VAPID 未設定
- ディスパッチャは URL を `data.url` に入れるが、`public/sw.js` はトップレベルの `url` しか読まない（sw.js L21, L31-39）
- `notification_preferences.kind` の CHECK は message / goal_achievement / session_reminder

### DB と運用
- PostgreSQL 15.8。alerts / alert_detection_runs / triage_actions は無く、名前の衝突も無い。リモート適用済みの最新 migration は `20260913000100`
- cron は4本 active（UTC）: issue-recurring-tickets `0 0` / send-session-reminders `0 11` / auto-skip-workouts `0 18` / cleanup-ai-images `0 19`。06:00 JST（`0 21`）は空き
- cron から SQL を直接呼ぶ前例あり（issue-recurring-tickets。`20260710020000` L91）
- 索引: 記録4表は `(client_id, recorded_at DESC)`（sleep は `(client_id, recorded_date DESC)`）、messages は `(sender_id, created_at DESC)` / `(receiver_id, created_at DESC)`、ai_estimation_logs は `(client_id, created_at DESC)`。顧客ごとの最終記録・最終メッセージの相関サブクエリは Index Only Scan（EXPLAIN 確認済み）→ 新しい索引は不要
- `ALTER DEFAULT PRIVILEGES` で、新しいテーブル・関数・シーケンスに anon / authenticated の権限が自動で付く → 作るたびに剥がす
- `clients_update_own` で顧客本人が clients の全列（purpose を含む）を UPDATE できる → トレーナーが決める値は clients に置かない
- `delete-account` は clients を DELETE して子テーブルを CASCADE で消す（`delete-account/index.ts` L118-131 のコメントに一覧がある）
- DEFINER 関数の書式は2通り: service_role 専用は `public, pg_temp`（`find_sessions_for_reminder`）、authenticated 向けは `''` と完全修飾（8.4 の `get_my_sessions`）

### Web
- ダッシュボードは `'use client'`。14個の取得関数を1つの `Promise.all`（`dashboard/page.tsx` L225）で呼び、個別に catch しているのは支払いサマリーだけ（L203-207）→ 1本でも失敗するとダッシュボード全体が空になる
- 今のアラートはクライアント側で組み立てている（L257-290: 非アクティブ上位3件・期限間近チケット・今週の未実施プラン）。表示はページ最下部の `AlertList`（L399、最大5件）。`getInactiveClients` の呼び出し元はダッシュボードだけ
- サイドバーのバッジは `/message` の未読専用（`layout.tsx` L119-147, L170）。Realtime の publication は messages と trainers だけ
- ディープリンク: `/message?clientId=`（`message/page.tsx` L48-49）、`/clients/<id>?tab=weight|sleep|meal|exercise|notes|tickets|summary`（`?tab=` は初期値としてだけ読む。L30-48）
- 規約: 書き込みは API Route（`requireTrainer` + `trainerOwnsClient` + `supabaseAdmin`、`src/lib/api/guards.ts`）。vitest は node 環境でコンポーネントのテスト基盤は無い。純関数と `'use client'` を同じファイルに置くと next build だけが落ちる（lessons「React hooks 入り共有モジュールを…」）。pnpm、sonner ^2.0.7、Radix は alert-dialog / dialog / label / select / slot / tabs だけ、アバターは `components/clients/ProfileAvatar.tsx`、Zustand のストアは `userStore.ts` だけ
- `ui/card.tsx` は rounded-xl + shadow でデザイントークンに反する。ダッシュボードは hex の任意値クラス・`rounded-md`・`border-[#E2E8F0]`・重要度の red / amber で揃っている
- プライバシーポリシー（`(legal)/privacy/page.tsx`）は「端末情報、ログ情報」の取得（L93）までで、同期の状況を担当トレーナーに見せることは書いていない

## カタログからの読み替え

| カタログの記載 | 本計画 | 根拠 |
|---|---|---|
| Edge Function `detect-client-anomalies` を cron で起動 | SQL 関数を migration 管理の pg_cron から直接実行。Edge Function は作らない | 判断7-3。push しない MVP に HTTP の段は要らない。issue-recurring-tickets が前例 |
| `push_subscriptions` + `/api/push-notify` で通知 | 当面は送らない。VAPID 設定後に device_tokens + `sendNotification` の別関数で足す | 判断1。/api/push-notify は 7.3 で削除済み |
| `alerts.title` / `body` 列 | 持たない。`payload` から Web の純関数で文言を作る | 導出値は保存しない（lessons「導出値を非正規化して保存すると必ずドリフトする」） |
| status `'muted'`、部分ユニーク `WHERE status='open'` | ミュートは拡張の alert_settings に置く。部分ユニークは `WHERE resolved_at IS NULL` | open だけに掛けると、対応済みにした翌朝に同じアラートが作り直される |
| `alert_settings` の PRIMARY KEY(trainer_id, client_id〈NULL〉, alert_type) | 拡張で作るときに `UNIQUE NULLS NOT DISTINCT` | 主キー列は NULL を持てない。PG 15.8 で使える |
| ②記録途絶 = 全記録の最終日時から3日超 | 3変種（未開始・記録/同期なし・記録なし）。サーバー時刻の到着で「同期済み」の境目を引き、登録日より前は数えない | 1-7、フェーズ9 のタスク文言「途絶判定を『最終アプリ起動』と分離」 |
| 減量目的は `purpose` と `target_weight` の方向で判定 | `purpose` だけで判定 | target_weight は全員が既定値の60 |
| ⑤と +20 点に `calculate_achievement_rate` | MVP では使わない | 中身のずれ・権限の穴があり、initial_weight も全員 NULL |
| `get_daily_triage(p_trainer_id)` SECURITY DEFINER | 引数なし・SECURITY INVOKER の `get_unreplied_clients_for_trainer()`。スコアは Web の純関数 | 他人の ID を渡して読める穴を作らず、RLS で二重に守る |
| `/message?client=` | `/message?clientId=` | 実装済みのパラメータ |
| AlertList の組み立て L224-257 を置き換え | 実際は L257-290。上部に「今日の対応」を新設し、下部カードは「チケット・プラン」に縮める | 現行コード |

## 設計判断

1. **検知は SQL 関数を cron から直接呼ぶ**（Edge Function・Vault・pg_net は不要）。例外は `cron.job_run_details` に failed として残るので、HTTP 経由の cron のように「succeeded と記録されたのに中身は失敗」が起きない（lessons「cron の『succeeded』は HTTP の成否ではない」）
2. **実行は1日1回、06:00 JST**。6〜12時の同期・送信は14件中2件で、昼に再評価しても解消できる件数は少ない。同じ対象日の再実行は冪等なので、回数は後から `alter_job` 1行で足せる
3. **dry run は `evaluate_client_alerts`（STABLE で書き込めない）、本実行は `run_client_alert_detection`（対象日は必須）**。読み取り専用であることが構造で保証され、MCP の読み取りでも実行でき、`p_as_of` を渡せばバックテストにも使える。本実行は締め時刻を受け取らない（既定値だけ）
4. **監視対象は「ログインできる・自己登録でない・最終到着（登録を含む）が14日以内」の顧客**（記録開始前は登録から14日以内）。対象外は理由別の人数だけ見せる（アプリ未登録・記録開始前・2週間以上データなし）。生きている record_gap があっても監視を延長しない（オーナー決定1。実装レビューで修正、2026-09-13）。監視対象は alerts に依存しないので、snapshot / evaluate は alerts の中身に左右されない
5. **記録途絶は3変種**で、上から1つだけ当てる: 一度も記録が無い（未開始）→ 到着が3日無い（記録・同期なし）→ 到着はあるのに記録が3日無い（記録なし）。「記録なし」は、最終到着より前かつ登録日以降の日だけを数える。登録直後に既読を付けただけの顧客を「60日以上の途絶」と判定しない
6. **体重は登録日以降の計測だけを使う**。初回連携の30日一括で、担当になる前の変化を検知しないため。検知できるのは登録から10日目以降になる
7. **解消はヒステリシスにする**。体重は評価でき、かつ成立値の8割未満になったら解消。評価できない日は状態を変えない。14日間再確認できなければ期限切れ
8. **重大度**: 途絶は3〜6日 medium、7日以上 high。対応済みでも昇格したら1回だけ再浮上させる。open のまま昇格したときも `surfaced_on` を更新する（後で push の対象を選ぶ列なので、昇格した行が漏れないように）
9. **外れ値**: 20〜300kg に絞り、日ごとの代表値は中央値、14日分の中央値から ±15% を超える日は除く（60kg の人に誤計測の80kgが1日混ざると、7日平均が約2.9kg 動いて閾値を超える）
10. **減量目的（purpose='diet'）の減少は medium に下げる**。前版では確認事項だったが、diet の顧客が0名で効果を確かめられず、評価関数の定数1箇所で変えられるので推奨案を既定にした。purpose は顧客本人も書き換えられるが、変わるのは重要度が1段下がることだけで検知は残るので、MVP では許容する（alert_settings を作るときにトレーナー側へ移す）
11. **push 用の列は持たない**（判断1: 冪等化は `notification_logs.dedup_key` に統一）。送る対象は `surfaced_on` で選ぶ
12. **ミュート・閾値 UI・日次上限・追加の実行回は拡張**。対応済みのアラートは条件が続く間は作り直さないので、毎日の再作成を止めるためのミュートは要らない。見込みは1トレーナーあたり1日0.03〜0.05件
13. **置き場所は PR1 から上部の「今日の対応」**（TodaysSchedule の上。カタログどおり）。PR2 は同じセクションに未返信を足すだけで、作り直さない
14. **トリアージの RPC は INVOKER で未返信だけを返し、スコアは Web で計算する**。messages と clients の RLS が本人の範囲に絞る。重みを migration なしで調整でき、vitest で固定できる。顧客は最大30名なので Web でまとめて足りる
15. **記録メッセージの除外は tags だけで判定する**。旧形式の13件は2〜3月のもので7日の窓に入らず、SQL と TS に同じ定義を二重に持たずに済む
16. **バッジは「今日の対応」に並ぶ顧客の数**。PR1 は open のアラートがある顧客、PR2 から未返信の顧客も合わせる。見出しの件数と揃える
17. **記録日の集合を返す汎用関数は作らない**。Phase 9 は表ごとの最大値で足りる。フェーズ10 のストリークで要るときに、`auth.uid()` 固定の INVOKER 関数として作る
18. 性能は検証の EXPLAIN で確認する（合成データでの計測スクリプトは拡張）

## PR 分割

### PR1 = 9.1 MVP（`feature/client-alerts`、目安5日）
**スコープ**
- Supabase: `alerts`・`alert_detection_runs` のテーブル、関数4本（活動スナップショット・評価・本実行・検知状態）、cron（inactive で登録）
- 検知ルール: ①体重急変、②記録途絶（3変種）
- Web: ダッシュボード上部の「今日の対応」（顧客ごとに理由を並べる、「対応済み」とトーストの「元に戻す」、検知状態と対象外の人数、医療判断ではない旨の注記）、サイドバー「ダッシュボード」のバッジ、クライアント側の「N日間記録なし」と `getInactiveClients` の撤去
- Edge Function: `delete-account` の CASCADE 一覧のコメントに alerts を足すだけ（コードは変えない。再デプロイ不要）
- Mobile: 変更なし（トレーナー専用のテーブルを足すだけで、clients も記録テーブルも変えない）

**拡張に回すもの**
- ミュートと閾値設定 UI（`alert_settings`、`/settings/alerts`、顧客ごとの上書き、目的・方向の上書き、目標カロリーの置き場所）
- 日次上限、昼・夕方の追加実行
- ルール③睡眠悪化・④カロリー超過・⑤期日接近×未達
- Mobile の heartbeat（アプリ起動を記録する仕組み）と HealthKit 連携状態の報告
- トレーナー向け push と cron 失敗監視ジョブ（オーナー確認3）
- アラート履歴の画面、ヘッダーのベルを通知センターにすること、Realtime でのバッジ更新
- 1-B の記録時点での即時検知
- `/clients/[id]` の `?tab=` をクエリの変化に追従させること

### PR2 = 9.2 MVP（`feature/daily-triage`、PR1 のマージ後。目安2日）
**スコープ**
- `get_unreplied_clients_for_trainer()`
- 「今日の対応」に未返信の顧客を合わせ、優先度スコア順に並べる（上位5件と「すべて表示」）
- 「返信する」の導線、バッジを未返信込みの数にする

**拡張に回すもの**
- `triage_actions`（完了・スヌーズ・返信不要。オーナー確認4）
- 朝のサマリー push
- AI 返信候補（3-A。判断6の ai_usage_logs が前提）
- 期日接近の +20 点
- 顧客一覧の要対応ソート（2-B）
- 記録カードからの引用返信（6-A の record_ref。判断7-1のレジストリ文書が前提）
- タグ付きメッセージに添えられた自由記述（ワークアウトの「💬 感想」など）を未返信として拾うこと

## データモデル

### `public.alerts`（PR1）

| 列 | 型・制約 | 意味 |
|---|---|---|
| id | uuid PK DEFAULT gen_random_uuid() | |
| trainer_id | uuid NOT NULL、FK → trainers(id) ON DELETE CASCADE | 検知した時点の担当トレーナー |
| client_id | uuid NOT NULL、FK → clients(client_id) ON DELETE CASCADE | 退会（delete-account の CASCADE）で一緒に消える |
| alert_type | text NOT NULL、CHECK IN ('weight_change','record_gap') | 種別を増やすときは CHECK を DROP → ADD し、既存の値を落とさない |
| severity | text NOT NULL、CHECK IN ('high','medium','low') | low は将来用 |
| status | text NOT NULL DEFAULT 'open'、CHECK IN ('open','acknowledged','resolved') | |
| payload | jsonb NOT NULL DEFAULT '{}' | 判定時点の値・閾値・期間・変種。表示用の文字列は入れない |
| first_detected_on | date NOT NULL | この発生を最初に検知した対象日（JST） |
| surfaced_on | date NOT NULL | open になった日（新規・再浮上）か、open のまま重大度が上がった日。並び順と、後で push の対象を選ぶのに使う |
| last_detected_on | date NOT NULL | 条件の成立を最後に確かめた対象日 |
| acknowledged_at | timestamptz | |
| reopened_count | smallint NOT NULL DEFAULT 0 | 1回の発生につき最大1 |
| resolved_at / resolved_reason | timestamptz / text CHECK IN ('cleared','expired','reassigned','ineligible') | |
| created_at / updated_at | timestamptz NOT NULL DEFAULT now() | updated_at は `public.update_updated_at_column()` のトリガー |

- 表の CHECK: `(status = 'resolved') = (resolved_at IS NOT NULL)`、`status <> 'acknowledged' OR acknowledged_at IS NOT NULL`
- 索引: UNIQUE `(client_id, alert_type) WHERE resolved_at IS NULL`（生きている発生は顧客×種別で1件）/ `(trainer_id) WHERE status = 'open'`（ダッシュボードとバッジ用）/ `(client_id)`（FK の CASCADE 用）
- RLS は有効にし、ポリシーは SELECT 1本だけ: `alerts_trainer_select` TO authenticated、`trainer_id = (select auth.uid()) AND EXISTS (SELECT 1 FROM public.clients c WHERE c.client_id = alerts.client_id AND c.trainer_id = (select auth.uid()))`。担当が替わったら前のトレーナーからは見えない。サブクエリの列はテーブル名で修飾し、`pg_get_expr` で解決先を確かめる（lessons「storage.objects ポリシーのサブクエリ内で…」）
- GRANT: `REVOKE ALL ... FROM anon, authenticated` のあと `GRANT SELECT ... TO authenticated`。書き込めるのは service_role（API Route）と検知関数だけ。顧客本人には見せない
- payload（`v` でバージョンを持つ。日付だけで時刻は持たない）
  - weight_change: `{v:1, direction, recent:{from,to,avg_kg,days}, previous:{from,to,avg_kg,days}, delta_kg, delta_pct, threshold:{pct,kg}, severity_reason?}`
  - record_gap: `{v:1, variant:'not_started'|'no_data'|'no_record', gap_from, gap_to, last_activity_on, last_record_on, threshold_days}`。日数は `gap_to − gap_from + 1` で表示時に出す（今日の日付に依らない）。`last_activity_on` の扱いはオーナー確認2に従う

### `public.alert_detection_runs`（PR1。運用ログ）
- 列: `id uuid PK DEFAULT gen_random_uuid()`（シーケンスを作らない）、`target_date date`、`as_of timestamptz`、`started_at` / `finished_at timestamptz`、`stats jsonb`（すべて NOT NULL）
- stats は件数だけ: 監視数、対象外の理由別（no_account / self / not_started / inactive）、種別・変種ごとの検知数、opened / updated / escalated / reopened / resolved（理由別）、重要度を下げた数。client_id や健康に関する値は入れない
- 行が入るのは本実行が成功したときだけ（失敗はトランザクションごと巻き戻る）
- RLS は有効でポリシーなし、`REVOKE ALL FROM anon, authenticated`

### 関数

| 関数 | 形 | EXECUTE | 役割 |
|---|---|---|---|
| `client_activity_snapshot(p_target_date date, p_as_of timestamptz, p_trainer_id uuid DEFAULT NULL)` | sql STABLE DEFINER | service_role のみ | 顧客ごとの `client_id, trainer_id, join_on, purpose, last_activity_on, last_record_on, exclusion_reason`。「活動」「記録」「監視対象」の定義はここ1箇所 |
| `evaluate_client_alerts(p_target_date date DEFAULT JST の今日, p_as_of timestamptz DEFAULT NULL)` | STABLE DEFINER | service_role のみ | 監視対象について `(client_id, trainer_id, alert_type, state 'detected'\|'cleared'\|'unknown', severity, payload)` を返す。dry run とバックテストを兼ねる |
| `run_client_alert_detection(p_target_date date)` | plpgsql VOLATILE DEFINER | service_role のみ（cron は postgres で実行） | 状態遷移と実行記録。対象日は必須で既定値なし。jsonb のサマリーを返す |
| `get_alert_detection_status()` | sql STABLE DEFINER | authenticated のみ | 検知状態と対象外の人数（契約参照） |
| `get_unreplied_clients_for_trainer()`（PR2） | sql STABLE **INVOKER** | authenticated のみ | 未返信の顧客（契約参照） |

- DEFINER の関数はすべて `SET search_path = ''` とし、テーブル・関数を完全修飾する（8.4 の `get_my_sessions` と同じ書式）
- `REVOKE ALL ... FROM PUBLIC, anon, authenticated` のあと、表の相手にだけ GRANT EXECUTE
- authenticated に開ける関数は、引数でトレーナー ID を受け取らず、戻り列を許可リストで固定する
- snapshot の COMMENT に書くこと: 活動痕跡の一覧、睡眠 upsert と `set_updated_at` への依存、「authenticated へ GRANT しない。公開するときは `auth.uid()` 固定の INVOKER ラッパーを作る」
- 既存の安全でない DEFINER 関数（`calculate_achievement_rate` など）は呼ばない
- Web の型は `src/types/alert.ts` と `src/types/triage.ts`。Mobile のモデルは変更しない

### 拡張で追加するもの（PR1・PR2 では作らない）
- `alert_settings(id, trainer_id, client_id NULL, alert_type, enabled, threshold jsonb, muted_until, created_at, updated_at)`。`UNIQUE NULLS NOT DISTINCT (trainer_id, client_id, alert_type)`、RLS は alerts と同じ形。追加するときは `evaluate_client_alerts` を CREATE OR REPLACE し、関数内の定数への上書きとして読む
- `triage_actions`（オーナー確認4で「入れる」になった場合は PR2 で作る）: `(id, trainer_id, client_id FK CASCADE, action CHECK IN ('dismiss_unreplied'), through_at timestamptz, created_at, updated_at)`、`UNIQUE (trainer_id, client_id, action)`、書き込みは API Route だけ

## 検知ルールの仕様

### 共通
- **対象日 D** = 実行した日の JST の暦日。cron は `(now() AT TIME ZONE 'Asia/Tokyo')::date` を渡す。評価の窓は D−1 で閉じる（06:00 時点では当日の計測はほとんど届いていない）
- **締め時刻 as_of** = `p_as_of`、指定が無ければ `LEAST(now(), (D+1) 0:00 JST)`
  - evaluate では、as_of が D の 0:00 JST より前、または now() より後なら例外にする
  - 記録（最終記録日 L と体重の窓）は、到着（`coalesce(created_at, recorded_at)`）と計測時刻の両方が as_of 以前のものだけを見る。活動の痕跡（最終到着 R）は**到着時刻だけ**が as_of 以前かで判定する（計測時刻は問わない。② の R の定義を参照）
  - 過去の日に p_as_of（その日の 06:00 JST）を渡すと、「その朝に見えていたデータ」に近い状態を再現できる
- **JST の暦日は範囲比較**: `recorded_at >= d::timestamp AT TIME ZONE 'Asia/Tokyo' AND recorded_at < (d+1)::timestamp AT TIME ZONE 'Asia/Tokyo'`。列に関数を掛けず、CURRENT_DATE を使わない（lessons「JST の『暦日』判定は範囲比較で書く」）。日付への変換は範囲で絞った後の SELECT / GROUP BY の中だけ。sleep は recorded_date（JST の起床日）をそのまま使う
- **登録日 J** = `clients.created_at` の JST 日付
- **監視対象**（snapshot の `exclusion_reason`。上から順に1つ）
  1. `no_account`: `auth.users` に行が無い
  2. `self`: `client_id = trainer_id`（人数にも数えない）
  3. （削除: 生きている record_gap による監視の延長は行わない。オーナー決定1）
  4. `not_started`: 記録が一度も無く、D − J > 14
  5. `inactive`: 最終到着 R < D − 14
  6. どれでもなければ監視対象（NULL）
- 閾値・窓の長さ・日数の定数は `evaluate_client_alerts` の冒頭1箇所にまとめ、根拠をコメントに書く

### ① 体重急変 `weight_change`
- 使うデータ: `recorded_at` が [max(D−14, J) の 0:00, D の 0:00)（JST）に入り、値が 20〜300kg の weight_records。source は問わない
- 日ごとの代表値は、その JST 日の中央値。14日分の代表値の中央値から ±15% を超える日は外れ値として除く
- 直近の窓 D−7〜D−1、前の窓 D−14〜D−8。**両方の窓に代表値が3日以上**あるときだけ評価する（登録日より前の計測を使わないので、評価できるのは D ≥ J + 10 から）
- Δkg = 直近の窓の平均 − 前の窓の平均、Δ% = Δkg ÷ 前の窓の平均 × 100
- 成立（detected）: **|Δ%| ≥ 3.0 または |Δkg| ≥ 2.0**。カタログの初期値のまま。実データでは0件、±2% にすると2回出る。20名規模に単純に広げても1日約0件（テスト端末2台からの外挿なので桁の目安だけ）
- 解消（cleared）: 評価でき、かつ |Δkg| < 1.6 **かつ** |Δ%| < 2.4（成立値の8割）
- 評価できない日と、成立値と解消値の間の日は `unknown`（状態を変えない）
- 重大度は high。purpose='diet' の減少だけ medium にし、`payload.severity_reason='diet_decrease'` を残す
- 期限切れ: 生きている weight_change のうち `last_detected_on ≤ D − 14` のものはすべて resolved（expired）。評価されなかった顧客の行にも掛ける
- 30日分の一括取り込みで、過去2週間の変化が後から検知されることがある（登録から時間がたって連携した顧客）。payload に比較期間を持たせ、画面に「いつの変化か」を出す

### ② 記録途絶 `record_gap`（1-7 への対応）
- **最終到着 R** = as_of 以前のサーバー時刻の痕跡のうち最も新しいものの JST 日付。対象は次のとおり
  - 登録（`clients.created_at`）
  - 顧客が送ったメッセージの `created_at`（`sender_id = 顧客 AND sender_type = 'client'`）
  - 顧客宛てメッセージの `read_at`（`receiver_id = 顧客 AND receiver_type = 'client'` かつ **今の担当トレーナーが送った分**（`sender_id = clients.trainer_id AND sender_type = 'trainer'`）だけ。messages の RLS は送信者に read_at・receiver 系の列を自由に書かせてしまうため、担当関係の無い第三者が既読を偽造して R を動かせないようにする。実装レビューで修正、2026-09-13）
  - weight / meal / exercise / sleep の `created_at`（NULL の古い行は recorded_at）、weight と sleep の `updated_at`
  - `ai_estimation_logs.created_at`
  - 端末の時計で書かれる値（workout の finished_at、device_tokens.last_seen_at）と、Web の既読は使わない
  - 記録テーブルは計測時刻で D−60 以降に絞ってから最大値を取る（14日以内に届いた行は計測がそれより最大30日前までなので漏れず、既存の複合索引が効く）
  - R は**到着時刻だけ**で判定し、計測時刻の上限（≤ as_of）は掛けない。HealthKit の体重は recorded_at が計測日の JST 23:59 なので、06:00 前に同期された当日分が到着に数えられず、体重だけ連携している顧客が「記録・同期なし」に誤判定されるため（実装レビューで修正、2026-09-13）。L（最終記録日）は従来どおり計測日と到着の両方で絞る
- **最終記録日 L** = 計測日が D−1 以前で、到着が as_of 以前の記録のうち最も新しい JST 日付（全期間。表ごとに `ORDER BY recorded_at DESC LIMIT 1` で索引を使う）。記録には顧客が送ったメッセージ（タグの有無は問わない）も含める（カタログ「全記録種別＋メッセージ」）。1件も無ければ NULL
- **判定**（上から1つだけ当てる。N = gap_to − gap_from + 1）
  1. L が NULL → 変種 `not_started`: gap_from = J、gap_to = D−1（N = D − J）。N ≥ 3 で detected。表示は「登録から N日・記録なし」
  2. (D−1) − R ≥ 3 → 変種 `no_data`: gap_from = R+1、gap_to = D−1。表示は「記録・同期なし N日」
  3. 記録なしの日数 ≥ 3 → 変種 `no_record`: gap_from = max(L, J−1) + 1、gap_to = min(R, D) − 1。表示は「記録なし N日」。R より前は同期済みと見なせるので、そこで記録が無い日は「記録が無い」と確定できる。登録日より前は数えない
  4. どれでもなければ cleared
- 新規作成は監視対象であれば常に行う。監視条件（最終到着が14日以内、未開始は登録から14日以内）があるので、no_data は最大13日、not_started は最大14日で打ち切られる。no_record（アプリは使っているのに記録が無い）は長さで打ち切らない
- 重大度: N が 3〜6 なら medium、7 以上なら high。変種が変わっても行は1つのままで payload を更新する
- 閾値の3日はカタログどおり。R はサーバーへの到着で決まるので、HealthKit の遅れ（睡眠の p90 は約6日）は「記録なし」の誤判定にならない
- 依存関係: 睡眠の `updated_at` を同期の代わりに使えるのは、Mobile の upsert が毎回約30行を更新するから。体重だけ連携している顧客は、新しい計測が無いとアプリを開いても何も書かれないので「記録・同期なし」に分類される（閾値も重要度も同じで、違うのは表示だけ）

### 状態遷移（すべて条件付き UPDATE。API と同時に走っても片方しか通らない）
1. **対象外になった行**: 生きている行の顧客が `no_account` / `self` になった、または snapshot に現れない（created_at が有限でない等）なら resolved（ineligible）
2. **担当替え**: 生きている行の trainer_id が今の `clients.trainer_id` と違えば resolved（reassigned）。新しい担当の分は同じ実行の中で作れる
3. **期限切れ**: 生きている weight_change で `last_detected_on ≤ D − 14` のものを resolved（expired）。生きている record_gap で、顧客が not_started / inactive（監視対象外）になったものも resolved（expired）（段 3-2）
4. **新規**: detected で生きている行が無ければ open で INSERT（first_detected_on = surfaced_on = last_detected_on = D）
5. **継続**: detected で生きている行があれば payload・severity・`last_detected_on = GREATEST(last_detected_on, D)` を更新。重大度が上がったとき
   - status が open なら `surfaced_on = D`
   - status が acknowledged で reopened_count = 0 なら、open に戻す（acknowledged_at = NULL、reopened_count = 1、surfaced_on = D）
6. **解消**: cleared なら resolved（cleared）
7. **トレーナーの操作**（API）: open → acknowledged（「対応済み」）、acknowledged → open（「元に戻す」。resolved になる前だけ）
- resolved は終端。再発したら新しい行を作る

### 冪等性とガード
- `run_client_alert_detection` は `pg_advisory_xact_lock` で直列に実行する
- 例外にする条件は3つだけ: 対象日が NULL / JST の今日より未来 / 最後に成功した本実行の対象日より前（古い窓で新しい状態を上書きしないため）。同じ対象日の再実行は許す
- 同じ対象日の再実行は同じ状態に収束する（新規0、更新 n）。今日の対象日なら as_of = now() なので、後から届いたデータの分だけ結果が新しくなる
- 生きている行の二重作成は部分ユニーク索引が防ぐ。違反したら実行全体がロールバックされ、`cron.job_run_details` に failed で残る

### 見込み件数（調査時点のデータ）
- 有効化の初回: 0〜1件（監視対象1名が最終到着から6日。有効化が9/21 以降なら対象外になる）。記録開始前3名は登録から14日を過ぎているので出ない。weight_change は0件
- その後: 1トレーナーあたり1日0.03〜0.05件
- 監視対象が1名しかいないので、見込みは有効化の直前に dry run を取り直して確かめる

## cron と Edge Function
- **ジョブ `detect-client-alerts`**: schedule `0 21 * * *`（06:00 JST。UTC では前日21時）、command `SELECT public.run_client_alert_detection((now() AT TIME ZONE 'Asia/Tokyo')::date);`
  - 登録は DO ブロックで jobname がまだ無いことを確かめてから `cron.schedule` し、直後に `cron.alter_job(active := false)`（`20260913000000` L135-159 の書式）
  - HTTP を使わないので、Vault・pg_net・apikey・タイムアウトの設定は要らない
  - 有効化は、リモートで dry run とバックテストをした後にオーナーが行う
- **dry run の既定**: dry run は `evaluate_client_alerts` だけ（書き込めない）。`run_client_alert_detection` には dry_run フラグも対象日の既定値も持たせず、呼んだら本実行になる。後で作る push 関数は既存の規約（lessons「push を伴う cron 起動 Function は dry_run 省略時に送らない」）に従う
- **バックテスト**
  - 過去30日の各日 d について `evaluate_client_alerts(d, d の 06:00 JST)` を流し、**前日に detected でなかった（顧客, 種別）が detected になった件数**（新規）を1日ごとに数える。続いている発生を毎日数えると、有効化の判断基準（1日の新規件数）と比べられない
  - 監視対象は alerts に依存しないので、バックテストはいつ取っても同じ結果になる（本実行の前後を問わない）
  - 睡眠の updated_at は後の同期で上書きされ、過去の到着の痕跡が一部失われる → 「記録・同期なし」を多めに数える方向にずれる（安全側）
- **再試行ヘルパー**（8.4 の `_shared/retry.ts`）: PR1・PR2 には HTTP の段が無いので使わない。後で作る push 関数では DB の読み取りだけを `withRetry` で包み、`sendNotification` は包まない
- **失敗の見える化**
  1. 例外は `cron.job_run_details` に failed で残る
  2. 成功した本実行ごとに `alert_detection_runs` に1行
  3. Web に最終チェック時刻と「まだ実行されていない」「30時間以上前（遅延）」「停止中」を出す
  4. 手順書に確認用の SQL（直近7日の job_run_details と runs）を載せる
- 判断7-3 の cron 失敗監視ジョブは PR1・PR2 に含めない（オーナー確認3。推奨はトレーナー向け push の配線と同時に作る）
- **Edge Function のレーン**: 新規は無し。変更は `delete-account/index.ts` のコメントだけ（`_shared/push.ts` を含め `_shared/` には触らない）

## リリース順序とロールバック
**PR1 のリリース順序**
1. PR1 を develop にマージ。Supabase のリモートは1プロジェクトだけなので、Web のどのデプロイも同じ DB を読む。migration 適用前は「今日の対応」だけが取得失敗の表示になり、他のカードは影響を受けない（取得を分けているため）
2. 着手条件の 000400 が適用済みであることを確かめてから、オーナーの確認後にルートから `supabase db push`
3. Advisors（security）で、新しい関数に function_search_path_mutable などが出ていないことを確かめる
4. MCP の読み取りで evaluate の dry run と30日のバックテスト
5. 有効化の直前に dry run を取り直す → オーナーが run を1回手動実行 → cron を有効化
6. 翌朝、`cron.job_run_details`・`alert_detection_runs`・alerts の件数を SQL で確かめる
7. その後に develop → main（Vercel 本番）。本番のトレーナーには「未実行」「停止中」の状態が見えない

**ロールバック**（手順書に載せる）
- 止めるだけ: `cron.alter_job(active := false)`。データは残り、ダッシュボードは「停止中」を出す
- 撤去: ① Web を revert して本番に出す（`getInactiveClients.ts` と旧表示も戻る）→ ② 新しい migration で `cron.unschedule('detect-client-alerts')` → DROP FUNCTION（status → run → evaluate → snapshot の順）→ DROP TABLE（alert_detection_runs → alerts）。alerts を消すと対応済みの履歴も消える。適用済みの migration ファイルは消さない。Web を先に戻さないと、DB を落とした時点で「今日の対応」が取得失敗になる
- PR2: Web を revert してから `get_unreplied_clients_for_trainer()` を DROP

## Web UI

### PR1
- **置き場所**: KPI カード（`dashboard/page.tsx` L317 付近）の直後、売上カードと「本日の予定」より上に「今日の対応」セクション
- **取得**: コンテナの `TriageSection` がアラートと検知状態を自分で取る（`Promise.allSettled`）。ページの `Promise.all` には入れず、migration 未適用や RPC の失敗でダッシュボード全体が空にならないようにする。取り直すのは、表示時・タブに戻ったとき（visibilitychange）・操作の後
- **1行 = 1顧客**
  - アバター（`ProfileAvatar`）、顧客名（`/clients/<id>` へのリンク）、理由のチップ（例:「体重 +2.4kg」「記録・同期なし 4日」「記録なし 4日」「登録から5日・記録なし」）
  - 主ボタン「記録を見る」（weight_change は `?tab=weight`、record_gap は `?tab=summary`）と「メッセージ」（`/message?clientId=<id>`）
  - 行を開くと（`aria-expanded` の disclosure）、理由ごとの詳細・検知日・「対応済み」ボタンが出る。PR2 でも形は変えない
- **文言**（重要度は色だけでなく「要確認」（high）・「注意」（medium）と文字でも示す）
  - 体重:「体重の急な変化」「7日平均 +2.4kg（+3.4%）。9/6〜9/12 と 8/30〜9/5 の比較」
  - not_started:「記録開始前」「9/8 に登録してから、記録もメッセージもありません」
  - no_data:「記録・同期なし 4日」「9/9 以降、記録も同期も届いていません（計測していても、アプリを開くまで届かないことがあります）」。「アプリを開いていない」とは書かない
  - no_record:「記録なし 4日」「最後の記録は 9/8 です（9/12 まではアプリからのデータが届いています）」。最後の記録が登録日より前（HealthKit の初回取り込みなど）のときは「9/9 に登録してから記録がありません（9/12 まではアプリからのデータが届いています）」（日数と日付が食い違って見えないように。実装レビューで追加）
  - 到着日（R）に触れる括弧書きは、オーナー確認2の結論に合わせて出す・消す
- **並び順**: 顧客ごとの最大の重要度 → surfaced_on の新しい順 → 名前。上位5件を出し、「すべて表示（N件）」でその場に展開
- **対応済み**: 押したら先に行から外し、sonner のトースト「対応済みにしました」と「元に戻す」を出す。API が失敗したら行を戻してエラーのトーストを出す。バッジも取り直す。この状態遷移（楽観的更新・元に戻す・失敗時の巻き戻し・展開）は純関数の reducer に切り出し、vitest で固定する（コンポーネントのテスト基盤が無いため）
- **状態ごとの表示**（どれもヘッダーは残す）
  - 読み込み中: スケルトン
  - 取得失敗:「対応リストを読み込めませんでした」と「再読み込み」
  - 0件:「確認が必要な顧客はいません」と、最終チェック時刻・自動チェックの対象人数。「すべて順調」とは書かない
  - 未実行・遅延・停止中: それぞれの警告
  - 対象外がいるとき:「自動チェックの対象外: アプリ未登録 9人・記録開始前 3人」のように理由別の人数（表示した時点の数）
  - ヘッダーに「6:00 時点の自動チェック」と書く
- 注記: セクションの下に常に「健康データからの自動判定です。医療的な判断ではありません。」
- **サイドバー**: `renderNavItem` を、項目ごとにバッジの値と色を受け取れる形に広げる。「ダッシュボード」に「今日の対応」の顧客数を出す（aria-label「今日の対応 N人」）
  - 値は `triageBadgeStore`（Zustand、persist しない）で持つ
  - 取り直すのは、レイアウトの表示時・pathname の変化・タブに戻ったとき・操作の後
  - Realtime は使わない（検知は1日1回で、publication も増やさない。横断1-5）。PR2 で未返信を合わせたあとも同じ方針で、/message で返信を送った直後にも取り直す。新着の未返信は次の画面遷移かタブ復帰で反映される
- **下部のカード**: 'inactive' の組み立てを外し、見出しを「チケット・プラン」に変え、空の状態の文言も直す
- ヘッダーのベルには触らない（(auth) レイアウトでも描画されている）

### PR2
- 同じセクションに未返信の理由（例:「未返信 18時間・2件」）を加え、未返信があれば主ボタンを「返信する」（`/message?clientId=`）にする
- 並び順はスコアの降順。スコアは並べるためだけに使い、数値は出さない（見かけの精度を持たせない）
- アラート・未返信・検知状態は並列に取る。どれかが失敗しても取れた分は出し、失敗した部分だけセクション内でエラーと再読み込みを出す
- 小さく「未返信は表示した時点、アラートは 6:00 時点の判定」と書く。サイドバーの「メッセージ」の数（未読）と違うことが分かるよう、「未返信 = 最後のメッセージが顧客からで、まだ返信していない」を見出しのヘルプに書く
- バッジは、open のアラートがある顧客と未返信の顧客を合わせた数にする

### デザイン方針（UI レーンに委託する前に、マネージャーが `fit-connect:ui-ux-pro-max` を実行し、既存のトークンと合う規則だけを採る）
- カードは既存ダッシュボードと同じ `bg-white rounded-md border border-[#E2E8F0]`。`ui/card.tsx` は使わない
- 角丸は 6px（最大 8px）、8px グリッド。グラデーションと濃い影は使わない
- 文字色は #0F172A / #475569 / #94A3B8。主ボタンとバッジはアクセントの #14B8A6。red / amber は重要度の表示だけ
- フォントは Noto Sans JP と Plus Jakarta Sans
- Radix のパッケージは足さない（disclosure は `<button aria-expanded>` で作る）
- 行全体をリンクにしない（操作できる要素を入れ子にしない）
- ボタンのアクセシブルな名前に顧客名と種別を入れる（例:「田中さんの体重の変化を対応済みにする」）
- フォーカスリングを見せ、キーボードだけで全操作できるようにする。トーストは polite で読み上げる
- アニメーションは 150〜200ms で、`prefers-reduced-motion` を尊重する

## 通知（VAPID 待ちの間と、後で push を足す場所）
- **PR1・PR2 では `sendNotification` を呼ばず、通知種別（kind）も足さない**
  - 今呼ぶとすべて skipped（no_tokens / vapid_not_configured）で終わり、dedup キーだけを使い切って後から送り直せなくなる
  - 届かない種別のトグルを Web の通知設定に出すと紛らわしい（判断1: 設定は notification_preferences に一元化し、push を配線するときに種別を足す）
- **後で足す手順**（後続タスク。オーナーの VAPID 設定の後）
  1. 前提を直す: トレーナーの Web Push 購読を `device_tokens(web_push)` に入れる（push_subscriptions の1件を移すか、再購読の導線を作る）/ `sw.js` が `data.url` を読んでクリックでその URL を開く / `resolveTargets` を user_type で絞る（兼務アカウントで顧客用のスマホに届かないように）/ `/clients/[id]` の `?tab=` をクエリの変化に追従させる
  2. 種別 `client_alert` を追加する: push.ts の kind、CHECK の migration（先にリモートへ適用）、Web の `NotificationSection`（一覧と読み込みのフィルタ）。トレーナー専用なので Mobile の enum は不要
  3. Edge Function `notify-trainer-alerts` を作る: cron は 06:10 JST、認証は isServiceRequest + verify_jwt=false、dry_run 省略時は送らない、本送信では target_date 必須。対象は `status='open' AND severity='high' AND surfaced_on = target_date`（新規・再浮上・open 中の昇格のすべてが入る）。dedupKey は `client_alert:<alert_id>:<surfaced_on>`、`data.url` は `/clients/<id>?tab=…`。ロック画面に健康の数値を出さない文面にする
  4. 朝のまとめ（2-A の拡張2）は同じ関数の最後に `daily_triage:<trainer_id>:<対象日>` で1通だけ
  5. 判断7-3 の cron 失敗監視ジョブも、この配線に載せて作る（オーナー確認3）
- alerts に `surfaced_on` と `reopened_count` があるので、テーブルを変えずに上の手順で足せる

## 契約（レーン間で共有する。変えるときは全レーンに知らせる）

### API `PATCH /api/alerts/[id]`（PR1）
- body は `{ action: 'acknowledge' | 'reopen' }`。純関数 `parseAlertPatchBody` で検証し、それ以外は 400
- `requireTrainer()` で認証し、trainer_id はセッションから取る。対象を supabaseAdmin で読み、`trainer_id` が本人でない、または `trainerOwnsClient` を満たさなければ 404（存在しない場合も同じ）
- 条件付き UPDATE: acknowledge は `status = 'open'` の行だけ（acknowledged_at = now()）、reopen は `status = 'acknowledged' AND resolved_at IS NULL` の行だけ（acknowledged_at = NULL）。0行なら今の status をそのまま 200 で返す（冪等）
- 返却: `{ status: 'ok', alert: { id, status } }`

### RPC `get_alert_detection_status()`（PR1）
- 戻り列: `enabled, last_succeeded_at, last_target_date, monitored_count, excluded_no_account, excluded_not_started, excluded_inactive`
- 呼び出したのがトレーナー（trainers に行がある）でなければ0行
- 人数は、呼び出したトレーナー（`auth.uid()`）の担当顧客だけを `client_activity_snapshot(JST の今日, now(), auth.uid())` で表示した時点に数える（06:00 時点の値ではない。自己登録は数えない）。全トレーナー合算の runs.stats からは出さない
- `enabled` は cron.job の active、`last_*` は alert_detection_runs の最新行

### RPC `get_unreplied_clients_for_trainer()`（PR2）
- 戻り列（許可リスト）: `client_id, client_name, profile_image_url, unreplied_since, latest_unreplied_at, unreplied_count`
- 未返信の定義
  - 今の担当顧客（`clients.trainer_id = auth.uid()` かつ `client_id <> auth.uid()`）から自分宛て（`receiver_id = auth.uid()`、`sender_type = 'client'`）に届いた、**タグ無し**（`coalesce(cardinality(tags), 0) = 0`）のメッセージ
  - そのうち、トレーナーがその顧客に最後に送ったメッセージ（タグの有無は問わない）より後のもの
  - 最新の未返信が **7日以内** の顧客だけ
  - 削除済みの顧客とのメッセージは clients との JOIN で落ちる
- 使う索引は `(sender_id, created_at DESC)` と `(receiver_id, created_at DESC)`。新しい索引は要らない
- **実装で補強した点（2026-09-22、PR2 レビュー後）**
  - 「返信」はトレーナーとして送ったメッセージ（`sender_type = 'trainer'`）だけ。兼務アカウントが相手の顧客として送った記録投稿で、未返信が消えないようにする
  - 顧客のメッセージは `isfinite(created_at) AND created_at <= now()` のものだけ数える（messages の INSERT ポリシーは sender_id しか見ないため、未来・無限の日時で未返信が消えなくなる・画面の時間計算が壊れるのを防ぐ）
  - 「今の担当顧客」の判定は `clients.trainer_id` を信用している。この列を顧客が書き換えられる既存の穴は、RLS の列ガードの別タスクで塞ぐ
  - 性能: 関数本体で `(SELECT auth.uid())` と書くと計画時に値が分からず、顧客ごとに受信箱全体を走査する計画になった（155ms）。`auth.uid()` を直接書き、返信が無いときの `-infinity` は最後の返信を求めるサブクエリの中で coalesce して、索引が効く形にした（1.3ms）

### スコア `triageScore`（PR2、Web の純関数）
- 式はカタログ 2-A の式に上限を付けたもの: `min(未返信の時間, 72) × 2 + open のアラート（high 30 / medium 10）+ open の record_gap の日数（上限14）× 5`
- 期日×達成率の +20 は入れない。acknowledged のアラートは点に入れない
- 同点のときは、未返信が古い順 → 最初の検知日が古い順 → 名前
- 重みは定数としてこのファイルに置き、テストで固定する

## タスク分割

### PR1（9.1）

#### レーンA: Supabase（統括の supabase エージェント。migration の番号は着手時に 8.4 の `20260913000400` より後で採番し直す）
1. `supabase/migrations/20260914000000_client_alerts.sql`
   - 79桁の罫線ヘッダに背景・方針・出典
   - `alerts` / `alert_detection_runs`（列・CHECK・索引・FK・updated_at トリガー・RLS・ポリシー・REVOKE / GRANT・COMMENT）。DO ブロックと IF NOT EXISTS で冪等に書く
2. `supabase/migrations/20260914000100_client_activity_snapshot.sql`: `client_activity_snapshot`（COMMENT に活動痕跡の一覧・睡眠 upsert と set_updated_at への依存・GRANT しない旨）
3. `supabase/migrations/20260914000200_client_alert_detection.sql`: `evaluate_client_alerts` / `run_client_alert_detection` / `get_alert_detection_status`、cron `detect-client-alerts`（inactive で登録）
4. `supabase/tests/client_alerts_rls_test.sql`（`sessions_rls_test.sql` / `notification_prefs_logs_rls_test.sql` の構造を踏襲）
   - (a) 担当トレーナーには見える (b) 他のトレーナーには0行 (c) 担当が替わった後、前のトレーナーには0行 (d) 顧客本人には0行
   - (e-1) anon（クレーム無し）/ (e-2) anon（クレーム付き）は permission denied
   - (f) authenticated の INSERT / UPDATE / DELETE は insufficient_privilege
   - (g) `alert_detection_runs` は anon・authenticated とも拒否
   - (h) EXECUTE: service_role 専用の3関数は authenticated と anon で拒否。`get_alert_detection_status` は anon で拒否、トレーナーは実行でき、**トレーナー B が呼んでも A の顧客は人数に入らない**、顧客が呼ぶと0行
   - (i) service_role は書き込める
5. `supabase/tests/client_activity_snapshot_test.sql`
   - 痕跡の種類ごとの取り込み（登録日を含む）。as_of より後に届いたものは数えない。created_at が NULL なら recorded_at。計測時刻が未来でも as_of までに届いた行は R に数え、L には数えない。HealthKit の体重（recorded_at が当日 23:59、到着が当日 05:00）は 06:00 の R に入る（ケース k）
   - トレーナーが送ったメッセージの `created_at` は顧客の活動に数えず、顧客宛ての `read_at` は数える
   - **兼務**: そのアカウントがトレーナーとして送ったメッセージ・トレーナーとして付けた既読（`receiver_type='trainer'`）は顧客の活動に数えない
   - 端末の時計で書かれる列を使っていない
   - L: 記録4表とメッセージ、sleep の recorded_date、JST の境界（D の JST 0:30 = UTC 前日 15:30 は D−1 に入らない）
   - exclusion_reason: no_account / self / not_started（D − J = 14 は監視、15 は対象外）/ inactive（R = D−14 は監視、D−15 は対象外）/ 生きている record_gap があっても対象外は対象外 / p_trainer_id で絞れる / created_at が有限でない顧客は返らず例外にもならない / 担当関係の無い送信者の既読は R に数えない
6. `supabase/tests/client_alert_detection_test.sql`
   - **方針（ヘッダに明記）**: BEGIN の直後に alerts と alert_detection_runs を DELETE する（ROLLBACK で戻る）。件数・状態の assert は試験用の顧客に限る（seed の顧客にも行ができるため。`session_reminder_test.sql` と同じ）。対象日は過去の固定日。**締め時刻の境界は evaluate(p_as_of) で確かめ、run の遷移テストは既定の as_of（D+1 の 0:00 JST）を前提に created_at を明示して書く**
   - (a) JST の境界: (D−7) の JST 0:30 は直近の窓、(D−8) の JST 23:30 は前の窓、D の JST 0:30 は窓の外。最終到着が (D−3) の JST 0:30 なら検知せず、(D−4) の JST 23:30 なら検知。UTC の日付で判定すると結果が変わるデータにする
   - (b) 体重: 2.9% かつ 1.9kg は不成立、3.0% ちょうど / 2.0kg ちょうどで成立。片方の窓が2日なら評価しない。1日10件の中の外れ値は中央値で安定。±15% 超の日と範囲外の値（10kg）は除外。ヒステリシス（3.1% → 2.6% で継続、2.3% で解消）。14日再確認されなければ expired（評価されなかった顧客の行にも掛かる）。**登録日より前の計測は使わない**
   - (c) diet の減少は medium、diet の増加と他の purpose の減少は high
   - (d) 途絶
     - **登録翌日・既読だけ・記録なし → 検知しない**。**登録から3日（D = J+3）→ not_started・N=3・medium**。登録15日超の未開始 → 作らない（対象外）
     - no_data（3日で medium、7日で high）。no_record（前日に既読はあるが4日記録なし）。HealthKit の体重が 06:00 前に届いた顧客は no_data にならない（d-healthkit）
     - 最後の記録が登録日より前でも、日数は登録日から数える
     - evaluate で、締め時刻より後に届いた計測は数えずに no_data になり、締め時刻を後ろにずらすと cleared
   - (e) 対象外: auth が無い / 自己登録 / 最終到着が D−15（生きている行が無い場合）
   - (f) 状態遷移を1本の流れで: 作成 → 同じ日の再実行で行数は変わらず payload が更新 → 対応済み → 条件が続いても acknowledged のまま → 7日で high に上がり1回だけ再浮上、2回目の昇格では再浮上しない → cleared → 再発で新しい行。別の顧客で **open のまま medium → high に上がると surfaced_on = D**
   - (g) 担当替えは reassigned で閉じ、新しい担当の分ができる。auth.users の削除・自己登録化で ineligible
   - (h) ガード: 対象日が NULL / 未来 / 最後の本実行より前なら例外。evaluate の as_of が範囲外なら例外
   - (i) evaluate は `BEGIN READ ONLY` の中でも実行でき、行数を変えない
   - (j) 本実行が1回成功すると alert_detection_runs が1行増え、stats に client_id が含まれない
   - (k) 生きている行を二重に INSERT すると unique_violation
   - (l) cron: jobname が1件だけ、schedule が `0 21 * * *`、command に `run_client_alert_detection` と `'Asia/Tokyo'` を含み `net.http_post` を含まない。**command を `EXPLAIN`（ANALYZE なし）で解析・計画でき、前後で alerts の件数が変わらない**（`cron_jobs_test.sql` (e) と同じ）。active はアサートしない
   - (m) 関数の定義に `'Asia/Tokyo'` が含まれる。DEFINER の関数すべてに search_path が設定されている（proconfig）
7. `docs/tasks/2026-07-10-cron-vault-setup.md` に `detect-client-alerts` の節を足す: dry run、30日バックテスト（新規件数の数え方・alerts が空のうちに取る）、有効化直前の dry run の取り直し、初回の手動実行、有効化と停止、ロールバック（撤去の順序と履歴が消える旨）、翌朝の確認 SQL、ローカルで QA 用データを入れる手順（weight_records.updated_at の既定値 now() が「今日同期した」痕跡に数えられるので、QA データでは updated_at を明示する）、Vault 不要の明記、**weight / sleep を一括 UPDATE する migration では set_updated_at を一時的に無効にするか、前後で検知を止める**

#### レーンB: Edge Function
1. `supabase/functions/delete-account/index.ts`: L118-131 のコメントの CASCADE 一覧に `alerts` を足す（コードは変えない。再デプロイ不要）

#### レーンC: Web（UI・API・クエリは nextjs-ui、ストアは zustand。UI の委託前に ui-ux-pro-max を実行）
1. `fit-connect/src/types/alert.ts`: `ClientAlertType` / `AlertSeverity` / `AlertStatus` / payload の判別共用体（3変種）/ `ClientAlert` / `AlertDetectionStatus`。既存 `AlertItem.tsx` の `AlertType` とは別の名前にする
2. `fit-connect/src/lib/alerts/describeAlert.ts` と `.test.ts`: 見出し・詳細文・重要度のラベル・リンク先のタブ・日数（payload の gap_from / gap_to から）。未知の alert_type や `v`、payload の欠けで落ちない。日付の表示は `lib/payments/jstDate.ts` を使い、UTC の日付で壊れるケースを入れる
3. `fit-connect/src/lib/alerts/detectionStatus.ts` と `.test.ts`: 「未実行 / 最新 / 遅延（30時間超）/ 停止中」の判定
4. `fit-connect/src/lib/alerts/validation.ts` と `.test.ts`: `parseAlertPatchBody`
5. `fit-connect/src/lib/triage/buildTriageRows.ts` と `.test.ts`: アラートを顧客ごとにまとめて並べる。バッジ用の顧客 ID 集合も返す（PR2 で未返信を合流させる）
6. `fit-connect/src/lib/triage/triageListState.ts` と `.test.ts`: 対応済み（楽観的に外す）・元に戻す・API 失敗時の巻き戻し・展開の reducer
7. `fit-connect/src/app/api/alerts/[id]/route.ts` と `fit-connect/src/app/api/alerts/alerts-auth.test.ts`（`tickets-auth.test.ts` の vi.hoisted / vi.mock の書き方）: 未認証 401、不正な body 400、他人のもの・存在しない・担当変更済みは 404、条件付き UPDATE と冪等（200）
8. `fit-connect/src/lib/supabase/getOpenAlerts.ts`: `status='open'` に絞り、`clients!inner(name, profile_image_url)` を埋め込む。絞り込みは RLS に任せ、trainer_id を引数で受け取らない
9. `fit-connect/src/lib/supabase/getTriageBadgeCount.ts`: open のアラートがある顧客の数（PR2 で未返信を合わせる）
10. `fit-connect/src/lib/supabase/getAlertDetectionStatus.ts`: RPC を呼ぶ
11. `fit-connect/src/lib/alerts/updateAlertStatus.ts`: API を呼ぶだけの fetch 関数（フックは入れない）
12. `fit-connect/src/store/triageBadgeStore.ts`: 顧客数と `refresh()`
13. `fit-connect/src/components/dashboard/TriageRow.tsx` / `TriageList.tsx`: 表示専用
14. `fit-connect/src/components/dashboard/TriageSection.tsx`: 取得、各状態の表示、対応済みと元に戻す（reducer を使う）、バッジの更新
15. `fit-connect/src/app/(user_console)/dashboard/page.tsx`: TriageSection を KPI の直後に置き、`getInactiveClients` の呼び出しと 'inactive' の組み立てを削除
16. `fit-connect/src/components/dashboard/AlertItem.tsx` / `AlertList.tsx`: 型から 'inactive' を外し、見出しを「チケット・プラン」、空の状態の文言を直す
17. `fit-connect/src/app/(user_console)/layout.tsx`: バッジを項目ごとに出せる形に広げる
18. `fit-connect/src/lib/supabase/getInactiveClients.ts` を削除
19. （オーナー確認2で「ポリシーに追記」になった場合）`fit-connect/src/app/(legal)/privacy/page.tsx` に、同期の状況（データが最後に届いた日）を担当トレーナーに表示する旨の1文を足す（文案はオーナーが確認）

#### 統合（マネージャー）
1. ui-ux-pro-max を実行し、結果を渡して UI レーンを委託
2. 「検証」の節の手順 → chrome-web-qa
3. 「リリース順序とロールバック」の順に進める
4. `IMPLEMENTATION_TASKS.md` を更新: 9.1 は MVP に入ったサブ項目（体重急変・記録途絶・1-7 の分離・Web のバッジ）に x を付け、睡眠悪化・カロリー超過・閾値のトレーナー設定・ディスパッチャ経由の push は未完了のサブ項目として残す。9.3 は触らない
5. lessons に追記: SQL の cron と HTTP の cron で失敗の見え方が違うこと、睡眠 upsert と set_updated_at への依存（一括 UPDATE の注意）、兼務アカウントの痕跡は sender_type / receiver_type で分けること

### PR2（9.2）

#### レーンA: Supabase
1. `supabase/migrations/20260922200000_triage_unreplied.sql`（番号は実装時に変更。他セッションの `20260922000000` より後ろに並べるため）: `get_unreplied_clients_for_trainer()` を契約どおりに作る。`SET search_path = ''`、REVOKE（PUBLIC・anon）、GRANT authenticated、COMMENT
2. `supabase/tests/triage_unreplied_test.sql`
   - (a) トレーナーの最後の送信より後にタグ無しが2件 → 1行（unreplied_since は古い方、count は2）
   - (b) タグ付きしか無い → 0行 / `tags` が NULL → タグ無しとして数える
   - (c) トレーナーが返信した → 0行
   - (d) 最新の未返信が7日より前 → 0行
   - (e) 他のトレーナー宛て / 担当が替わった / clients に無い顧客のメッセージ → 0行
   - (f) トレーナー B が呼んでも A の顧客は出ない
   - (g) 顧客本人が呼ぶと0行
   - (h-1)(h-2) anon はクレーム無し・クレーム付きのどちらでも EXECUTE を拒否
   - (i) 自分宛て（sender = receiver）は除かれる
3. （オーナー確認4で「入れる」になった場合）`triage_actions` の migration と RLS テスト

#### レーンB: Edge Function
- 変更しない

#### レーンC: Web
1. `fit-connect/src/types/triage.ts`: `UnrepliedClient` / `TriageRowModel`
2. `fit-connect/src/lib/supabase/getUnrepliedClients.ts`
3. `fit-connect/src/lib/triage/triageScore.ts` と `.test.ts`: 上限（72時間・14日）、重み、同点のときの並び
4. `fit-connect/src/lib/triage/buildTriageRows.ts` を広げてテストを足す: 未返信だけの顧客を合流させ、スコア順に並べる。バッジ用の顧客 ID 集合に未返信を合わせる
5. `fit-connect/src/lib/supabase/getTriageBadgeCount.ts`: 未返信の顧客を合わせた数にする
6. `TriageRow.tsx`: 未返信のチップと「返信する」（未返信の時間は表示時に計算）
7. `TriageSection.tsx`: 3つを並列に取り、部分的な失敗をセクション内で出す。未返信の定義のヘルプ
8. （オーナー確認4で「入れる」になった場合）`fit-connect/src/app/api/triage-actions/route.ts` とそのテスト、「返信不要にする」ボタン

#### 統合（マネージャー）
- PR1 と同じ手順（リリースは RPC の db push → Web）。`IMPLEMENTATION_TASKS.md` の 9.2 を更新

## 検証
1. **ローカル**
   - worktree のルートで `supabase db reset`。Docker のスタックは全 worktree で共有しているので、他のセッションとタイミングを合わせる
   - `docker exec -i supabase_db_fit-connect psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/tests/<file>.sql` で全テスト（既存8本 → PR1 で11本、PR2 で12本（5.6 の権限テストが加わったため実際は PR1 後 12本・PR2 後 13本））
   - 検知のテストは冒頭で alerts と runs を消すので、QA のための手動実行と順番を気にしなくてよい
2. **テストの判別力**（わざと誤った実装に差し替えて落ちることを見てから戻す）
   - JST の範囲比較を UTC の日付に変える → 境界ケースが落ちる
   - ポリシーから「現担当」の EXISTS を外す → RLS (c) が落ちる
   - `TO authenticated` を外す → (e-2) が落ちる
   - ヒステリシスを外す → (b) が落ちる
   - 登録日の下限を外す → (d) の新規顧客のケースが落ちる
   - open 中の昇格で surfaced_on を更新しない → (f) が落ちる
   - sender_type / receiver_type の絞り込みを外す → snapshot の兼務ケースが落ちる
   - 未返信のタグ除外を外す → PR2 (b) が落ちる
3. `pg_get_expr(polqual, polrelid)` で、ポリシーの列がどこに解決されたかを目で確かめる
4. ローカルで `EXPLAIN` を取り、snapshot と未返信の RPC（トレーナーのロールで実行）が既存の複合索引を使っていることを確かめる
5. **Web**: `pnpm test` → `pnpm lint` → `pnpm exec tsc --noEmit` → `pnpm build`。next build は dev サーバーを止めてから（起動中は禁止）。`.next` を他の worktree と共有しない
6. **deno test**: 変更は delete-account のコメントだけなので対象外。`_shared/` に差分が無いことを diff で確かめる
7. **chrome-web-qa**: トレーナーのログインが要るので、オーナーが実施する可能性がある
   - 準備: seed の顧客に「登録日より後に7日で3%以上増えた体重」と「古い最終到着」を SQL で入れ、今日の対象日で `run_client_alert_detection` を実行
   - 確認: 表示、disclosure、対応済みと元に戻す、バッジの増減、展開、0件・未実行・停止・取得失敗の表示、対象外の人数、キーボードだけでの操作
   - PR2: 返信する、未返信の復活、スコア順、部分失敗
8. **リモート**: 「リリース順序とロールバック」の手順（db push → Advisors → dry run とバックテスト → 直前の dry run → 手動実行と有効化 → 翌朝の確認 → main リリース）
9. **Mobile** は変更しないので ios-simulator-qa は不要

## 既知のリスク・拡張候補
- **閾値に統計的な根拠が無い**。アクティブな顧客は HealthKit 連携の2名で、期間も約2週間。有効化前のバックテストで新規件数を見て、運用を始めたら `alert_detection_runs` の stats で見直す
- **「記録・同期なし」には、計測はしているがアプリを開かない顧客も入る**（仕様。文言で明示する）。体重だけ連携している顧客は、アプリを開いても新しい計測が無ければこちらに入る。アプリの未起動と未計測を区別するには Mobile の heartbeat（サーバー時刻で書く RPC と専用テーブル）が要り、Mobile のリリースを伴うので次の Mobile リリース（フェーズ10 など）を勧める
- **睡眠 upsert と set_updated_at への依存**: Mobile で upsert を最適化すると、睡眠連携だけの顧客で「記録・同期なし」の誤検知が増える。weight / sleep を一括 UPDATE する migration を流すと全員が「同期あり」に見え、休眠中の顧客が監視対象に戻って「記録なし」が大量に出る（手順書と lessons に注意を書く）
- **iOS で HealthKit の読み取りを拒否していると**、同期は成功しているのにデータが空に見え「記録なし」が出る。Android では Health Connect の体重の権限宣言が食い違っている疑いもある。文言は事実だけにし、Android は別タスクで実機確認
- **06:00 時点の判定**なので、朝に同期した顧客の「記録・同期なし」は翌朝まで残る。登録から時間がたって連携した顧客では、30日分の一括取り込みで過去2週間の体重の変化が後から検知される。一方、登録から約10日間は体重の急変を検知しない
- **旧「N日間記録なし」を撤去する**ので、アプリ未登録の旧顧客と2週間を過ぎた記録開始前の顧客は個別には出なくなる（人数だけ。オーナー確認1）
- **対応済みにしたアラートは、トーストが消えると見返すことも戻すこともできない**（DB には残る。履歴の画面は拡張）
- **トレーナー向け push を後で有効にしても**、通知の節の前提4点を直すまでは届かないか、兼務アカウントでは顧客用のスマホに届く。VAPID の設定前に sendNotification を呼ぶと dedup キーを使い切る
- **cron 失敗の運営向け通知が無い**（判断7-3 を後回しにする場合）。検知の遅延・停止はトレーナーの画面にしか出ない
- **未返信からタグ付きメッセージを一律に除く**ので、ワークアウト達成の「💬 感想」や記録に添えた質問は拾えない。将来は「タグ以外の本文があるもの」を含める案
- **purpose は顧客本人が書き換えられる**ので、diet に変えると減少の重要度が1段下がる（検知は残る）
- **消し込みを入れない場合**（推奨案）、返信不要のメッセージが最長7日並ぶ
- **新着の未返信はリアルタイムにはバッジに出ない**（次の画面遷移・タブ復帰・返信送信の後に反映）。見出しに「未返信は H:mm 時点」の取得時刻を出す
- **既存の DEFINER 関数に穴がある**: `calculate_achievement_rate` / `check_goal_achievement` / `issue_recurring_tickets` は anon から実行でき search_path も未固定（範囲外。別タスクを推奨）
- **8.4 と重なる**: migration の番号、手順書、000400 の適用順（db push で一緒に当たる）。ローカルの Supabase スタックとメインのチェックアウトも共有。コミット前に lock ファイルや .g.dart が develop から漏れていないか比べる
- **既存の定義のずれは残る**: 期限間近チケット（14日と7日）、アクティブ（7日と30日）、`getClientListMetrics` の UTC 日付。KPI と「今日の対応」の数字が合わないことがある
- **監視対象が今は1名**なので、見込み件数は有効化の直前に dry run で取り直す
- **拡張の優先順（提案）**: 1. トレーナー向け push（と cron 失敗監視）2. 9.2 の消し込み 3. alert_settings（ミュート・閾値 UI・目的の上書き）4. Mobile heartbeat 5. ③睡眠悪化 6. 追加の実行回 7. ⑤期日×未達（initial_weight の入力導線と達成率の定義の統一が前提）8. ④カロリー超過（目標カロリーは alert_settings に置く）9. 1-B の即時検知

## オーナー決定（2026-09-13。4点とも推奨案を採用）
1. 記録開始前・アプリ未登録の顧客の扱い（旧「N日間記録なし」の撤去）→ **登録から2週間以内の未開始だけ出し、それ以外は理由別の人数だけ**
2. データが届いた日をトレーナーに見せることとプライバシーポリシー → **日付だけ見せ（時刻は持たない）、プライバシーポリシーに1文足す**（文案は PR1 のレビューでオーナーが確認）
3. 判断7-3 の cron 失敗監視の時期 → **トレーナー向け push の配線と一緒に作る**（それまではダッシュボードの検知状態表示と、手順書の確認 SQL を週1回流すことで代える）
4. 9.2 の MVP に消し込みを入れるか → **入れない（拡張1）**。`triage_actions` は PR2 では作らない
5. （2026-09-22 追加）プライバシーポリシーの変更に合わせ、**最終更新日と同意バージョンを 2026-09-22 に上げる**（Web と Mobile の定数を同時に変更。既存の顧客にはアプリ更新後に同意画面が再表示される）
- 前版の確認事項「減量目的の顧客の減少」は、推奨案（検知して medium に下げる）を既定として採った（設計判断10）。異なる扱いにしたい場合はレビューで指摘してもらえば、定数1箇所の変更で済む

## 見送った指摘
- run に締め時刻（p_now）を渡せるようにする案: 採らない。締め時刻の境界は evaluate(p_as_of) で検証でき、本実行に時刻を差し込める口は運用で誤用しうる
- weight_change の payload に pre_join を持たせる案: 採らない。登録日より前の計測を使わない方が単純で、画面の説明も要らない
- ~~兼務対策で既読を「相手が今の担当」のメッセージに限る案: 採らない~~ → **実装レビューで採用に変更（2026-09-13）**。見送りの根拠は「既読は顧客本人の操作」だったが、messages の RLS は送信者が read_at を書くことを防いでいない（担当関係の無い第三者が既読を偽造して R を動かせる）。RLS 自体の修正は別タスク
- `client_record_days` を snapshot の内部関数として残す案: 関数ごと無くした。Phase 9 は表ごとの最大値で足り、記録日の集合はどこも使わない
- escalated_on / high_since 列を足す案: 採らない。open 中の昇格で `surfaced_on` を更新すれば、並び順も後の push の対象選びも足りる
- alert_detection_runs のシーケンスに REVOKE を足す案: id を uuid にしてシーケンス自体を作らないことで代えた
