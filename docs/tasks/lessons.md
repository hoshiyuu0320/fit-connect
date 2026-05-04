# Lessons - 過去の失敗と学び

## 記録ルール

- バグを解決したら、ここにパターンと対策を追記する
- 設計上の判断ミスや整合性の注意点も記録する
- 同じ失敗を繰り返さないための知見をまとめる

## 日付比較のタイムゾーン問題

- **発生箇所**: GoalAchievementChart（目標達成率推移グラフ）
- **症状**: 体重進捗率が実際の記録と連動せず、古い値のまま固定される
- **原因**: `new Date(record.recorded_at)` と date-fns の interval（ローカルタイム）を直接比較すると、JST(UTC+9) のレコードが期間境界で正しく振り分けられない
- **対策**: Supabase の `recorded_at` をフィルタする際は `recorded_at.split('T')[0]` の文字列比較を使う（report/page.tsx と同じパターン）。`new Date()` 同士の比較は避ける

## SleepRecord 設計時の知見（タスク 1.3）

- **recorded_date は DATE 型 + String 表現**: Mobile側でも `String "YYYY-MM-DD"` で扱い、`DateTime` 比較は禁止。`jstDateKey()` ヘルパーで一貫処理
- **UPSERT 戦略**: 手動評価と HealthKit 客観データを混在させる場合、ペイロードに**含めないフィールドを保持する** UPSERT が必要。Supabase の `.upsert(... onConflict: '...')` で実現
- **Supabase Trigger関数名**: 既存トリガは `update_updated_at_column()`（`set_updated_at` ではない）。新規テーブルでも踏襲すること
- **Sleep カラーは AppColorsExtension に追加**: `sleepStageDeep/Light/Rem/Awake` をライト/ダーク両preset対応。`AppColors` 直定数より ThemeExtension パターン優先

## エラー状態のUX原則（タスク 1.3）

- カードの error state は **ヘッダー構造を保持**してカードらしさを残す（テキスト1行のみは視認性が低い）
- **リトライ導線**を必ず提供（該当 provider を `ref.invalidate()`）
- 関連: `lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart` `_ErrorBody`

## モノレポ移行（2026-04-26 完了）

- **背景**: Web (`fit-connect`) と Mobile (`fit-connect-mobile`) を独立リポジトリで運用していたが、同一 Supabase 共有・1セッションで両方を統括したい等の理由でモノレポ化
- **戦略**: `git subtree add --prefix=fit-connect-mobile mobile-origin develop/1.0.0`（フル履歴保持）→ Web側ファイルを `fit-connect/` サブディレクトリへ `git mv` → 親レベル CLAUDE.md/.claude/docs を統合 → main を develop で上書き force push
- **トラップ**:
  - **subtree 取り込み元は default branch を確認**: mobile は `main` ではなく `develop/1.0.0` が事実上の運用ブランチだった（main は古い）。Web も同様で main は Initial commit のみ、develop に122コミット
  - **Vercel の Production Branch と実際のデプロイ元の不一致**: Production Branch は main 設定だが、実際の本番 deploy は Mar 14 の develop スナップショット凍結（main へ push されてなかった）。移行を機にこの歪みを解消
  - **Default branch を別運用ブランチに変更してあると、リポジトリ整理時にそれが削除できない**: GitHub の default branch を main に切り替える操作が必要（develop 削除前）
  - **Supabase の `_remote_schema.sql` は完全スキーマダンプ**: 両プロジェクト両方にあるからといって両方を採用してはいけない（時系列で新しい方を採用、古い方は破棄）
- **意図せず混入したもの** (.gitignore 追加候補): `.superpowers/brainstorm/*/.server.pid` 系、`.claude/skills/*/scripts/__pycache__/*.pyc`
- **移行詳細手順書**: `docs/tasks/2026-04-26-monorepo-migration.md`
- **未完のフォローアップ**: `docs/tasks/2026-04-26-monorepo-migration-followups.md`

## バックグラウンド同期の戦略選定（タスク 1.4）

- **`workmanager` を見送った理由**:
  - iOS の `BGAppRefreshTask` / `BGProcessingTask` は OS が裁量で実行するため、最短でも数時間に1回・最悪は数日に1回しか起動しない（ヘルスケアの即時性とミスマッチ）
  - 両プラットフォーム共通の native 設定（`AppDelegate.swift` 修正、`MainActivity.kt` 修正、トップレベル callback の dispatch 制約）が必要で、リグレッション影響範囲が大きい
  - 体重・睡眠は1日1回〜数回程度しか変動しないため、フォアグラウンド復帰時の同期で十分鮮度を保てる
- **採用した戦略**: `Timer.periodic(60min)` + アプリ resume 時 `lastSyncAt > 1h` で再同期。両者とも `_AuthLoadingScreenState` に集約 (`lib/app.dart`)
- **冪等性の確保**: `_isResumeSyncing` フラグで resume 経路の二重起動を防止。`_sync()` 自体は SharedPreferences の status (idle/syncing/success/error) で進行中を可視化するが、Riverpod レベルの mutex は省略（同期内部処理は body の異常系 try/catch で完結する設計）
- **リトライポリシー**: `_runWithRetry()` で `_syncWeight` / `_syncSleep` 各々独立に最大3回（初回 + 2リトライ、1s/2s 指数バックオフ）。体重と睡眠の片方失敗でも他方は完了させ、`lastSyncAt` は両方成功時のみ更新
- **エラー通知**: `flutter_local_notifications` で固定 ID=9001（連続失敗時に通知トレイが膨張しない）、メッセージは120字で省略
- **iOS/Android 以外（macOS/Web）のガード**: `health_sync_provider` 側で `kIsWeb || (!iOS && !android)` を判定し `showSyncErrorNotification` をスキップ。サービス内部の二重ガードは省略

## AI Meal Estimation Stage 1（タスク 2.1 + 2.2、2026-05-03 完了）

### Supabase Database Webhook の payload に jsonb カラムが含まれない罠

- **症状**: `messages.metadata jsonb` を追加して Edge Function (`parse-message-tags`) でそれを参照しても、webhook payload では `metadata = undefined` になり meal_record が NULL PFC で作られた
- **原因**: Database Webhooks の column filter のデフォルト挙動が新規追加カラムを自動で含めない（プロジェクト初期化時の filter config がレガシー）
- **対策**: webhook handler 内で `record.id` を使って `messages` テーブルから `metadata` を **再フェッチ** する。webhook payload は trigger 通知だと割り切り、必要なフィールドは SELECT で取り直す方針で固定
- **関連**: `supabase/functions/parse-message-tags/index.ts`

### `supabase functions_client` は非 2xx で例外を throw する

- **症状**: Edge Function が 403 や 429 を返したとき、Mobile 側のエラーハンドリングが `network` エラーに collapse して原因が特定できなくなる
- **原因**: `functions_client 2.5.0` の `invoke()` は `Response { status, data }` を返すのではなく `FunctionException` を **throw** する。`response.status` チェックでは到達不能
- **対策**: `try { await client.functions.invoke(...) } on FunctionException catch (e) { /* e.status, e.details を読む */ }` パターンを使う。`e.details` に Edge Function 側で `JSON.stringify` した body が入っている
- **関連**: `lib/features/meal_records/data/meal_estimation_api.dart`

### Claude Haiku 4.5 が JSON をコードフェンスで包むことがある

- **症状**: `JSON.parse(response.content[0].text)` が `Unexpected token \`` で失敗する
- **原因**: モデルが ` ```json\n{...}\n``` ` 形式で返すケースがある（プロンプトで明示しても発生）
- **対策**: parse 前に `extractJson()` ヘルパーで先頭末尾の ` ``` ` / ` ```json ` を strip する。正規表現で `^```(?:json)?\s*\n?` と `\n?\s*```$` を順次除去
- **関連**: `supabase/functions/estimate-meal-nutrition/index.ts`

### Anthropic API は credit balance が 0 だと API キー有効でも 400 を返す

- **症状**: HTTP 400 `Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.`
- **対策**: Anthropic Console の Plans & Billing で **Auto Reload** を設定（残高が閾値を下回ったら自動課金）。本番運用では必須
- **副次**: workspace を分けるなら API キーも別ワークスペースで発行し、Supabase Secrets と紐付ける

### Riverpod AsyncValue ゲート系 UI のフラッシュ問題

- **症状**: `aiFeaturesEnabledProvider` (AsyncValue) で「pro なら AI 呼出 / free なら既存挙動」を分岐したい場合、未 resolve のまま loading フェーズに切り替えてしまうと free プランで一瞬だけ「AI推定中…」が出るフラッシュが発生する
- **試行錯誤**:
  1. ❌ 同期 `ref.read()` で `cached.hasValue && cached.value == false` 早期 return → provider が未 resolve だと素通りしてフラッシュ発生
  2. ❌ `initState` で `ref.read(provider)` 先行フェッチ → タップが速いと resolve 前に await 開始でフラッシュ発生
  3. ✅ **loading フェーズへの遷移は `aiEnabled == true` 確定後**にする。input フェーズのまま `await ref.read(provider.future)` で resolve を待ち、`true` のときだけ `setState(_phase = loading)`
- **教訓**: AsyncValue ゲートで分岐するときは、**ゲート結果が確定するまで UI 状態を変えない**。`AsyncValue.when` で UI を直接組むパターンが使えない場合（命令的フロー）も同じ原則を守る
- **関連**: `lib/features/messages/presentation/widgets/structured_tag_form.dart` `_handleInsert`

### Subscription gate を B2B2C で組むときの認証チェーン

- **背景**: クライアントには課金 UI を一切持たせず、トレーナーの `subscription_plan` を継承するモデル（FIT-CONNECT のビジネス要件）
- **チェーン**: `auth.uid()` → `clients.user_id` → `clients.trainer_id` → `trainers.subscription_plan`
- **RLS の罠**: クライアントが自分のトレーナーの subscription_plan を SELECT できる必要がある。FIT-CONNECT の `trainers_select_all USING (true)` ポリシーがすでにこれを許可していたので追加対応不要だったが、新規プロジェクトでは要注意
- **関連**: `lib/features/subscription/providers/ai_features_enabled_provider.dart`

### Anthropic 構造化出力の totals 不整合

- **症状**: Claude に `foods[]` と `totals` を同時に返させると、`totals.calories` が `sum(foods[].calories)` と一致しないケースがある（モデルの算術ミス）
- **対策**: validator で `foods` から totals を **再計算して上書き**。Claude の totals は捨てる（食品レベルの推定だけ信用する）
- **関連**: `supabase/functions/estimate-meal-nutrition/index.ts`

### 残タスク（フェーズ 2 続き）

- **Stage 2**: 画像からのカロリー推定（タスク 2.3）
- **Stage 3**: メッセージタグからの自動推定（タスク 2.4 一部）
- **Stage 4**: 食事アプリスクショ画像分析（タスク 2.5）
- **インフラ**: Stripe 連携で `trainers.subscription_plan` を自動更新（フェーズ 7 想定）
