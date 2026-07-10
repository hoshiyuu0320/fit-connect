# FIT-CONNECT 改善施策カタログ（課題→解決策 詳細設計）

> 作成日: 2026-07-08
> 経緯: コードベース全体調査（Web / Mobile / Supabase）で洗い出した8カテゴリの課題に対し、カテゴリごとに解決機能・施策を詳細設計したもの。最後に全カテゴリ横断のレビュー（考慮漏れ・依存関係・優先順位）を付す。
> 関連: `docs/tasks/2026-04-29-feature-backlog.md`（元ネタの雑メモ）、`docs/tasks/IMPLEMENTATION_TASKS.md`（実装タスク管理）

## 目次

1. [カテゴリ1: トレーナーの介入を促す仕組み](#カテゴリ1-トレーナーの介入を促す仕組み--機能設計)
2. [カテゴリ2: 顧客の継続率（リテンション）を支える仕組み](#カテゴリ2-顧客の継続率リテンションを支える仕組み--機能設計)
3. [カテゴリ3: 収益化・ビジネス基盤](#カテゴリ3-収益化ビジネス基盤--機能設計)
4. [カテゴリ4: スケジュール・予約](#カテゴリ4-スケジュール予約--機能設計)
5. [カテゴリ5: 記録・データの拡充](#カテゴリ5-記録データの拡充--機能設計)
6. [カテゴリ6: コミュニケーション](#カテゴリ6-コミュニケーション--機能設計)
7. [カテゴリ7: セキュリティ・技術基盤の負債](#カテゴリ7-セキュリティ技術基盤の負債--機能設計)
8. [カテゴリ8: グロース・差別化](#8-グロース差別化--機能設計)
9. [横断レビュー: 考慮漏れ・依存関係・優先順位](#横断レビュー-考慮漏れ依存関係優先順位)

---

# カテゴリ1: トレーナーの介入を促す仕組み — 機能設計

> 前提となる実装済み資産（コード確認済み）:
> - Web ダッシュボードに簡易アラートが既存: `fit-connect/src/app/(user_console)/dashboard/page.tsx`(L224-257) が「N日間記録なし / チケット期限 / プラン未実施」の3種をクライアントサイドで都度計算し `AlertList.tsx` / `AlertItem.tsx` に表示。**サーバーサイド検知・永続化・通知は無い**
> - トレーナー向け Web Push 送信 API が既存: `fit-connect/src/app/api/push-notify/route.ts`（web-push + VAPID、`x-api-key` 認証、subscriptions 配列を受けて送信）→ Edge Function からの通知送出口として再利用可能
> - 顧客向け FCM 送信の実装が既存: `supabase/functions/parse-message-tags/index.ts`(L456-583) が FCM HTTP v1 で `clients.fcm_token` / `trainers.fcm_token` へ直接送信（※ `fcm_token` カラムの migration が `supabase/migrations/` に見当たらず、client_notes 同様の migration 欠落。要先行修復）
> - AI 呼び出しパターンが既存: `supabase/functions/estimate-meal-nutrition/index.ts`（Anthropic API 直叩き、haiku/sonnet 使い分け、`ai_estimation_logs` で 50回/client/日の rate limit、Pro プラン判定）→ AI 系新機能はこの雛形を流用

---

## 課題1: 異常検知アラートがない

### 1-A. サーバーサイド異常検知エンジン（日次バッチ + alerts テーブル）【推奨】
- **解決する課題**: 体重急増減・記録途絶・睡眠悪化・カロリー超過・期日接近×未達をサーバーサイドで毎日検知し、永続化されたアラートとしてトレーナーに自動通知する。現状のダッシュボード都度計算（開いた時しか気づけない）を「向こうから知らせてくる」仕組みに転換。
- **ユーザーストーリー**:
  - トレーナーとして、顧客の体重が1週間で3%以上変動したら朝の通知で知りたい。アプリを開かなくても異変に気づきたい。
  - トレーナーとして、対応済みのアラートは消し込み、未対応だけが残るリストで漏れなく介入したい。
  - トレーナーとして、顧客ごと・アラート種別ごとに閾値やON/OFFを調整したい（減量中の顧客の体重減少は正常なので）。
- **機能仕様**:
  - Web: ダッシュボードの `AlertList` を alerts テーブル駆動に置換。各アラートに「対応済み」「ミュート（この顧客のこの種別を30日停止）」「メッセージへ」アクションを追加。`/settings` に閾値設定セクション新設。
  - 検知ルール（初期セット）: ①体重急変: 直近7日平均が前7日平均比 ±3% or ±2kg ②記録途絶: 全記録種別+メッセージの最終日時から3日超 ③睡眠悪化: 直近7日平均睡眠時間が前週比 -1h 超 or 起床評価平均 < 1.5 ④カロリー超過: 目標kcal超過が3日連続（要 `clients.target_calories_kcal` 追加、未設定なら Mifflin-St Jeor 推定） ⑤期日接近×未達: `goal_deadline` まで30日以内かつ `calculate_achievement_rate`（既存RPC） < 50%
  - Mobile: 変更なし（アラートはトレーナー専用）。
- **データモデル**:
  - 新テーブル `alerts`: `id uuid PK, trainer_id uuid FK→trainers, client_id uuid FK→clients, alert_type text, severity text('high'/'medium'/'low'), title text, body text, payload jsonb(検知値・閾値・比較期間), status text('open'/'acknowledged'/'muted'), detected_at timestamptz, resolved_at timestamptz, created_at`。部分ユニーク index `(client_id, alert_type) WHERE status='open'`（同一アラートの重複生成防止、再検知時は payload 更新）。
  - 新テーブル `alert_settings`: `trainer_id, client_id(NULL=全体デフォルト), alert_type, enabled bool, threshold jsonb, PRIMARY KEY(trainer_id, client_id, alert_type)`。
  - `clients` に `target_calories_kcal int` 追加（カロリー超過検知用。Web クライアント編集フォームに入力欄追加）。
  - RLS: alerts / alert_settings とも `trainer_id = auth.uid()` で SELECT/UPDATE、INSERT は service role のみ。
- **バックエンド**: 新 Edge Function `detect-client-anomalies`（cron 毎朝6:00 JST。auto-skip-workouts と同じく Supabase Dashboard 側 cron 設定）。weight_records / meal_records / sleep_records / messages を集計し alerts へ upsert。high 新規発生分のみ通知。閾値は alert_settings をマージ。
- **通知設計**: トレーナーへ。high 発生時は即時（cron 実行時）、medium/low はダッシュボードバッジのみ。経路は `push_subscriptions` を読み `/api/push-notify` を `x-api-key` 付きで呼ぶ（既存 web-push 基盤流用）。通知文例:「⚠️ 田中様: 体重が7日で+2.4kg。タップして確認」→ URL `/clients/{id}?tab=weight`。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/dashboard/page.tsx`(alertList 生成 L224-257 を getAlerts.ts 呼び出しに置換)、`fit-connect/src/components/dashboard/AlertItem.tsx`(アクション追加)、`fit-connect/src/app/api/push-notify/route.ts`、既存 RPC `calculate_achievement_rate`、`supabase/functions/auto-skip-workouts/`(cron Function の雛形)。
- **フェーズ分け**: MVP=ルール①②のみ+alerts テーブル+ダッシュボード表示+Push → 拡張1=ルール③④⑤+alert_settings(閾値UI) → 拡張2=ミュート/顧客別設定/アラート履歴画面。
- **規模感**: M（MVP は3-4日、フル1週強）
- **リスク・考慮事項**: 誤検知が多いと通知が無視される（狼少年化）→ デフォルト閾値は保守的に、種別ごとの日次上限（トレーナーあたり10件等）。減量目的の顧客は体重減少を異常扱いしない（`clients.purpose` と `target_weight` の方向で判定）。健康データの自動判定であり医療判断ではない旨を UI に明記。`fcm_token`・`client_notes` の migration 欠落と同じ轍を踏まないよう必ず migration ファイルをコミット。

### 1-B. リアルタイム即時検知（DB webhook 型）【1-Aの拡張として併用推奨】
- **解決する課題**: 日次バッチではラグが出る「記録された瞬間に分かる異常」（前回比で大きく飛んだ体重、極端な睡眠時間）を即時検知する。
- **ユーザーストーリー**: トレーナーとして、顧客が朝計測した体重が前回から2kg跳ねていたら、その日のセッション前に知りたい。
- **機能仕様**: weight_records / sleep_records の INSERT を webhook で受け、単一レコード検査（前回値との差分、絶対値レンジ）。異常なら alerts へ upsert + 即時 Push。バッチ(1-A)と検知種別を分担（トレンド系=バッチ、スパイク系=即時）。
- **データモデル**: 1-A の alerts / alert_settings を共用。追加テーブル不要。
- **バックエンド**: 新 Edge Function `on-record-insert`（または parse-message-tags 同様の Database Webhook 設定を weight_records / sleep_records に追加）。
- **通知設計**: 1-A と同一経路。即時性が価値なので high のみ Push。
- **既存コードとの接続点**: `supabase/functions/parse-message-tags/index.ts`（messages webhook の設定パターンをそのまま踏襲）。HealthKit 同期 (`fit-connect-mobile/lib/.../health_repository.dart`) 由来の一括 INSERT で連発しないよう `source='healthkit'` の過去日データはスキップ。
- **フェーズ分け**: 1-A 安定後に追加。
- **規模感**: S（1-A のロジックを関数化していれば1日）
- **リスク・考慮事項**: HealthKit の遡及同期・重複排除との相互作用。webhook 失敗時のリトライは Supabase 側仕様に依存（バッチが翌朝拾うので致命的でない）。

### 1-C. 既存ダッシュボードのクライアントサイド計算の拡張のみ【非推奨・比較用】
- **解決する課題**: 同課題を最小工数で。検知種別（体重急変・睡眠悪化）を dashboard/page.tsx の都度計算に追加するだけ。
- **ユーザーストーリー**: トレーナーとして、ダッシュボードを開いたときに異変一覧を見たい。
- **機能仕様**: `src/lib/supabase/` にクエリ関数を2-3本追加し alertList 生成に合流。
- **データモデル**: 変更なし。
- **バックエンド**: 変更なし。
- **通知設計**: なし（ここが致命的欠点。開かないと気づけず「介入を促す」という課題の本質を解決しない）。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/dashboard/page.tsx`。
- **フェーズ分け**: 単発。
- **規模感**: S
- **リスク・考慮事項**: 消し込み・既読管理ができず件数が増えると形骸化。1-A への繋ぎとしてのみ価値あり。

---

## 課題2: 「今日対応すべきクライアント」トリアージビューがない

### 2-A. デイリートリアージ（優先度スコア付き対応リスト）【推奨】
- **解決する課題**: 未返信・記録途絶・アラート・期日接近を横断した「今日誰に何をすべきか」を1つの優先度付きリストに統合し、ダッシュボードを"見る場所"から"仕事を始める場所"に変える。
- **ユーザーストーリー**:
  - トレーナーとして、朝アプリを開いたら「今日対応すべき顧客トップN」が理由付きで並んでいて、上から順に返信・声かけすれば漏れがない状態にしたい。
  - トレーナーとして、対応したらチェックして消し込み、夕方に残件を確認したい。
- **機能仕様**:
  - Web: ダッシュボード最上部に「今日の対応」セクション新設（既存 `TodaysSchedule` の上）。各行 = 顧客アバター + 理由バッジ（複数可: 「未返信18h」「記録3日なし」「体重+2kg」「期日まで12日」）+ スコア順ソート + アクションボタン（「返信する」→ `/message?client={id}`、「記録を見る」→ `/clients/{id}`、「AI返信候補」→ 3-A 連携、「完了」チェック）。全件ビューは `/dashboard` 内アコーディオン展開で十分（新ページ不要）。
  - スコアリング（初期式）: `未返信時間×2 + open_alerts(high=30/medium=10) + 記録途絶日数×5 + 期日30日以内かつ達成率50%未満なら+20`。
- **データモデル**:
  - 新テーブル `triage_actions`: `id, trainer_id, client_id, action_date date, status text('done'/'snoozed'), created_at`。ユニーク `(trainer_id, client_id, action_date)`。当日消し込み管理用（翌日は再評価でリセット）。
  - RLS: `trainer_id = auth.uid()`。
- **バックエンド**: 新 RPC `get_daily_triage(p_trainer_id uuid)`（SECURITY DEFINER）: 既存 RPC `get_unread_counts_for_trainer` / `get_last_messages_for_trainer` のロジックを内包し、alerts(1-A)・最終記録日時・`calculate_achievement_rate` を JOIN してスコア計算済みの行セットを返す。1-A 未実装でも動くよう alerts JOIN は LEFT。
- **通知設計**: 任意拡張として、毎朝8:00 に「今日の対応: 5名（うち緊急2名）」の Web Push を1通（`detect-client-anomalies` cron の末尾で送出、通知過多を避けるためサマリー1通のみ）。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/dashboard/page.tsx`、`fit-connect/src/components/dashboard/`（`AlertList` の上位互換として新コンポーネント `TriageList.tsx`）、既存 RPC `get_unread_counts_for_trainer` / `get_last_messages_for_trainer` / `calculate_achievement_rate`、`/message` ページのクエリパラメータ受け（顧客選択の deep link 対応要確認）。
- **フェーズ分け**: MVP=RPC+リスト表示+返信導線（消し込みなし） → 拡張1=triage_actions で完了/スヌーズ → 拡張2=朝のサマリーPush、AI返信候補ボタン統合。
- **規模感**: M（MVP 2-3日）
- **リスク・考慮事項**: スコア式はチューニング前提（重みを RPC 内定数でなく設定化するか初期から検討）。顧客数が多いトレーナーで RPC が重くなる可能性 → 最終記録日時は集計ビュー or インデックス設計を先に。1-A と同時設計すると alerts テーブルを二重に作らずに済むため、**1-A → 2-A の順で連続実装が効率的**。

### 2-B. クライアント一覧への「要対応」フィルタ・ソート追加【軽量代替】
- **解決する課題**: 同課題を既存 `/clients` ページの拡張で解決。専用ビューを作らず「未返信順」「記録途絶順」ソートと「要対応のみ」フィルタを足す。
- **ユーザーストーリー**: トレーナーとして、顧客一覧を「放置度順」に並べ替えて上から対応したい。
- **機能仕様**: `/clients` の検索/フィルタ UI にソートキー追加。`ClientCard.tsx` に未返信/途絶バッジ表示。
- **データモデル**: 変更なし（2-A の RPC を共用）。
- **バックエンド**: 2-A の `get_daily_triage` を流用。
- **通知設計**: なし。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/clients/page.tsx`、`fit-connect/src/components/clients/ClientCard.tsx`、`src/lib/supabase/searchClients.ts`。
- **フェーズ分け**: 2-A MVP 後の横展開として。
- **規模感**: S
- **リスク・考慮事項**: 単独では「今日やるべきこと」の提示にならない（能動的に一覧を開く必要がある）。2-A の補完として価値。

---

## 課題3: AI返信候補がない

### 3-A. AI返信候補（オンデマンド生成 + 記録コンテキスト注入）【推奨】
- **解決する課題**: トレーナー最大の負荷である返信業務を、顧客の直近記録を踏まえた返信ドラフト3案のワンタップ生成で軽減する。
- **ユーザーストーリー**:
  - トレーナーとして、顧客のメッセージや食事記録に対し「AI候補」を押すと、体重推移や昨日の食事内容を踏まえた返信案が3つ出て、選んで少し直すだけで送信したい。
  - トレーナーとして、AI 候補が自分の口調（絵文字の量、敬語レベル）に寄っていてほしい。
- **機能仕様**:
  - Web `/message`: メッセージ入力欄の上に「✨AI返信候補」ボタン。押下で3案（①短い労い・承認 ②記録データに言及した具体アドバイス ③深掘り質問）をチップ表示 → タップで入力欄に挿入（**必ず編集可能、自動送信はしない**）。生成中はスケルトン表示。再生成ボタン付き。
  - コンテキスト: 対象顧客との直近メッセージ20件 + 直近7日の記録サマリー（体重変化・食事kcal/PFC・運動・睡眠・open alerts）+ 顧客プロフィール（目的/目標体重/期日）+ トレーナー自身の過去返信10件（文体 few-shot）。
  - Pro プラン限定（estimate-meal-nutrition と同一のプラン判定）。
- **データモデル**:
  - 新テーブル `ai_reply_logs`: `id, trainer_id, client_id, context_message_id uuid, suggestions jsonb(3案), adopted_index int NULL, was_edited bool, model text, input_tokens int, output_tokens int, created_at`。採用率の計測が改善の生命線。
  - rate limit は `ai_estimation_logs` の仕組みを汎用化するか、`ai_reply_logs` で独自にカウント（例: 200回/trainer/日）。
  - RLS: `trainer_id = auth.uid()` SELECT のみ、書き込みは Edge Function(service role)。
- **バックエンド**: 新 Edge Function `suggest-reply`: モデルは `claude-haiku-4-5`（速度・コスト重視。estimate-meal-nutrition のモデル切替パターン踏襲）。JSON モードで `{suggestions: [{type, text}]}` を返す。プロンプトに「医療・診断行為をしない」「トレーナーの文体サンプルに寄せる」を固定。
- **通知設計**: 不要。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/message/page.tsx`（入力エリア）、`fit-connect/src/components/message/RecordSidePanel.tsx`（記録コンテキストの取得ロジック共用）、`supabase/functions/estimate-meal-nutrition/index.ts`（認証・プラン判定・rate limit・Anthropic 呼び出しの雛形）、`fit-connect-mobile` 側変更なし。
- **フェーズ分け**: MVP=直近メッセージのみをコンテキストに3案生成+挿入 → 拡張1=記録サマリー注入+文体 few-shot → 拡張2=受信時の自動プリフェッチ（トレーナーが会話を開いた瞬間に裏で生成しておき体感ゼロ秒に）、トリアージ(2-A)行からの直接生成。
- **規模感**: M（MVP 3日、拡張込み1週）
- **リスク・考慮事項**: APIコスト（haiku で1生成 ≈ 数円以下だが自動プリフェッチ導入時は開封率を見て制御）。健康情報を外部 API に送る旨のプライバシーポリシー/利用規約更新（estimate-meal-nutrition で前例あり、トレーナー向け同意で足りるか法務確認）。「AIっぽい返信」を顧客に見抜かれると関係性を毀損 → 自動送信は絶対にしない設計思想を守る。Anthropic API 利用規約上は問題なし（医療診断を返さないガード必須）。

### 3-B. 定型文（クイックリプライ）ライブラリ【非AI・併用可】
- **解決する課題**: AI を使わずに返信負荷を下げる。よく使う返信（「ナイス記録です💪」「水分足りてますか？」）をトレーナーが登録しワンタップ挿入。
- **ユーザーストーリー**: トレーナーとして、毎日打っている定番フレーズを登録してワンタップで挿入したい。
- **機能仕様**: Web `/message` 入力欄横に定型文ピッカー（カテゴリ: 労い/食事/運動/睡眠/その他）。`/settings` で CRUD。
- **データモデル**: 新テーブル `reply_templates`: `id, trainer_id, category text, title text, body text, sort_order int, usage_count int, created_at`。RLS `trainer_id = auth.uid()` 全操作。
- **バックエンド**: 追加不要（Browser client から直接 CRUD、または既存 API Route パターン踏襲）。
- **通知設計**: 不要。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/message/page.tsx`、`/settings` ページ。7-A（カルテテンプレ）とテーブル設計・UI を共通化すると実装が半減。
- **フェーズ分け**: 単発。3-A の UI（チップ挿入）と同じコンポーネントを共用。
- **規模感**: S
- **リスク・考慮事項**: ほぼなし。AI 案の「編集して使う」需要の受け皿としても機能（AI 案を定型文に保存する導線を拡張で）。

---

## 課題4: AI相談機能がない

### 4-A. AI コーチング相談（顧客データコンテキスト付きチャット）【推奨】
- **解決する課題**: 顧客の統計データを踏まえた指導方針を AI に相談できるようにし、経験の浅いトレーナーの意思決定を支援、ベテランの仮説検証を高速化する。
- **ユーザーストーリー**:
  - トレーナーとして、「この顧客、体重が停滞して2週間。データを見てどう介入すべき？」と聞くと、実データ（摂取kcal推移・睡眠・運動頻度）を根拠にした選択肢が返ってきてほしい。
  - トレーナーとして、相談の続きを後日再開したい（会話履歴が残る）。
- **機能仕様**:
  - Web: クライアント詳細 `/clients/[client_id]` に右側ドロワー型の「AI相談」パネル新設（既存7タブは維持、ヘッダーにボタン配置。どのタブを見ながらでも開ける点でタブ追加より優位）。チャット UI、ストリーミング表示、会話履歴一覧、「この相談をカルテに転記」ボタン（client_notes へコピー）。
  - 自動注入コンテキスト: プロフィール・目標・達成率（`calculate_achievement_rate`）・直近30日の体重/食事/運動/睡眠集計・open alerts・最新カルテ5件。トークン節約のため生レコードでなく集計値を渡す。
  - Pro プラン限定。免責文「本機能は情報提供であり医学的助言ではありません」を常時表示。
- **データモデル**:
  - 新テーブル `ai_consultations`: `id, trainer_id, client_id, title text, created_at, updated_at`。
  - 新テーブル `ai_consultation_messages`: `id, consultation_id FK, role text('user'/'assistant'), content text, input_tokens int, output_tokens int, created_at`。
  - RLS: 両テーブル `trainer_id = auth.uid()`（messages は consultation 経由の EXISTS）。書き込みは Edge Function。
- **バックエンド**: 新 Edge Function `ai-consult`（SSE ストリーミング対応）: モデル `claude-sonnet-4-6`（推論品質重視。分量は少ないのでコスト許容）。新 RPC `get_client_stats_summary(p_client_id, p_days)` で30日集計を1クエリ化（4-A 専用でなく 5-A 週次サマリーとも共用設計）。rate limit: 30メッセージ/trainer/日。
- **通知設計**: 不要。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/clients/[client_id]/page.tsx`（ドロワー起点）、`supabase/functions/estimate-meal-nutrition/index.ts`（Anthropic 呼び出し/プラン判定雛形）、`fit-connect/src/app/api/client-notes/route.ts`（カルテ転記）、`fit-connect/src/utils/weightPrediction.ts`（予測値もコンテキストに含めると相談品質向上）。
- **フェーズ分け**: MVP=単発Q&A（履歴なし・非ストリーミング・コンテキスト自動注入） → 拡張1=会話履歴+ストリーミング → 拡張2=カルテ転記、相談から返信ドラフト生成（3-A 連携）、期間指定コンテキスト。
- **規模感**: M〜L（MVP 4日、フル 1.5週）
- **リスク・考慮事項**: **最重要は医療境界**: 摂食障害・急激な体重減少・不眠等が窺えるデータでの相談には「専門医受診を促す」旨をシステムプロンプトで強制。健康データの LLM 送信について顧客側の同意設計（利用規約 + 顧客への周知。estimate-meal-nutrition より広範なデータを送るため要法務確認）。コスト: sonnet はコンテキスト2-3万トークン級になり得るので集計値注入を徹底 + prompt caching 活用。ログの保存期間ポリシー。

---

## 課題5: 週次/月次の自動サマリーレポートがない

### 5-A. 週次自動サマリー生成（スナップショット + AI講評）【推奨】
- **解決する課題**: 手動 CSV/PDF 出力しかない `/report` に、毎週月曜朝、全顧客分の週次サマリー（前週比 + AI 講評）を自動生成して届け、週初の指導計画を数分で立てられるようにする。
- **ユーザーストーリー**:
  - トレーナーとして、月曜の朝に「先週の全顧客ダイジェスト」が届いていて、良かった人/停滞した人を5分で把握したい。
  - トレーナーとして、過去の週次スナップショットを遡って「1ヶ月前と比べてどうか」を確認したい。
- **機能仕様**:
  - Web: `/report` に「週次サマリー」タブ新設。週選択 → 顧客カードのグリッド（体重変化・記録率・平均睡眠・セッション消化・前週比の矢印 + AI講評2-3行）。ダッシュボードにも「先週のサマリーが届いています」カード。個別カード → クライアント詳細へ deep link。既存 PDF 出力機構でサマリーごと出力可能に（拡張）。
  - 生成タイミング: 毎週月曜 5:00 JST（月次は毎月1日）。
- **データモデル**:
  - 新テーブル `report_snapshots`: `id, trainer_id, client_id, period_type text('weekly'/'monthly'), period_start date, period_end date, metrics jsonb(体重start/end/delta, 記録日数/率, 平均kcal・PFC, 運動回数/分, 平均睡眠h, 起床評価avg, セッション実施数, 達成率), ai_comment text NULL, created_at`。ユニーク `(client_id, period_type, period_start)`。
  - RLS: `trainer_id = auth.uid()` SELECT。INSERT は service role。
- **バックエンド**: 新 Edge Function `generate-periodic-summary`（cron 週次/月次）: `get_client_stats_summary` RPC（4-A と共用）で集計 → snapshot INSERT → Pro のみ AI 講評（`claude-haiku-4-5`、1顧客1回・バッチ処理）→ 完了後トレーナーへ通知。Free は数値サマリーのみ（AI 講評なし）で機能差別化。
- **通知設計**: トレーナーへ週1回、月曜朝に Web Push 1通「📊 先週のサマリーが届きました（顧客8名）」→ `/report?tab=weekly`。経路は `/api/push-notify`。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/report/`（既存 KPI/比較テーブル/PDF 出力コンポーネント群を流用）、`fit-connect/src/components/dashboard/`（お知らせカード）、`supabase/functions/auto-skip-workouts/`（cron 雛形）、既存 RPC `calculate_achievement_rate`。
- **フェーズ分け**: MVP=weekly スナップショット生成+`/report` タブ表示（AI講評なし・通知なし） → 拡張1=AI講評+月曜Push → 拡張2=monthly、PDF 出力統合、体重予測（`weightPrediction.ts`）を含めた「今週このままだと」コメント。
- **規模感**: M（MVP 3-4日、フル1週）
- **リスク・考慮事項**: AI講評コスト = 顧客数×週次（haiku で微少。全トレーナー合算でも許容）。データが薄い顧客（記録0件週）の講評は無意味なので閾値未満はスキップ。cron 失敗時の再実行手段（管理用に手動トリガーの HTTP 呼び出しを許可、ユニーク制約で冪等）。

### 5-B. 顧客向け週次サマリー自動配信（メッセージ連携）【拡張オプション】
- **解決する課題**: 同じスナップショットを顧客のモチベーション維持に転用。トレーナーの「週次報告を作って送る」作業をゼロにする。
- **ユーザーストーリー**:
  - 顧客として、週明けに「先週のがんばり」がトレーナーから届くと続けるモチベーションになる。
  - トレーナーとして、自動生成された週次メッセージを一目確認して送信ボタンだけ押したい（勝手に送られたくない）。
- **機能仕様**: 5-A のスナップショットから顧客向け文面（称賛トーン）を生成し、Web `/message` に「下書き」として提示 → トレーナーが確認・編集して送信（**自動送信はデフォルト OFF**。設定で完全自動化も可）。Mobile 側は通常メッセージ + `metadata.type='weekly_summary'` で専用カード表示（拡張、`RecordCard` 系の描画パターン流用）。
- **データモデル**: `report_snapshots` に `client_message_draft text, client_message_sent_at timestamptz` 追加。
- **バックエンド**: `generate-periodic-summary` に文面生成を追加。送信は既存 messages INSERT（parse-message-tags webhook 経由で FCM 通知が既存フローのまま飛ぶ）。
- **通知設計**: 顧客へは既存のメッセージ FCM 通知に相乗り（新規経路不要）。
- **既存コードとの接続点**: `supabase/functions/parse-message-tags/index.ts`（送信時の FCM は既存フローが処理）、`fit-connect/src/app/(user_console)/message/page.tsx`（下書きバナー）、`fit-connect-mobile/lib/features/`（メッセージカード表示）。
- **フェーズ分け**: 5-A 拡張2の後。
- **規模感**: M
- **リスク・考慮事項**: トレーナー名義の自動文面は関係性リスクが高い → 「確認して送る」を既定に。数値がネガティブな週（増量など）の文面トーン制御が難しい（AI プロンプトで「批判しない・事実+前向き」固定）。

---

## 課題6: 睡眠データ→メッセージ指導フローへの動線が未実装

### 6-A. 記録カード起点の「メッセージで指導」導線【推奨】
- **解決する課題**: クライアント詳細の睡眠タブ/記録サイドパネルで異変に気づいても、メッセージ画面に手で移動してコンテキストを打ち直す断絶を解消する（タスク1.5 繰り延べ分。睡眠に限らず全記録種別に一般化）。
- **ユーザーストーリー**:
  - トレーナーとして、睡眠チャートで「昨夜4時間睡眠」を見つけたら、その場の1クリックで「昨夜の睡眠(4h12m・起床評価△)について」の引用付き返信を書き始めたい。
  - 顧客として、トレーナーのコメントがどの記録についてか、メッセージ内のカードで分かるようにしたい。
- **機能仕様**:
  - Web①: `/message` の `RecordSidePanel` 内 `RecordCard` にホバーアクション「💬 返信で触れる」→ 入力欄に記録要約の引用ブロックを挿入。元記録がタグ付きメッセージ由来なら既存 `reply_to_message_id` を利用（既存 ReplyPreview/ReplyQuote がそのまま機能）。HealthKit 由来（messages 行が存在しない sleep/weight records）は送信時 `metadata.record_ref = {type:'sleep_record', id, summary}` を付与し、Web `MessageBubble` / Mobile メッセージバブルで小型記録カードとして描画。
  - Web②: クライアント詳細の `SleepChart` / `WeightChart` のデータ点クリック → ポップオーバー「この記録についてメッセージ」→ `/message?client={id}&record_ref={type}:{id}` へ遷移し入力欄に自動挿入。
  - Mobile: `metadata.record_ref` 付きメッセージの表示対応のみ（送信機能は不要）。
- **データモデル**: 新テーブル不要。`messages.metadata` (jsonb, 既存) に `record_ref` 規約を追加するのみ。
- **バックエンド**: 変更なし（parse-message-tags は `tags` 空なら記録生成しない既存挙動のままで OK。record_ref は表示専用メタデータ）。
- **通知設計**: 既存のメッセージ通知（FCM）に相乗り。追加不要。
- **既存コードとの接続点**: `fit-connect/src/components/message/RecordCard.tsx` / `RecordSidePanel.tsx` / `ReplyPreview.tsx` / `MessageBubble.tsx`、`fit-connect/src/components/clients/SleepChart.tsx` / `WeightChart.tsx`、`/message` ページのクエリパラメータ処理、`fit-connect-mobile` のメッセージバブル widget。
- **フェーズ分け**: MVP=RecordSidePanel からの引用挿入（メッセージ由来記録のみ=既存 reply 機構流用、Mobile 変更ゼロ） → 拡張1=SleepChart/WeightChart からの deep link → 拡張2=HealthKit 由来 record_ref + Mobile カード描画。
- **規模感**: S（MVP 1日）〜 拡張込み M
- **リスク・考慮事項**: ほぼなし。metadata 規約は meal_estimation の前例に倣い `fit-connect/docs/` にスキーマ規約をドキュメント化（Web/Mobile 双方が解釈するため）。1-A の睡眠悪化アラート →「メッセージで触れる」ボタンにもこの導線を接続すると相乗効果。

---

## 課題7: カルテ（client_notes）のテンプレート/定型文/前回コピーがない

### 7-A. カルテテンプレート + 前回コピー + 変数展開【推奨】
- **解決する課題**: セッション毎のカルテ記入を、テンプレ選択 → 前回値参照 → 差分だけ記入の流れに短縮し、記録品質の均一化と記入率向上を図る。
- **ユーザーストーリー**:
  - トレーナーとして、「初回カウンセリング」「通常セッション」「月次評価」のテンプレを選ぶと見出し構造が入った状態で書き始めたい。
  - トレーナーとして、「前回コピー」で前回カルテを下敷きに変更点だけ直したい。
  - トレーナーとして、テンプレに `{{date}}` `{{client_name}}` `{{weight_latest}}` を入れておくと自動で埋まってほしい。
- **機能仕様**:
  - Web: クライアント詳細のカルテタブのエディタ上部にツールバー追加: [テンプレートから作成 ▼]（自作テンプレ一覧 + プリセット3種同梱）/ [前回のカルテをコピー]。`/settings` にテンプレ管理（CRUD、並び替え）。変数はクライアント側で挿入時に展開（`{{date}}`=今日, `{{client_name}}`, `{{weight_latest}}`=最新 weight_records, `{{session_count}}`=消化セッション数）。
  - 3-B（返信定型文）とテーブル/管理 UI を共通化する場合は `templates` テーブルに `kind text('note'/'reply')` を持たせ一本化【推奨】。
- **データモデル**:
  - 新テーブル `note_templates`（または共通 `templates`）: `id, trainer_id, kind text, title text, body text, sort_order int, created_at, updated_at`。RLS `trainer_id = auth.uid()` 全操作。
  - **先行修復**: `client_notes` の CREATE TABLE migration が欠落（調査済み事実）。現 DB 実体から migration を起こしてコミットしてから着手。
- **バックエンド**: 新 API Route `/api/note-templates`（既存 `/api/client-notes/route.ts` のパターン踏襲）。変数展開はフロントで完結、RPC 不要。
- **通知設計**: 不要。
- **既存コードとの接続点**: `fit-connect/src/app/api/client-notes/route.ts` / `[id]/route.ts`、`fit-connect/src/lib/supabase/getClientNotes.ts`、クライアント詳細ページのカルテタブ、`/settings` ページ。将来は 4-A の「AI相談をカルテに転記」の受け口。
- **フェーズ分け**: MVP=前回コピー（テーブル追加なしで実装可、getClientNotes の最新1件流用）+ プリセットテンプレ3種ハードコード → 拡張1=note_templates CRUD + 変数展開 → 拡張2=3-B と統合、AI 相談転記。
- **規模感**: S（MVP 1日、フル 2-3日）
- **リスク・考慮事項**: client_notes migration 欠落の修復が前提（欠落のまま列追加系を重ねると環境再現不能に。`docs/tasks/lessons.md` の生成物漏れ事例と同種）。他はリスクほぼなし。

---

## カテゴリ内の推奨着手順

1. **6-A MVP + 7-A MVP（各S・計2-3日）**: 既存機構（reply / client_notes API）の流用だけで即効の体験改善。並行して `fcm_token` / `client_notes` の migration 欠落を修復し以降の基盤を整地。
2. **1-A 異常検知エンジン（M）**: alerts テーブル + cron + Web Push。カテゴリの核であり、2-A・5-A・6-A拡張が全てこのデータを消費する。
3. **2-A デイリートリアージ（M）**: 1-A の alerts と既存未読 RPC を統合し、ダッシュボードを「今日の仕事リスト」化。ここまででトレーナーの介入ループ（検知→優先度→行動）が閉じる。
4. **3-A AI返信候補（M）**: 最大の負荷である返信業務を直接軽減。estimate-meal-nutrition の雛形流用で Pro プランの目玉に。3-B 定型文を同時実装し非 Pro にも価値提供。
5. **5-A 週次サマリー → 4-A AI相談（M〜L）**: `get_client_stats_summary` RPC を共用設計して連続実装。5-B（顧客向け配信）と 1-B（即時検知）は各基盤の安定後に。
---

# カテゴリ2: 顧客の継続率（リテンション）を支える仕組み — 機能設計

> 事前調査で確認した事実: `flutter_local_notifications: ^18.0.1` は導入済みだがスケジュール通知(`zonedSchedule`)未使用・`timezone`パッケージ未導入。FCMトークンは `clients.fcm_token` / `trainers.fcm_token` カラムに保存済み（`notification_service.dart` L200-310で確認。テーブル新設は不要）。`rescheduleAssignment` は `assigned_date` を単純UPDATEするのみで履歴を持たない。`onboarding_screen.dart` は存在するが「QR/招待コード選択」の1画面のみで、権限リクエスト導線・機能ツアーは無い。

---

## 課題1: 記録リマインダーが存在しない

3アプローチを併用する。A(ローカル通知)が最速、B(サーバー起点)が本命、C(トレーナー手動)が差別化。

### 1-A. ローカル記録リマインダー 【推奨・最初に着手】

- **解決する課題**: サーバー実装ゼロで「21時に夕食記録リマインド」を実現。オフラインでも確実に発火する。
- **ユーザーストーリー**:
  - 顧客として、夕食の時間帯に記録リマインドを受け取り、忘れずに記録したい
  - 顧客として、リマインド時刻を自分の生活リズムに合わせて変更したい
- **機能仕様**: Mobile設定画面(`settings_screen.dart`)に「リマインダー」セクション新設。体重(朝/任意時刻)・食事(朝昼夕の3スロット)・ワークアウト(当日assignmentがある日の指定時刻)のON/OFFと時刻設定。`zonedSchedule`で毎日繰り返し登録し、**アプリ起動時・記録作成時に「今日すでに記録済みのカテゴリの当日通知をキャンセル」**する(records providerの作成成功コールバックでフック)。通知タップで該当記録フォームへ深いリンク(`onNotificationTap`の既存タップ遷移機構を拡張)。
- **データモデル**: MVPはSharedPreferencesのみ(サーバー保存なし)。拡張で `client_reminder_settings`(client_id PK/FK, meal_times jsonb, weight_time time, workout_reminder_enabled bool, updated_at)を追加しWebトレーナーからも閲覧可に。RLS: 本人R/W+担当トレーナーR。
- **バックエンド**: MVPは不要。
- **通知設計**: 顧客本人・設定時刻・ローカル通知。既定はOFFで、オンボーディング/設定から明示的にON(通知疲れ回避)。
- **既存コードとの接続点**: `fit-connect-mobile/lib/services/notification_service.dart`(ローカル通知チャンネル初期化済み。`zonedSchedule`用に`timezone`パッケージ追加が必要)、`fit-connect-mobile/lib/features/messages/providers/messages_provider.dart`(記録作成成功時のキャンセルフック)、`settings_screen.dart`
- **フェーズ分け**: MVP=体重・夕食の2種固定時刻 → 拡張=カテゴリ別カスタム時刻・記録済みスキップ・深いリンク
- **規模感**: S〜M
- **リスク・考慮事項**: iOSはアプリを長期間起動しないと再スケジュールが切れる(64件上限)→7日分先まで登録し起動毎に更新。Android 13+は`SCHEDULE_EXACT_ALARM`不要な`inexact`で十分。

### 1-B. サーバー起点スマートリマインダー(未記録者抽出Push)

- **解決する課題**: 「実際に記録していない人だけ」に送る精密なリマインド。ローカル通知の「記録済みでも鳴る/端末依存」問題を解消。
- **ユーザーストーリー**: 顧客として、記録済みの日は通知が来ず、忘れた日だけ「夕食の記録がまだのようです」と届いてほしい
- **機能仕様**: cron(毎時)のEdge Functionが、`client_reminder_settings`の時刻が現在時刻±30分の顧客を抽出→当日の該当recordsが無い顧客にFCM Push。同日同カテゴリ再送なし。
- **データモデル**: 1-Aの`client_reminder_settings`に`timezone text default 'Asia/Tokyo'`を追加。`notification_logs`(id, client_id, kind, sent_at, dedup_key unique)で冪等化。
- **バックエンド**: 新Edge Function `send-record-reminders`(cron毎時、auto-skip-workoutsと同じservice_role Bearer認証パターン)。**FCM HTTP v1 API送信の共通モジュールが未存在なので新設**(サービスアカウントJSONをsecretsへ。既存Web Pushはトレーナー向けVAPIDのみで別物)。
- **通知設計**: 顧客・設定時刻±30分・FCM Push。1日最大2通の上限をハードコード。
- **既存コードとの接続点**: `supabase/functions/auto-skip-workouts/index.ts`(cron+service_role認証の雛形)、`clients.fcm_token`(保存済み)、`supabase/functions/parse-message-tags/`(records生成元。未記録判定はweight/meal/exercise/sleep_recordsを直接参照)
- **フェーズ分け**: 1-Aリリース後、拡張として置き換え(ローカル通知はフォールバックに降格)
- **規模感**: M
- **リスク・考慮事項**: FCMサービスアカウント管理、タイムゾーン処理、cron設定がリポジトリ外(既存auto-skipと同様にダッシュボード設定の手順をdocsに残すこと)。

### 1-C. トレーナー手動ナッジ(「つつき」ボタン)

- **解決する課題**: 自動通知より効く「トレーナー本人からの一言」を1タップで送れるようにし、トレーナーの声かけ工数を下げる。
- **ユーザーストーリー**: トレーナーとして、記録が途切れている顧客に定型リマインドを1クリックで送りたい
- **機能仕様**: Web `/clients` 一覧・詳細に「リマインド送信」ボタン。定型文3種(食事/体重/ワークアウト)+自由文。送信するとメッセージとしても残る(messagesにINSERT→既存のFCM通知経路に乗せるだけでも成立)。
- **データモデル**: 追加不要(messages既存で完結)。
- **バックエンド**: メッセージINSERT時の顧客向けPush通知が既にあるならそれを利用。無ければ1-BのFCM送信モジュールを共用する`notify-client` Edge Function。
- **通知設計**: 顧客・トレーナー操作時・FCM(メッセージ通知として)。
- **既存コードとの接続点**: `fit-connect/src/`のメッセージ送信サービス、クライアント一覧(最終記録日の表示があると押しどころが分かる→ストリーク機能2-Aと連動)
- **フェーズ分け**: 1-Bの後に小さく追加
- **規模感**: S
- **リスク・考慮事項**: なし(通常メッセージの範疇)。

---

## 課題2: ストリーク（連続記録）機能なし

### 2-A. 記録ストリーク表示 【推奨】

- **解決する課題**: 「連続◯日記録中」の可視化で日次記録の習慣ループを作る。confetti(目標達成時のみ)しかない現状に日次の小さな報酬を足す。
- **ユーザーストーリー**:
  - 顧客として、ホームで「🔥 12日連続記録中」を見てチェーンを切りたくないと感じたい
  - トレーナーとして、顧客一覧でストリークが切れかけの人を見つけて声かけしたい
- **機能仕様**: Mobile: ホーム(`home_screen.dart`)の今日のまとめカード付近にストリークバッジ、記録サマリ(`records_overview_screen.dart`)に最長記録と月間カレンダーヒートマップ。「何でも1記録あれば継続」のゆるい定義(体重 or 食事 or 運動 or 睡眠のいずれか)。Web: `/clients`一覧にストリーク列(降順ソート可)、途切れそう(昨日記録なし)の警告アイコン。
- **データモデル**: MVPはテーブル追加なし。RPC `get_record_streak(p_client_id uuid)` で4テーブルUNIONの日付集合から連続日数を計算(sleep_recordsのclient_id×日付ユニークと同様の日付基準で)。拡張で `client_streaks`(client_id PK, current_streak int, longest_streak int, last_record_date date, freezes_remaining int default 1)をキャッシュ+フリーズ(週1回まで欠損を無効化=挫折で全消しさせない)。
- **バックエンド**: RPC 1本(MVP)。拡張: `parse-message-tags`のrecords生成後にclient_streaks更新、またはrecordsテーブルへのINSERTトリガー。
- **通知設計**: 「ストリークが切れそうです(昨日未記録)」を1-Bのリマインダーに統合(独立通知は増やさない)。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/home/presentation/widgets/daily_summary_card.dart`、`records_overview_screen.dart`、`supabase/functions/parse-message-tags/`、Web `/report`の比較テーブル(ストリーク列追加)
- **フェーズ分け**: MVP=RPC+ホームバッジ → 拡張=フリーズ・最長記録・Web一覧列・ヒートマップ
- **規模感**: M
- **リスク・考慮事項**: ストリーク定義を厳しくしすぎると逆効果(全カテゴリ必須はNG)。タイムゾーンは日本固定前提でよいが、日付境界はsleep_date_utils.dartの既存基準と揃える。

### 2-B. マイルストーンバッジ

- **解決する課題**: ストリークだけでは拾えない中長期の達成(累計50記録、初回進捗写真、体重-3kg等)を称える。
- **ユーザーストーリー**: 顧客として、節目でバッジと祝福演出をもらい、トレーナーからも「おめでとう」が届いてほしい
- **機能仕様**: Mobile設定orプロフィールにバッジ棚。獲得時は既存confetti+`goal_achievement_overlay.dart`と同系の全画面演出。獲得イベントをトレーナーのWebにも通知(声かけのフック)。
- **データモデル**: `client_badges`(id, client_id, badge_key text, earned_at, unique(client_id, badge_key))。RLS: 本人R+トレーナーR、INSERTはservice roleのみ。
- **バックエンド**: 記録INSERT後の判定をRPC or parse-message-tags拡張で。
- **通知設計**: 顧客(獲得時アプリ内演出+Push)、トレーナー(Web Push、既存`push_subscriptions`経路)。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/goals/presentation/widgets/goal_achievement_overlay.dart`(演出の再利用)、`goal_achievement_provider.dart`
- **フェーズ分け**: 2-Aの拡張として。MVP不要
- **規模感**: M
- **リスク・考慮事項**: バッジ乱発は価値を下げる。10種程度から。

---

## 課題3: オンボーディング未着手

### 3-A. 初回起動フロー完成(権限プライミング+初期設定) 【推奨】

- **解決する課題**: 初回起動→トレーナー紐付け→通知/HealthKit許可→リマインダー初期設定までを一本の導線にし、Day1離脱と「権限OFFのまま使われて通知施策が全部無効」問題を防ぐ。
- **ユーザーストーリー**:
  - 顧客として、招待コード入力後に何をすればいいか迷わず、3分で使い始められる状態になりたい
  - トレーナーとして、招待した顧客が通知ONで使い始めてくれることを期待したい
- **機能仕様**: 既存の `welcome → onboarding(QR/コード選択) → invite_code/qr_scan → trainer_confirm → profile_setup → registration_complete` の後段に追加: (1)通知許可プライミング画面(「トレーナーからの返信を受け取る」と価値を説明してからOS許可ダイアログ=`NotificationService.initialize()`内の`requestPermission`を初回起動時自動ではなくこの画面に移す)、(2)HealthKit連携提案(`health_settings_screen.dart`への導線、スキップ可)、(3)リマインダー初期設定(1-Aの夕食21時だけ提案)、(4)ホーム初回表示時に3ポイントだけのコーチマーク(記録の仕方=#タグ、プランタブ、記録タブ)。
- **データモデル**: `clients.onboarding_completed_at timestamptz` カラム追加(再表示制御。SharedPreferencesだけだと機種変で再走するがそれは許容でも可)。
- **バックエンド**: 不要。
- **通知設計**: なし(許可取得のタイミング設計そのもの)。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/auth/presentation/screens/`(welcome/onboarding/profile_setup/registration_complete 全て既存)、`lib/services/notification_service.dart`(権限リクエストの分離)、`lib/features/health/presentation/screens/health_settings_screen.dart`、`docs/tasks/IMPLEMENTATION_TASKS.md`フェーズ3の骨子
- **フェーズ分け**: MVP=権限プライミング2画面+リマインダー提案 → 拡張=コーチマーク・進捗インジケータ付きステッパー
- **規模感**: M
- **リスク・考慮事項**: iOSは通知許可を一度拒否されると設定アプリ誘導しかできない→プライミング画面で「あとで」を用意し、拒否させない設計が重要。ATT等は不要(広告なし)。

### 3-B. ホームの「はじめの3ステップ」チェックリスト

- **解決する課題**: オンボーディングを1回のフローで終わらせず、初週の行動(初記録・トレーナーに挨拶・HealthKit連携)まで誘導する。
- **ユーザーストーリー**: 顧客として、初週はホーム上部のチェックリストを潰していけば使い方が身につく状態にしたい
- **機能仕様**: `home_screen.dart`最上部にカード(全完了 or 14日経過で消滅)。項目: ①最初の体重を記録 ②トレーナーにメッセージ ③ヘルスケア連携 ④リマインダー設定。各項目タップで該当画面へ。
- **データモデル**: 達成判定は既存データから導出(専用テーブル不要)。非表示フラグのみSharedPreferences。
- **バックエンド**: 不要。
- **既存コードとの接続点**: `home_screen.dart`、`goal_card.dart`の下
- **フェーズ分け**: 3-Aの直後に追加
- **規模感**: S
- **リスク・考慮事項**: なし。

---

## 課題4: 「記録＝メッセージ経由のみ」の摩擦

### 4-A. 記録タブからの直接記録(クイック記録) 【推奨】

- **解決する課題**: 「トレーナーに送るほどでもない」記録の心理的コストを除去。記録タブが閲覧専用である制約を外し、記録行動をチャットから独立させる。
- **ユーザーストーリー**:
  - 顧客として、深夜の間食をトレーナーへのメッセージにせず、こっそり素早く記録したい
  - トレーナーとして、経路がどうであれ全記録がWebの記録タブに揃っていてほしい
- **機能仕様**: Mobile: 記録タブ(`records_screen.dart`)にFAB「+記録」→ボトムシートでカテゴリ選択→`structured_tag_form.dart`のフォームUIを流用した入力→**messagesを経由せず各repositoryから直接INSERT**(`source='manual'`。weight_recordsのsource制約は manual/message/healthkit 対応済み、HealthKit同期が直接INSERTしている前例あり)。各記録画面(weight/meal/exercise/sleep)にも「+」を配置。フォーム末尾に「トレーナーにも送る」トグル(ON時のみ従来どおりタグ付きメッセージ送信=既存経路)。AI栄養推定は`meal_estimation_api.dart`がEdge Function直叩きなので直接記録経路でもそのまま使える。Web: 変更ほぼ不要(記録タブは同じテーブルを読む)。記録カードに経路バッジ(チャット/直接/ヘルスケア)を出すと親切。
- **データモデル**: meal/exercise/sleep_recordsに`source`列が無ければ揃えるmigration(weight_recordsに倣う)。message_id列がnullableであることの確認。
- **バックエンド**: 不要(parse-message-tagsは経由しないだけ)。**重複注意**: 「トレーナーにも送る」ON時に直接INSERT+タグメッセージの二重生成にならないよう、ON時はメッセージ送信のみ(既存webhookに任せる)に倒す。
- **通知設計**: なし。むしろ「通知されない」ことが価値。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart`(フォーム流用元)、`quick_action_bar.dart`、各`*_repository.dart`(weight/meal/exercise/sleep)、`lib/features/health/providers/health_sync_provider.dart`(直接INSERTの前例・冪等パターン)
- **フェーズ分け**: MVP=体重+食事の直接記録 → 拡張=運動・睡眠(手動)、編集・削除、経路バッジ
- **規模感**: M
- **リスク・考慮事項**: 記録がチャットに流れなくなるとトレーナーの気づき機会が減る→Web側は既読管理と無関係に記録タブで拾える設計を維持し、トレーナー向け「今日の新着記録」サマリー(将来のダイジェスト通知)で補完。RLSでclientロールのINSERTポリシーが各recordsテーブルにあるか要確認(現状message経由=service role生成のため欠けている可能性が高い)。

### 4-B. サイレントタグ送信(既存経路の軽量化)

- **解決する課題**: 同じ課題を最小工数で緩和する代替案。メッセージ経路を保ちつつ「チャットのタイムラインを汚さない」記録専用送信を作る。
- **機能仕様**: `structured_tag_form.dart`に「記録のみ(会話に表示しない)」トグル→`messages.metadata`に`{"silent": true}`を付与し、Mobile/Webの会話ビューはフィルタで非表示(既存の会話/記録表示分離=`message_filter.dart`とtags基盤に乗る)。parse-message-tagsはそのまま動くので記録は生成される。
- **データモデル**: 追加なし(metadata jsonb既存)。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/messages/utils/message_filter.dart`、`fit-connect/`のメッセージパネル(#57で分離済みのフィルタ)
- **フェーズ分け**: 4-Aを採らない場合の代替。両方やる価値は薄い
- **規模感**: S
- **リスク・考慮事項**: 「メッセージなのに相手に見えない」という概念のわかりにくさ。長期的には4-Aが素直。**推奨は4-A**。

---

## 課題5: 進捗写真（ボディフォト）専用機能なし

### 5-A. 進捗写真機能(専用テーブル+比較ビュー) 【推奨】

- **解決する課題**: 体重数値より強い「見た目の変化」をリテンション資産にする。メッセージに埋もれる問題と、公開バケットに体の写真が置かれるプライバシー問題を同時に解消。
- **ユーザーストーリー**:
  - 顧客として、月1で同じ構図の写真を撮り、開始時と並べて変化を実感したい
  - トレーナーとして、ビフォーアフターをセッション時に見せてモチベーションを支えたい
- **機能仕様**: Mobile: 記録タブに「写真」サブタブ追加(現在6サブタブ→7、または体重タブ内セクション)。カメラ起動時に前回写真の半透明オーバーレイ(同じ構図で撮れる)+正面/横/背面のポーズ選択。ギャラリーは時系列グリッド、比較ビューは2枚選択のスライダー/並列表示、撮影時体重を自動添付。月1撮影リマインダー(1-Aに統合)。Web: `/clients`詳細に「写真」タブ追加、並列比較+セッション中に見せるモード。
- **データモデル**: 新テーブル `progress_photos`(id uuid, client_id FK, taken_on date, pose text check in('front','side','back'), storage_path text, weight_kg numeric null, note text, created_at)。**新Storageバケット `progress-photos` は非公開**(既存message-photosのpublic readを踏襲しない)。Storage RLS: パス先頭`{client_id}/`で本人+担当トレーナーのみselect/insert。表示は署名付きURL。
- **バックエンド**: 不要(直接INSERT)。拡張でトレーナーへの「新しい進捗写真」Web Push。
- **通知設計**: 顧客へ月1撮影リマインド(ローカル通知)、トレーナーへアップロード通知(既存Web Push経路、任意)。
- **既存コードとの接続点**: `fit-connect-mobile/lib/services/storage_service.dart`(アップロード)、`image_picker`導入済み、`lib/shared/widgets/full_screen_image_viewer.dart`、Web `/clients`タブ構造、`supabase/migrations/20260102075114_create_message_photos_bucket.sql`(バケット作成migrationの雛形)
- **フェーズ分け**: MVP=撮影/アップロード/時系列ギャラリー/2枚比較 → 拡張=オーバーレイガイド・ポーズ別フィルタ・体重グラフとの重ね表示・SNSシェア画像生成(バックログ連動)
- **規模感**: L
- **リスク・考慮事項**: **体の写真=センシティブデータ**。非公開バケット必須、App Storeのプライバシー表(健康とフィットネス+写真)更新、削除機能(顧客が自分で消せる)必須。カメラ/フォトライブラリ権限の用途文言。3Dスキャン(バックログ)はこの土台の遥か先。

### 5-B. メッセージ写真のタグ抽出ギャラリー(軽量代替)

- **解決する課題**: 専用機能を作らず、`#進捗写真`タグ付きメッセージの画像を横断ギャラリー表示するだけの最小案。
- **機能仕様**: Mobile記録タブ+Web記録パネルに、`messages.tags`に`進捗写真`を含むメッセージの`image_urls`を時系列グリッド表示。
- **データモデル**: 追加なし。
- **既存コードとの接続点**: `message_tag_parser.dart`、`tag_model.dart`、messages.tags(#56で統一済み)
- **規模感**: S
- **リスク・考慮事項**: message-photosバケットがpublic readのままなので体の写真の置き場として不適。**繋ぎとしては可だが、推奨は5-A**(セキュリティ改善を伴うため)。

---

## 課題6: 顧客側から目標を確認・相談するUIがない

### 6-A. 目標詳細画面(Mobile) 【推奨・MVP】

- **解決する課題**: 目標が「トレーナーがWebで設定した数値」で終わっている状態を、顧客が毎日見て自分事化できる画面にする。
- **ユーザーストーリー**:
  - 顧客として、目標体重までの残り・ペース・期日までの日数をいつでも確認したい
  - 顧客として、いまのペースで間に合うのかを知りたい(7-Aの予測と連動)
- **機能仕様**: ホームの`goal_card.dart`タップ→新画面「目標の詳細」。内容: 目標体重/現在/開始時、達成率(既存RPC `calculate_achievement_rate`)、期日カウントダウン、週次ペース(実績kg/週 vs 必要kg/週)、体重グラフに目標ラインとペースライン重畳、7-Aの予測到達日。
- **データモデル**: 追加なし(clientsの目標体重/目的/期日カラム既存)。
- **バックエンド**: 既存RPCで足りる。ペース計算はクライアント側。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/goals/providers/goal_provider.dart`、`goal_repository.dart`、`home/presentation/widgets/goal_card.dart`、`weight_records_provider.dart`
- **フェーズ分け**: MVP=詳細画面 → 拡張=7-A予測統合・目標達成履歴
- **規模感**: S〜M
- **リスク・考慮事項**: 「間に合いません」表示はネガティブに働き得る→「ペースを上げるには」の提案トーンで、断定的な失敗宣告をしない文言設計。

### 6-B. 「目標について相談」導線(タグ付きメッセージ)

- **解決する課題**: 目標の変更・相談をチャネル化し、顧客発の目標対話を生む(相談が発生する=解約しにくい関係性)。
- **機能仕様**: 6-Aの画面に「トレーナーに相談する」ボタン→メッセージ画面へ遷移し`#目標相談`タグ+定型文(現在値・目標・気持ちの選択肢)がプリセットされた状態で送信。Web側はタグフィルタで相談を見逃さない。
- **データモデル**: 追加なし(tags既存)。
- **既存コードとの接続点**: `structured_tag_form.dart`(タグ種別追加)、`message_filter_provider.dart`、Web記録サイドパネルのタグフィルタ
- **フェーズ分け**: 6-Aと同時
- **規模感**: S
- **リスク・考慮事項**: なし。

### 6-C. 顧客からの目標提案→トレーナー承認フロー(拡張)

- **解決する課題**: 目標編集権を顧客に部分開放しつつ、トレーナーの専門性(最終決定権)を守る。
- **機能仕様**: 顧客が新目標値・期日を提案→Webに承認/修正カード→承認で`clients`の目標カラム更新+双方に通知。
- **データモデル**: `goal_proposals`(id, client_id, proposed_weight numeric, proposed_deadline date, reason text, status pending/approved/rejected, responded_at)。RLS: 顧客=自分のC/R、トレーナー=担当分R/U。
- **バックエンド**: 承認時のclients更新はRPC(`approve_goal_proposal`)でトランザクション化。
- **通知設計**: トレーナーへWeb Push(提案時)、顧客へFCM(回答時)。
- **フェーズ分け**: 6-A/Bの利用状況を見てから
- **規模感**: M
- **リスク・考慮事項**: 承認フローが重いと使われない。「相談(6-B)で済む」可能性があるので後回しで良い。

---

## 課題7: カロリー収支→体重予測の顧客向け表示がない

### 7-A. 体重予測のDart移植+Mobile表示 【推奨】

- **解決する課題**: Webにしかない`weightPrediction.ts`の予測を顧客本人に見せ、「記録すると未来が見える」という記録の意味付け(最強の記録動機)を作る。
- **ユーザーストーリー**:
  - 顧客として、今日までの食事記録から「このペースなら◯月◯日に目標達成」を見たい
  - 顧客として、食べすぎた日に予測がどう動くかを見て翌日の行動を変えたい
- **機能仕様**: `weightPrediction.ts`(確認済みexport: `calculateBmr`/`calculateCalorieBalance`/`predictWeight`/`getPeriodDays`、Mifflin/Harris式)を`fit-connect-mobile/lib/shared/utils/weight_prediction.dart`へ移植。表示: ①体重画面(`weight_record_screen.dart`)のグラフに予測点線+目標ライン、②6-Aの目標詳細に「予測到達日」、③ホームの今日のまとめに「今日の収支 -320kcal」行。必要入力: BMR(clientsの性別/年齢/身長カラム既存)+摂取(meal_records.kcal)+活動係数(MVPは固定or設定画面で選択)。
- **データモデル**: 追加なし。活動係数を永続化するなら`clients.activity_level text`追加(Web側フォームにも同時追加)。
- **バックエンド**: MVPは不要(クライアント計算)。**拡張でRPC `get_weight_prediction`に一元化し、Web/Mobileのロジック二重管理を解消するのが本筋**。
- **通知設計**: なし(週次サマリー通知に載せるのは拡張)。
- **既存コードとの接続点**: `fit-connect/src/utils/weightPrediction.ts`(移植元・仕様の真実)、`fit-connect-mobile/lib/features/weight_records/presentation/screens/weight_record_screen.dart`、`daily_summary_card.dart`、`meal_records_provider.dart`
- **フェーズ分け**: MVP=収支表示+予測線 → 拡張=RPC一元化・活動係数設定・食事記録が疎な週の信頼度表示
- **規模感**: M
- **リスク・考慮事項**: **健康系の予測表示はApp Store審査で「医学的助言」と誤認されないよう免責文言を添える**。食事記録が欠けている日は収支が過大にマイナスに見える→記録率が低い期間は予測を非表示/低信頼表示にするガードが必須。摂食障害傾向のユーザーへの配慮としてネガティブ演出(赤字強調等)は避ける。二重実装のドリフトはテストフィクスチャ共有(同一入力→同一出力のゴールデンテスト)で防ぐ。

---

## 課題8: ワークアウト繰越問題（リスケでプランが消える）

### 8-A. リスケ設計の整理(履歴保持+表示修正) 【推奨・不具合修正として最優先】

- **解決する課題**: バックログで「不具合寄り」とされる「翌日に回すとプランが消える」を解消。`rescheduleAssignment`が`assigned_date`を裸でUPDATEするだけで移動元の痕跡が消える現状を、履歴を持つ移動に変える。
- **ユーザーストーリー**:
  - 顧客として、今日のプランを明日に回しても、明日のプランタブに確実に現れてほしい
  - トレーナーとして、Webのカレンダーで「元は月曜だったが水曜に移動」が分かってほしい
- **機能仕様**: (1)migration: `workout_assignments`に`original_date date`・`rescheduled_count int default 0`追加(初回リスケ時のみoriginal_dateを埋める)。(2)`rescheduleAssignment`(`workout_repository.dart` L170付近)を両カラム更新に変更。(3)**消える原因の特定と修正**: 週表示(`getWeeklyAssignments`は`assigned_date`範囲取得)・`weekly_mini_calendar.dart`・Web WeeklyCalendarで、移動先が表示週外/フィルタ外に落ちるケースと、翌週分の定期アサインとの重複表示を検証して直す。(4)リスケ上限(例: 同一assignmentは2回まで、移動先は7日以内)を`reschedule_date_picker.dart`でUI制約。(5)Webカレンダーはリスケされたアイテムにアイコンとツールチップ(元日付)表示、元日付セルにはゴースト表示。
- **データモデル**: 上記2カラム追加のmigration(※調査サマリーで`workout_assignments.status`列のmigration欠落疑いが指摘済み。このmigrationで現状スキーマとの整合を先に監査すること)。
- **バックエンド**: `auto-skip-workouts`は`assigned_date`基準なのでリスケ済みは自然に猶予が延びる(現行ロジックのままで整合)。変更不要。
- **通知設計**: なし(8-Bで補完)。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/workout/data/workout_repository.dart`(`rescheduleAssignment`/`getWeeklyAssignments`/`getOverdueAssignments`)、`reschedule_date_picker.dart`、`overdue_assignment_card.dart`、`weekly_mini_calendar.dart`、`supabase/functions/auto-skip-workouts/index.ts`、Web `WeeklyCalendar`
- **フェーズ分け**: MVP=カラム追加+消える不具合修正+リスケ上限 → 拡張=Webゴースト表示・リスケ履歴のトレーナー通知
- **規模感**: M(不具合調査込み)
- **リスク・考慮事項**: 定期アサイン(recurrence)との衝突(移動先に同一プランが既にある場合はマージか警告)。既存データはoriginal_date=nullで自然に後方互換。

### 8-B. スキップ前警告通知

- **解決する課題**: auto-skipが3日で黙って`skipped`にする現状を、消える前日に顧客へ「明日で期限切れ。今やる?明日に回す?」と選択肢付きで通知して救済する。
- **機能仕様**: `auto-skip-workouts`実行時(またはcron別枠)に「明日skip対象になるpending assignment」を抽出→顧客にFCM Push。タップでプランタブの`overdue_assignment_card.dart`へ遷移し、既存の「やる/リスケ/スキップ」操作に接続。
- **データモデル**: `notification_logs`(1-Bと共用)で重複送信防止。
- **バックエンド**: `auto-skip-workouts/index.ts`に警告フェーズ追加(cutoff-1日のpendingをselect→FCM送信)。1-BのFCM送信モジュールを共用。
- **通知設計**: 顧客・スキップ前日の夕方・FCM。
- **既存コードとの接続点**: `supabase/functions/auto-skip-workouts/index.ts`、`overdue_assignment_card.dart`、`notification_service.dart`のタップ遷移
- **フェーズ分け**: 8-Aと1-BのFCM基盤の後
- **規模感**: S
- **リスク・考慮事項**: なし。

### 8-C. 週間タスクプール方式(代替・大規模)

- **解決する課題**: そもそも「日付固定」をやめ、「今週やる3つ」というプールから顧客が消化する方式にすれば繰越問題自体が消滅する。
- **機能仕様**: `workout_assignments`に`assigned_week`(週開始日)を導入し、日付は「予定日(目安)」に降格。プランタブは「今週の残り」リスト中心のUIへ再設計。
- **規模感**: L(Web作成フロー・Mobile実行UI・auto-skip全て再設計)
- **リスク・考慮事項**: トレーナーの「この日にやってほしい」という処方意図と衝突する。**推奨は8-A+8-Bで、8-Cはユーザーの声が集まってから検討**。

---

## カテゴリ内の推奨着手順

1. **8-A(繰越不具合修正)** — 不具合寄りで信頼を毀損中。データモデル整備(original_date)も他機能に先行して安い。
2. **1-A(ローカルリマインダー)+3-A(オンボーディング権限プライミング)** — 通知許可の取り方と通知そのものはセットで初めて機能する。リテンションの土台。
3. **4-A(直接記録)+2-A(ストリーク)** — 記録の摩擦を下げてから継続を可視化する順番。ストリークは記録が簡単になって初めて回る。
4. **1-B(FCM送信基盤+スマートリマインダー)+8-B(スキップ前警告)** — サーバーPush基盤を1度作って2用途に使う。
5. **7-A(体重予測)→6-A/B(目標詳細・相談)→5-A(進捗写真)** — 「記録の意味付け」系。5-AはL規模かつバケット設計を伴うため独立スプリントで。
---

# カテゴリ3: 収益化・ビジネス基盤 — 機能設計

> 前提として確認した実装事実: `trainers.subscription_plan`（free/pro）は `supabase/migrations/20260502120100_add_subscription_plan_to_trainers.sql` で追加済みで、カラムコメントに「Stripe連携時に自動更新する想定」と明記されている。Mobile側のPro判定は `fit-connect-mobile/lib/features/subscription/providers/ai_features_enabled_provider.dart` が「顧客の担当トレーナーのplan」を参照して機能表示を切替えており、**顧客自身は何も購入しない構造**（TODOコメントにStripe webhook対応が既に予告されている）。また `ticket_subscriptions` / `ticket_templates` テーブルはWeb API（`fit-connect/src/app/api/ticket-subscriptions/route.ts`）から使用されているが **CREATE TABLE migrationがリポジトリに存在しない**（client_notesと同種の欠落）。`tickets` テーブルには価格カラムが一切ない。

---

## 課題1: 決済が一切ない（Proプランを売る手段がない）

アプローチは3案。**推奨は案A（Stripe Checkout + Customer Portal）**。案B（Stripe Elements自前UI）は工数対効果が悪く、案C（Paddle/Lemon SqueezyなどMoR）は日本円・インボイス対応と手数料面で現状不利なため列挙のみとする。

### 機能1-A: トレーナーSaaS課金（Stripe Checkout + Customer Portal）【推奨】

- **解決する課題**: `subscription_plan` フラグを手動でしか変更できない現状に対し、トレーナーがWebから自分でProを購入・解約でき、フラグがwebhookで自動更新される状態にする。
- **ユーザーストーリー**:
  - トレーナーとして、設定画面から月額Proプランをカード決済で申し込み、即座にAI栄養推定が使えるようになりたい。
  - トレーナーとして、カード変更・領収書取得・解約をセルフサービスで行いたい。
  - トレーナーとして、無料トライアル期間中にPro機能を試したい。
- **機能仕様**:
  - Web `settings` に「プラン・お支払い」タブを新設（`fit-connect/src/app/(user_console)/settings/` 配下に `_components/BillingSection.tsx`）。現プラン表示・「Proにアップグレード」ボタン → Stripe Checkoutへリダイレクト。契約中は「お支払い管理」ボタン → Stripe Customer Portalへ。
  - 決済成功後 `/settings?billing=success` に戻し、トースト表示。
  - `past_due`（支払失敗）時はダッシュボード上部にバナー表示。猶予期間（例: 7日）経過で `subscription_plan` を `free` に戻す。
  - Mobileは変更なし（後述のIAPリスク参照。プラン名・価格・購入導線をMobileに一切出さない）。
- **データモデル**:
  - `trainers` に追加: `stripe_customer_id text unique`
  - 新テーブル `trainer_subscriptions`: `id uuid PK`, `trainer_id uuid FK→trainers`, `stripe_subscription_id text unique`, `stripe_price_id text`, `status text CHECK (in 'trialing','active','past_due','canceled','incomplete')`, `current_period_end timestamptz`, `cancel_at_period_end boolean`, `created_at/updated_at`
  - 新テーブル `billing_events`（webhook冪等・監査）: `id uuid PK`, `stripe_event_id text unique`, `event_type text`, `payload jsonb`, `processed_at timestamptz`
  - RLS: `trainer_subscriptions` はトレーナー本人のSELECTのみ。INSERT/UPDATEはservice roleのみ（RLSポリシーを作らない＝admin経由限定）。`billing_events` はservice roleのみ。
- **バックエンド**:
  - Next.js API Route 新設: `/api/stripe/checkout`（Checkout Session作成）、`/api/stripe/portal`（Portal Session作成）、`/api/stripe/webhook`（署名検証 → `checkout.session.completed` / `customer.subscription.updated|deleted` / `invoice.payment_failed` を処理し `trainers.subscription_plan` と `trainer_subscriptions` を更新）。既存の `supabaseAdmin` パターン（`fit-connect/src/lib/supabaseAdmin.ts`）をそのまま使える。
  - Edge Functionではなく Next.js Route を推奨（Stripe SDK・環境変数をWeb側に一元化。Supabase側に置く場合は `supabase/functions/stripe-webhook/` でも可）。
- **通知設計**: 支払失敗時にトレーナーへメール（Stripe標準のsmart retriesメール利用で初期は追加実装ゼロ）。アプリ内はダッシュボードバナーのみ。
- **既存コードとの接続点**:
  - `supabase/migrations/20260502120100_add_subscription_plan_to_trainers.sql`（更新対象フラグ）
  - `fit-connect-mobile/lib/features/subscription/providers/ai_features_enabled_provider.dart`（planが変わると自動でAI機能が切替わる。keepAliveなのでアプリ再起動まで反映されないTODOが既記載 → 拡張フェーズでRealtime購読化）
  - `fit-connect/src/app/(user_console)/settings/`（タブ追加先）
  - Edge Function `estimate-meal-nutrition`（Pro判定の実利用箇所。plan降格時に自動で拒否されるかの確認が必要）
- **フェーズ分け**: MVP=Checkout+Portal+webhook+設定タブ（単一Pro月額プラン）→ 拡張1=年額プラン・無料トライアル14日 → 拡張2=Mobile側planのRealtime反映、従量制（AI推定回数課金）検討。
- **規模感**: M（3-5日。Stripeダッシュボード設定含む）
- **リスク・考慮事項**:
  - **Apple/Google IAP**: 購入者はトレーナー（Web専用ユーザー）で、Mobileアプリ利用者（顧客）は購入当事者ではない。ただしMobileに「Proにアップグレード」「トレーナーがPro契約すると使えます」等の文言・価格・外部リンクを出すとIAP誘導規約（App Store Review 3.1.1/3.1.3）に抵触しうる。**Mobileでは機能の有無のみ表現し、課金への言及を完全に排除する**（現状の `aiFeaturesEnabled=false` で非表示にする実装が既に正解の形）。
  - webhookの冪等性（`billing_events.stripe_event_id` unique制約で担保）、Vercelのwebhookタイムアウト、テスト環境（Stripe test mode）とSupabaseローカルの組合せ。
  - 特商法表記・利用規約が先に必要（課題4と依存関係あり）。

### 機能1-B: Stripe Elements による自前決済UI【非推奨・列挙のみ】

- **解決する課題**: 同上。決済画面をアプリ内に埋め込みブランド一貫性を高める。
- **非推奨理由**: SCA/3Dセキュア・カード更新・請求書などをすべて自前実装する必要があり、MVP段階では規模L。Checkoutで十分。将来ブランド要件が上がったら移行。
- **規模感**: L

### 機能1-C: Merchant of Record（Paddle / Lemon Squeezy）【代替案・列挙のみ】

- **解決する課題**: 同上＋インボイス/税務処理の外部化。
- **考慮**: 日本の個人事業主トレーナー向けSaaSとしては手数料（5%+）が重く、日本語請求書対応も弱い。海外展開時に再検討。
- **規模感**: M

---

## 課題2: チケット/月契約が回数管理のみ（金銭と繋がっていない）

アプローチは3案あり、**推奨は「案2-A（支払記録・請求管理）を先行し、案2-B（Stripe Connect決済代行）を拡張として重ねる」**二段構え。案2-Cは軽量つなぎ。

### 機能2-A: チケット価格設定＋支払記録・未払い管理【推奨・先行】

- **解決する課題**: トレーナーが別ツール（紙・スプレッドシート）で管理している「いくらで売ったか・払われたか」をFIT-CONNECT内に取り込む。決済処理自体はまだ外部（現金・銀行振込）でよい。
- **ユーザーストーリー**:
  - トレーナーとして、チケットテンプレートに価格を設定し、発行時に支払予定（金額・期日・支払方法）を自動生成したい。
  - トレーナーとして、未払いの顧客を一覧で見て、入金確認したら1タップで「支払済み」にしたい。
  - トレーナーとして、月契約の売上見込み（MRR相当）をダッシュボードで見たい。
- **機能仕様**:
  - Web `/tickets` ページに「支払い」タブ追加（既存タブ: テンプレート/発行済み/月契約の並びに追加。`fit-connect/src/app/(user_console)/tickets/page.tsx`）。未払い一覧（顧客名・金額・期日・経過日数）、支払済みマーク、支払方法記録、領収書番号採番。
  - `TemplateList.tsx` / `CreateSubscriptionModal.tsx` / `EditIssuedTicketModal.tsx` に価格入力欄追加。チケット発行・月契約の毎月チケット発行時に `payments` 行を自動生成。
  - ダッシュボード（`/dashboard`）に「今月の売上・未収金」カード追加。`/report` に売上推移を将来統合。
  - 領収書: 支払済みレコードから領収書PDF出力（`/report` の既存PDF出力実装を流用）。
  - Mobile: 変更なし（顧客に金額を見せるのは案2-Bから。段階導入でトラブル回避）。
- **データモデル**:
  - **前提整備**: `ticket_templates` / `ticket_subscriptions` のCREATE TABLE migrationが欠落しているため、まず現行スキーマを `supabase/migrations/` に固定するmigrationを作成（client_notes欠落と合わせて解消推奨）。
  - `ticket_templates` に追加: `price_yen integer`（null=価格未設定で後方互換）
  - `tickets` に追加: `price_yen integer`
  - 新テーブル `payments`: `id uuid PK`, `trainer_id uuid FK`, `client_id uuid FK`, `ticket_id uuid FK nullable`, `ticket_subscription_id uuid FK nullable`, `amount_yen integer NOT NULL`, `method text CHECK (in 'cash','bank_transfer','card_external','stripe')`, `status text CHECK (in 'unpaid','paid','overdue','refunded') DEFAULT 'unpaid'`, `due_date date`, `paid_at timestamptz`, `receipt_number text`, `note text`, `stripe_checkout_session_id text nullable`（案2-B用に先置き）, `created_at/updated_at`
  - RLS: trainer本人（`trainer_id = auth.uid()`）のCRUD。顧客からのSELECTは案2-B導入時に「自分宛のみ」ポリシーを追加。
- **バックエンド**:
  - `/api/tickets` / `/api/ticket-subscriptions`（既存Route）に payments 自動生成ロジックを追加。
  - cron（Supabase pg_cron or 既存 `auto-skip-workouts` と同様の方式）: `due_date` 超過の `unpaid` を `overdue` へ更新。月契約の `next_issue_date` 自動発行cronの存在確認（リポジトリ外設定の疑いあり）と同時に整備。
- **通知設計**: MVPは通知なし（トレーナーがWeb内で確認）。拡張で「未払いがN日超過」をWeb Push（既存 `push_subscriptions` + web-push実装を流用）。
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/tickets/_components/`（TemplateList / SubscriptionList / CreateSubscriptionModal / EditIssuedTicketModal）、`fit-connect/src/app/api/ticket-subscriptions/route.ts`、`fit-connect/src/lib/supabase/getTicketSubscriptions.ts`
- **フェーズ分け**: MVP=価格カラム＋payments＋未払い一覧＋手動消込 → 拡張1=領収書PDF・売上ダッシュボード → 拡張2=案2-Bへ接続。
- **規模感**: M（1週弱）
- **リスク・考慮事項**: 金額データはRLS厳格必須（既知のclientsテーブルanonポリシー残存問題と同種の事故が金銭情報で起きると致命的。**anonポリシー撤去を先に実施すべき**）。領収書の適格請求書（インボイス制度）対応はトレーナーの課税事業者判定次第なので、登録番号フィールドをtrainer設定に持たせる程度に留める。

### 機能2-B: Stripe Connect による顧客決済代行（請求リンク）【拡張・推奨】

- **解決する課題**: トレーナー→顧客の実際の金銭授受をアプリ内で完結させる。「このアプリがないと仕事にならない」依存度の核になる機能。
- **ユーザーストーリー**:
  - トレーナーとして、チケット発行時に決済リンクを顧客へメッセージで送り、カード払いしてもらいたい。
  - 顧客として、アプリ内の請求からそのままカードで支払い、支払履歴を見たい。
  - トレーナーとして、月契約の毎月の支払いを自動化（カード自動課金）したい。
- **機能仕様**:
  - Web: 設定に「決済を受け取る（Stripe連携）」セクション → Stripe Connect Expressオンボーディング。tickets画面の未払い行に「請求リンクを送る」ボタン → チャット（既存messages）に決済URL付きメッセージを自動送信。
  - Mobile: メッセージ内の請求カード（`messages.metadata` に `payment_request` を格納し専用バブル表示。既存の `meal_estimation` metadataパターンを踏襲）。タップで**外部ブラウザ（SFSafariViewController等）のStripe Checkout**を開く。支払完了で `payments.status='paid'` に自動更新、チャットに完了メッセージ。
- **データモデル**:
  - `trainers` に追加: `stripe_connect_account_id text`, `connect_charges_enabled boolean DEFAULT false`
  - `payments` の `stripe_checkout_session_id` / `method='stripe'` を使用
  - `payments` にRLS追加: 顧客は自分宛（`client_id = auth.uid()` 相当の参照経路）のSELECTのみ
- **バックエンド**: `/api/connect/onboard`（Account Link発行）、`/api/connect/checkout`（destination charge + application_fee でプラットフォーム手数料徴収可）、`/api/stripe/webhook` に `checkout.session.completed`（Connect分岐）追加。月契約自動課金はStripe Subscription（Connect上）へ移行するフェーズ3。
- **通知設計**: 支払完了→トレーナーへWeb Push（既存実装流用）。請求受領→顧客へFCM（`fit-connect-mobile/lib/services/notification_service.dart` 実装済み。ただしFCMトークンのサーバー保存テーブルが未確認のため、`fcm_tokens` テーブル整備が前提）。
- **既存コードとの接続点**: `messages.metadata jsonb`（20260502120200）、Mobile `message_bubble.dart`、Web Push実装、`payments`（機能2-A）
- **フェーズ分け**: フェーズ1=単発チケットの請求リンク → フェーズ2=月契約の自動課金 → フェーズ3=プラットフォーム手数料（FIT-CONNECT自体の第2収益源）。
- **規模感**: L（2-3週）
- **リスク・考慮事項**:
  - **Apple IAP**: パーソナルトレーニングは「アプリ外で消費される対人サービス」（App Store Review 3.1.3(e) / person-to-person 3.1.3(d)）に該当し、**IAP不要・外部決済OK**。ただし決済画面はWebViewよりも外部ブラウザ/Checkoutリダイレクトが審査上安全。Googleも同様（physical services除外）。
  - Stripe Connectの本人確認（トレーナー側KYC）離脱率、返金・チャージバックのオペレーション設計、資金移動を伴うため利用規約での責任分界が必須（課題4依存）。

### 機能2-C: Stripe Payment Links 手貼り運用【軽量つなぎ案】

- **解決する課題**: Connect実装前のつなぎとして、トレーナーが自分のStripeアカウントのPayment Linkを `payments.note` やメッセージに貼る運用をガイドで案内。実装はpaymentsに「外部決済リンク」テキスト欄を足すのみ。
- **規模感**: S
- **考慮**: プラットフォームは金流に関与しないため規約リスク最小。ただし自動消込不可。

---

## 課題3: ランディングページ未着手

### 機能3-A: LP＋料金ページ＋サインアップ導線【推奨】

- **解決する課題**: 新規トレーナー獲得の入口ゼロ状態を解消。Pro課金（課題1）の受け皿となる料金表示も兼ねる。
- **ユーザーストーリー**:
  - 見込みトレーナーとして、検索/SNSからLPに到達し、機能と料金を理解して無料登録したい。
  - 既存トレーナーとして、顧客に「このアプリを使っている」と紹介できる公式ページが欲しい。
- **機能仕様**:
  - `fit-connect/src/app/(marketing)/` route group新設: `/`（LP本体: ヒーロー/機能紹介/料金/CTA/フッター）、`/pricing`、`/legal/*`（課題4）。現在のルート `fit-connect/src/app/page.tsx` の挙動（リダイレクト）をLPへ差し替え、ログイン済みなら `/dashboard` へ。
  - `docs/tasks/IMPLEMENTATION_TASKS.md` フェーズ4（4.1〜4.5）の骨子に準拠: ヒーロー（キャッチコピー＋アプリスクショ）、機能紹介（メッセージ/記録/AI栄養推定/ワークアウトプラン/レポート）、料金（Free/Pro比較表 → CheckoutへのCTA）、フッター（法務リンク）。
  - Server Component＋静的生成でLighthouse最適化、メタタグ/OGP、アナリティクス（Vercel Analytics or GA4）。
  - デザイントークン: Web用トークン（Noto Sans JP、radius 6px、グラデーション禁止等）に準拠。実装時は `ui-ux-pro-max` スキル → `nextjs-ui` 委託のワークフロー。
- **データモデル**: なし（問い合わせフォームを置く場合のみ `contact_inquiries` テーブル or フォームSaaS利用。MVPはmailtoで十分）。
- **バックエンド**: なし。
- **通知設計**: なし。
- **既存コードとの接続点**: `fit-connect/src/app/page.tsx`、`fit-connect/src/app/(auth)/signup/`（CTA遷移先）、`docs/tasks/IMPLEMENTATION_TASKS.md` L172-204
- **フェーズ分け**: MVP=1ページLP＋料金セクション＋法務フッター → 拡張=導入事例・ブログ（SEO）・デモ動画・お問い合わせフォーム。
- **規模感**: M（3-5日）
- **リスク・考慮事項**: 料金を載せる以上、特商法表記（課題4）が同時公開必須。App Store申請時にもマーケティングURL/サポートURLとして流用できるため、Mobileリリース前に完成させる価値が高い。

---

## 課題4: 法務要件未整備

### 機能4-A: 法務ページ一式＋同意フロー【必須・最優先クラス】

- **解決する課題**: 利用規約・プライバシーポリシー・特商法表記が存在せず、課金開始（課題1）もApp Store審査（プライバシーポリシーURL必須）も法的にブロックされる状態を解消。
- **ユーザーストーリー**:
  - トレーナーとして、サインアップ時に規約に同意し、いつでも参照したい。
  - 顧客として、健康データ（体重・食事・睡眠・HealthKit）の取扱いを確認したい。
  - 運営者として、規約改定時に再同意を取りたい。
- **機能仕様**:
  - Web: `(marketing)/legal/terms`, `/legal/privacy`, `/legal/tokushoho`（特商法。Pro課金開始と同時公開）。`(auth)/signup` に同意チェックボックス＋リンク追加。
  - Mobile: 設定画面（既存5タブ目）に「利用規約」「プライバシーポリシー」リンク（url_launcherでWebページを開く。アプリ内複製は保守二重化になるので不可）。初回サインイン後に同意ダイアログ（バージョン付き）。
  - App Store Connect / Play Console のプライバシーURL・データセーフティ申告と整合させる（HealthKitデータは特に厳格: 「健康データを広告に使わない」等の明記必須）。
- **データモデル**:
  - 新テーブル `terms_acceptances`: `id uuid PK`, `user_id uuid`（trainer/client両対応）, `user_type text CHECK (in 'trainer','client')`, `document text CHECK (in 'terms','privacy')`, `version text`, `accepted_at timestamptz`
  - RLS: 本人INSERT/SELECTのみ。
- **バックエンド**: なし（同意記録はクライアントから直INSERT）。規約改定時の再同意判定は最新versionとの比較をアプリ側で実施。
- **通知設計**: 規約改定時のみ、Webバナー＋Mobile起動時ダイアログ。
- **既存コードとの接続点**: `fit-connect/src/app/(auth)/signup/`、Mobile設定画面（`fit-connect-mobile/lib/features/` 配下settings）、HealthKit実装（`health_repository.dart` — プライバシーポリシー記載内容の根拠）
- **フェーズ分け**: MVP=3文書静的ページ＋signup同意チェック → 拡張=同意バージョン管理テーブル＋再同意フロー。
- **規模感**: S〜M（文面ドラフト含め2-3日。**最終文面は弁護士/行政書士レビュー推奨**、特にStripe Connect導入時は資金決済・役務提供の責任分界）
- **リスク・考慮事項**: 健康情報＝要配慮個人情報に準ずる扱い（個人情報保護法）。AI栄養推定でAnthropic APIへ食事画像・テキストを送信している事実をプライバシーポリシーに明記必要。特商法表記には運営者住所・返金ポリシー必須。

---

## 課題5: 招待コード割引の仕組みなし

### 機能5-A: 紹介コード＋Stripeプロモーションコード連携【推奨】

- **解決する課題**: トレーナー間紹介の獲得チャネルがない状態に、既存トレーナーが紹介コードを配り、新規トレーナーがPro初月割引を受けられる仕組みを作る（既存のClientInviteModalは「トレーナー→顧客」招待であり別物。本機能は「トレーナー→トレーナー」紹介）。
- **ユーザーストーリー**:
  - トレーナーとして、自分の紹介コードを同業者にシェアし、相手がPro契約したら自分も割引（or 無料月）を得たい。
  - 新規トレーナーとして、紹介コード入力でPro初月50%オフ等を受けたい。
- **機能仕様**:
  - Web: 設定「プラン・お支払い」タブに「紹介プログラム」カード（自分のコード表示・コピー・成約数）。signupまたはCheckout画面でコード入力 → Checkout Session作成時にStripe `promotion_code` を適用（`allow_promotion_codes: true` にすればStripe標準UIで入力可能＝実装最小）。
  - 紹介成立（被紹介者の初回支払完了webhook）で紹介者にリワード（Stripe Customer Balanceへクレジット付与 or クーポン適用）。
- **データモデル**:
  - 新テーブル `referral_codes`: `id uuid PK`, `trainer_id uuid FK unique`, `code text unique`（例: 8桁英数）, `stripe_promotion_code_id text`, `created_at`
  - 新テーブル `referrals`: `id uuid PK`, `referrer_trainer_id uuid FK`, `referred_trainer_id uuid FK unique`, `code_used text`, `status text CHECK (in 'signed_up','converted','rewarded')`, `converted_at`, `rewarded_at`
  - RLS: referral_codesは本人SELECT。referralsは referrer本人SELECT、書き込みはservice role。
- **バックエンド**: `/api/stripe/webhook` に紹介成立判定を追加（checkout metadataに `referral_code` を積む）。リワード付与は `invoice.paid` 初回時に処理。
- **通知設計**: 紹介成立時に紹介者へメール or Web Push（拡張）。
- **既存コードとの接続点**: 機能1-Aの `/api/stripe/checkout` と webhook（本機能は1-Aの上に載る。単独では成立しない）、`fit-connect/src/app/(auth)/signup/`
- **フェーズ分け**: MVP=Checkoutの `allow_promotion_codes: true` を有効化し運営発行の汎用クーポンコードのみ対応（実装ほぼゼロ）→ 拡張=トレーナー個別紹介コード＋リワード自動付与。
- **規模感**: MVPはS（数時間）、紹介プログラム全体はM
- **リスク・考慮事項**: 自己紹介（自分のコードで自分が契約）の不正防止、リワードの景表法（過大な景品類にならない設計）、コードのブルートフォース対策（推測困難な生成）。

---

## カテゴリ内の推奨着手順

1. **機能4-A（法務ページ＋同意）と clientsテーブルanonポリシー撤去** — 課金・LP公開・App Store審査すべての前提。金銭データを扱う前にセキュリティ負債を解消する。
2. **機能1-A（Stripe SaaS課金）** — `subscription_plan` の設計・Mobile側ゲートが既に受け入れ準備済みで、最小工数で「Proを売れる」状態になる。同時に機能5-AのMVP（`allow_promotion_codes`）を有効化。
3. **機能3-A（LP＋料金ページ）** — 課金開始と同時公開し獲得導線を作る。
4. **機能2-A（チケット価格＋未払い管理）** — 欠落migration（ticket_templates/ticket_subscriptions/client_notes）の固定化から着手し、トレーナーの日常業務への依存度を上げる。
5. **機能2-B（Stripe Connect決済代行）** — 2-Aのデータ基盤の上に構築し、将来のプラットフォーム手数料という第2収益源へ繋げる。
---

# カテゴリ4: スケジュール・予約 — 機能設計

> **調査で確認した前提（コード実読に基づく）**
> - Web `/schedule` のセッションD&D移動は**実装済み**（`fit-connect/src/components/schedule/CalendarView.tsx` L250 `handleDragEnd` → `updateSession({ id, session_date })`、@dnd-kit使用）。未実装なのは「空きセルへのドラッグ新規作成」「時間リサイズ」「休み一括入力」
> - `sessions` テーブル（`supabase/migrations/20251230131753_remote_schema.sql` L477）: `status` は `scheduled/confirmed/completed/cancelled` の4値CHECK制約。`requested` は無い
> - `trainer_schedules`（`supabase/migrations/20260216221905_create_trainer_schedules.sql`）: 曜日別・`UNIQUE(trainer_id, day_of_week)`。**特定日のオフ（休暇）を表すテーブルは無い**。クライアントSELECT用RLSは策定済み
> - Mobileには `lib/features/schedules/`（`trainer_schedule_model.dart` / `trainer_status_card.dart` / `trainer_schedule_provider.dart`）が既にあり、ホーム（`home_screen.dart` L58）に在席カード表示済み。**セッション表示は皆無**
> - モバイルFCMトークンの保存先は **`clients.fcm_token` / `trainers.fcm_token` カラム**（`fit-connect-mobile/lib/services/notification_service.dart` L214-220で確認。push_subscriptionsとは別系統）
> - FCM v1送信ロジックは `supabase/functions/parse-message-tags/index.ts`（L456前後、サービスアカウント認証・無効トークン処理込み）に内包 → **共通化して再利用可能**

---

## 課題1: クライアント側からの予約リクエスト機能がない

3アプローチを列挙。**推奨は A（空き枠提示型リクエスト＋トレーナー承認）**。信頼関係が前提のパーソナルトレーニングでは「即時確定」より「承認フロー」が事故が少なく、既存の手入力フローとも共存できる。

### A. 空き枠提示型 予約リクエスト（承認制）【推奨】
- **解決する課題**: 顧客がトレーナーの空き枠から候補を選んで送信 → トレーナーがワンタップ承認で `sessions` が確定。メッセージ往復の日程調整を1往復に圧縮する。
- **ユーザーストーリー**:
  - 顧客として、アプリからトレーナーの空いている日時を見て予約リクエストを送りたい
  - トレーナーとして、リクエストを通知で受け取り、Webから1クリックで承認/辞退したい
  - トレーナーとして、承認前に時間を微調整（15分ずらす等）して確定したい
- **機能仕様**:
  - **Mobile（新画面）**: `features/booking/` を新設。「予約」画面＝週送りの空き枠グリッド（trainer_schedules の稼働時間 − 既存sessions − オフ日 で算出）。枠タップ→時間・コメント入力→送信。ホームの「次回セッションカード」（課題2）から導線。リクエスト中は「承認待ち」バッジ表示、取り下げ可。
  - **Web（既存画面に追加）**: `/schedule` 上部に「予約リクエスト」バッジ付きインボックス（Popover）。承認＝`sessions` INSERT＋リクエストclosed、辞退＝理由選択（任意テキスト）。カレンダー上にも承認待ちをゴースト表示（点線枠）。修正承認は SessionModal を初期値付きで開く。
- **データモデル**: 新テーブル `session_requests`
  - `id uuid PK` / `client_id uuid FK` / `trainer_id uuid FK` / `requested_start timestamptz` / `duration_minutes int DEFAULT 60` / `message text` / `status text CHECK (pending/approved/declined/cancelled/expired)` / `created_session_id uuid FK sessions NULL` / `responded_at timestamptz` / `decline_reason text` / `created_at`
  - RLS: client は自分の行を SELECT/INSERT/UPDATE(cancelのみ)、trainer は自分宛の行を SELECT/UPDATE。**sessions へのクライアントINSERT権限は付与しない**（承認時にトレーナー権限でINSERT）のがこの分離テーブル案の利点
- **バックエンド**:
  - RPC `get_available_slots(p_trainer_id, p_from date, p_to date)`: trainer_schedules（稼働）− sessions（確定済）− trainer_days_off（課題4で新設）− pending中の自分以外のリクエスト、を30分粒度で返す
  - 二重予約防止: 承認時に `sessions` へ同時間帯の排他チェック（RPC `approve_session_request` 内でトランザクション処理）
  - `session_requests` INSERT webhook → トレーナーへ通知
- **通知設計**: リクエスト送信時→トレーナー（Web Push: `push_subscriptions` 経由＋`trainers.fcm_token`）。承認/辞退時→顧客（FCM）。parse-message-tags のFCM送信部を `supabase/functions/_shared/push.ts` に切り出して共用。
- **既存コードとの接続点**: `fit-connect/src/components/schedule/CalendarView.tsx`（ゴースト表示）、`SessionModal.tsx`（修正承認）、`fit-connect-mobile/lib/features/schedules/providers/trainer_schedule_provider.dart`（稼働時間取得の既存Provider流用）、`supabase/functions/parse-message-tags/index.ts`（FCM送信の共通化元）
- **フェーズ分け**: MVP=単一候補日時のリクエスト＋承認/辞退＋通知 → 拡張1=複数候補提示（第3希望まで）→ 拡張2=修正承認・自動期限切れ（48h）cron
- **規模感**: **L**（Mobile新画面＋Web承認UI＋RPC＋通知で2-3週）
- **リスク・考慮事項**: 空き枠公開はプライバシー上「自分のトレーナーのみ」に限定（RLS必須）。チケット残数0の顧客のリクエスト可否はトレーナー設定にする（残0でもリクエスト自体は許可がデフォルト）。審査リスクなし（決済を伴わない）。

### B. メッセージ内 日程調整カード（軽量版・代替案）
- **解決する課題**: 同上を既存メッセージ基盤の上で軽量に解決。トレーナーが候補3枠を提示するカードを送り、顧客がタップで1つ選ぶと確定。
- **ユーザーストーリー**: トレーナーとして、チャットで「この3枠どうですか」を構造化して送り、返信待ちの取りこぼしをなくしたい
- **機能仕様**: Web メッセージ画面に「日程候補を送る」ボタン→枠ピッカー→`messages.metadata jsonb` に `{type:'schedule_proposal', slots:[...]}` を格納して送信。Mobile側はメッセージバブルを専用ウィジェットでレンダリングし、タップで確定（`metadata.selected_slot` 更新）。確定時に Edge Function が `sessions` INSERT。
- **データモデル**: 新テーブル不要（`messages.metadata` 流用）。確定sessionへの参照のみ metadata に持つ。
- **バックエンド**: parse-message-tags（messages UPDATE webhook 済み）に `schedule_proposal` 分岐を追加して sessions 作成。
- **既存コードとの接続点**: `messages.metadata`（既存カラム）、`supabase/functions/parse-message-tags/index.ts`（UPDATE webhook 既存）、Mobile `features/messages/` のバブル描画
- **フェーズ分け**: これ自体が単発機能。A実装後は「トレーナー起点の逆方向提案」として共存可能
- **規模感**: **M**（1週弱）
- **リスク**: 顧客起点の予約はできない（トレーナー起点のみ）。恒久解はA。Aの前段の即効薬、またはAの拡張2として位置づけ。

### C. 即時確定予約（承認レス）
- **解決する課題**: 同上。承認ステップすら省き、空き枠タップで即 `sessions` 確定。
- **機能仕様**: Aの承認を自動化したもの。トレーナー設定に「自動承認を有効化」トグルを置き、Aの `approve_session_request` を webhook で自動実行するだけ。
- **フェーズ分け**: **Aの拡張3**として実装（独立機能にしない）。
- **規模感**: Aがあれば **S**
- **リスク**: 無断ダブルブッキングや「話してから決めたい」トレーナーの反発。デフォルトOFF必須。

---

## 課題2: Mobileにセッション予定の表示が薄い

### 次回セッションカード＋セッション一覧（Mobile）
- **解決する課題**: 顧客が「次のセッションはいつ」をホームで即確認でき、日程の聞き直しメッセージを削減。予約リクエスト（課題1）の入口にもなる。
- **ユーザーストーリー**:
  - 顧客として、ホームを開いたら次回セッションの日時・残り日数が見たい
  - 顧客として、今後の予定と過去のセッション履歴を一覧で見たい
  - 顧客として、都合が悪くなったら変更希望をすぐ出したい
- **機能仕様**:
  - **Mobile**: `features/sessions/` 新設。①ホームカード `next_session_card.dart` を `home_screen.dart` の TrainerStatusCard（L58）直下に追加（「7/10(金) 18:00 · あと3日」＋当日なら強調表示、予定なしなら「予約をリクエスト」CTA=課題1へ）。②タップで一覧画面（今後/過去のセグメント切替、status表示）。③各行に「変更を相談」ボタン→メッセージ画面へ定型文付き遷移（MVP）／session_requests の振替リクエスト（拡張）。
  - **Web**: 変更なし。
- **データモデル**: 新テーブル不要。**`sessions` にクライアント用RLSポリシー追加が必須**:
  - `CREATE POLICY "Clients can view own sessions" ON sessions FOR SELECT USING (client_id IN (SELECT id FROM clients WHERE client_id = auth.uid()));`（clients の auth紐付けカラム実装に合わせる。trainer_schedules の既存ポリシー流用パターン）
- **バックエンド**: 追加なし（PostgREST直読み）。Realtime購読を `sessions` に追加すればトレーナー側の変更が即時反映（拡張）。
- **通知設計**: 本機能では不要（課題3で対応）。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/home/presentation/screens/home_screen.dart`（カード挿入位置）、`features/schedules/`（命名整理: schedules=トレーナー稼働、sessions=セッションで分離）、`fit-connect-mobile/lib/shared/models/`（SessionModel新設）
- **フェーズ分け**: MVP=ホームカード＋一覧（読み取りのみ）→ 拡張=Realtime反映・変更/キャンセルリクエスト（課題1のsession_requestsに `type: reschedule` を追加）
- **規模感**: **S〜M**（RLS＋モデル＋カード＋一覧で2-3日）
- **リスク**: RLS追加時、既存のトレーナー用ポリシーと干渉しないか確認。**カテゴリ内で最も費用対効果が高く、他機能の土台になるため最優先**。

---

## 課題3: セッション前日リマインダーなし

### セッションリマインダー通知（cron + push）
- **解決する課題**: 前日・直前のリマインドで無断キャンセル・遅刻を防止。業界定番機能の不在を解消。
- **ユーザーストーリー**:
  - 顧客として、前日夜と当日に「明日18:00からセッション」の通知を受け取りたい
  - トレーナーとして、当日朝に本日のセッション一覧サマリを受け取りたい
- **機能仕様**:
  - 通知タイミング（トレーナー設定でON/OFF・時刻変更可、デフォルト有効）: ①前日20:00（顧客宛）②開始2時間前（顧客宛）③当日朝8:00 本日サマリ（トレーナー宛）
  - Mobile: 通知タップで次回セッションカード/一覧へディープリンク（`notification_service.dart` の既存タップ遷移ルーティングに `session` タイプを追加）
  - Web: `/settings` にリマインダー設定セクション追加
- **データモデル**:
  - `sessions` に `reminder_day_before_sent_at timestamptz` / `reminder_hours_before_sent_at timestamptz` を追加（冪等性担保。二重送信防止）
  - `trainers` に `reminder_settings jsonb DEFAULT '{"day_before":true,"hours_before":2,"daily_summary":true}'`
- **バックエンド**:
  - 新Edge Function `send-session-reminders`: 未送信×時間窓該当の sessions を抽出→ FCM（`clients.fcm_token`）へ送信→ sent_at 更新。**pg_cron + pg_net で15分毎に起動**（`auto-skip-workouts` と同じ cron 呼び出しパターン。cron設定がリポジトリ外なので、今回から `supabase/migrations/` に `cron.schedule` を含めて管理下に置くことを推奨）
  - FCM送信は課題1で切り出す `_shared/push.ts` を使用（無効トークンnull化処理も移設）
- **通知設計**: 上記の通り。顧客=FCM、トレーナー=Web Push＋FCM両方（在席していない時間帯のため）。
- **既存コードとの接続点**: `supabase/functions/parse-message-tags/index.ts`（FCM v1送信・サービスアカウントsecretの流用）、`supabase/functions/auto-skip-workouts/`（cron Edge Functionの先例）、`fit-connect-mobile/lib/services/notification_service.dart`（タップ遷移追加）
- **フェーズ分け**: MVP=前日20:00顧客宛のみ（固定時刻・設定なし）→ 拡張1=2時間前＋トレーナー朝サマリ → 拡張2=設定UI・時刻カスタマイズ
- **リスク・考慮事項**: タイムゾーンは現状JP前提でよいが `session_date` は timestamptz なのでUTC計算に注意。cron間隔15分だと「前日20:00」は±15分ずれる（許容範囲）。FCMコストは無料枠内。**MVPだけなら S、フル実装で M**。
- **規模感**: **S（MVP）/ M（フル）**

### （代替・補完）Mobileローカル通知によるリマインダー
- **解決する課題**: 同上をサーバーレスで。セッション一覧取得時に `flutter_local_notifications` の `zonedSchedule`（導入済みだが未使用）で端末側に予約。
- **機能仕様**: sessions 取得/変更検知のたびに端末内の通知スケジュールを張り替え。
- **フェーズ分け**: 単体では非推奨（アプリを長期間開かないと予定変更が反映されない・トレーナー宛通知が作れない）。**サーバー版の補完（オフライン耐性）として拡張2で追加**。
- **規模感**: **S**
- **リスク**: iOSのローカル通知上限（64件）は問題なし。二重通知の抑止設計（サーバー通知受信時にローカル側をキャンセル）が必要。

---

## 課題4: オフ日設定・トレーナーステータスがない

### オフ日・休暇管理 ＋ トレーナーステータス表示強化
- **解決する課題**: 「今日はオフ」「◯日まで休暇」を顧客ホームに表示し、返信が遅い不安と「返信しなきゃ」のトレーナー側ストレスを両方解消。オフ日は空き枠計算（課題1）とセッション作成のガードにも使う。
- **ユーザーストーリー**:
  - トレーナーとして、来週水曜と年末年始をオフに設定し、顧客に自動で伝わってほしい
  - 顧客として、ホームのトレーナーカードで「本日オフ・返信は明日」が見たい
  - トレーナーとして、オフ日にセッションを誤って入れそうになったら警告してほしい
- **機能仕様**:
  - **Web**: `/settings` に「稼働スケジュール」セクション新設（trainer_schedules の曜日×時間帯編集UI — 現状seed投入のみで編集UIが無いため合わせて作る）＋「オフ日」管理（単日/期間指定、理由ラベル: 休暇/研修/その他、繰り返しなし）。`/schedule` カレンダーにオフ日を灰色帯表示し、該当日へのセッション作成/D&Dドロップ時に確認ダイアログ。休み一括入力=カレンダー上で日ヘッダの複数選択→「選択日をオフにする」（課題5と共通UI）。
  - **Mobile**: 既存 `trainer_status_card.dart`（223行、現在はpresenceベースのオンライン/オフライン表示のみ）を拡張 — 優先順位: 手動ステータス > 本日オフ > 稼働時間外 > presence。「本日はオフです 🌴」「営業時間 10:00-19:00（現在時間外）」等。
  - **手動ステータス**: Web ヘッダにステータス切替（対応中/離席/オフ）＋一言メッセージ（「7/10まで休暇です」）。
- **データモデル**:
  - 新テーブル `trainer_days_off`: `id uuid PK` / `trainer_id uuid FK` / `start_date date` / `end_date date` / `reason text` / `note text` / `created_at`。RLS: trainer全操作、担当clientはSELECT（trainer_schedulesの既存ポリシーを踏襲）
  - `trainers` に `status text CHECK (available/away/off) DEFAULT 'available'` / `status_message text` を追加（`is_online/last_seen_at` は自動presence、こちらは手動宣言で役割分離）
- **バックエンド**: 追加なし。課題1の `get_available_slots` RPC が本テーブルを参照。オフ日と重なる既存セッションの検出クエリ（設定保存時に警告表示用）。
- **通知設計**: 任意拡張=オフ期間設定時に「担当顧客へお知らせメッセージを一斉送信しますか？」（messages INSERT で既存チャット経路に乗せる。新経路不要）。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/schedules/presentation/widgets/trainer_status_card.dart`（表示拡張）、`trainer_schedule_provider.dart`（days_off取得追加）、`fit-connect/src/components/schedule/CalendarView.tsx`（灰色帯＋ドロップガード）、`supabase/migrations/20260216221905_create_trainer_schedules.sql`（RLSパターン踏襲）
- **フェーズ分け**: MVP=trainer_days_off＋Web設定UI＋Mobileカード表示 → 拡張1=手動ステータス＋一言メッセージ → 拡張2=カレンダー一括入力・顧客一斉お知らせ
- **規模感**: **M**（1週）
- **リスク**: trainer_schedules が `UNIQUE(trainer_id, day_of_week)` で1日1枠制約 → 昼休み等の複数時間帯は将来UNIQUE解除のmigrationが必要になる点を認識しておく。プライバシー: 休暇理由は顧客に見せない（reasonは内部用、顧客表示は「オフ」のみ）。

---

## 課題5: D&Dセッション設定・休み一括入力UIがない（入力負荷）

### カレンダー直接操作の完成（ドラッグ作成・リサイズ・一括操作）
- **解決する課題**: D&D**移動**は実装済みのため、残りの「空き枠にドラッグして新規作成」「端ドラッグで時間変更」「複数日一括オフ」を足してカレンダー操作を完結させ、手入力回数を最小化する。
- **ユーザーストーリー**:
  - トレーナーとして、カレンダーの空きセルをドラッグして時間範囲を選び、そのままセッションを作りたい
  - トレーナーとして、セッションの下端をドラッグして60分→90分に変えたい
  - トレーナーとして、盆休みの5日間を範囲選択で一括オフにしたい
- **機能仕様**（すべてWeb `/schedule`）:
  - ①空セルのドラッグ範囲選択 → SessionModal を開始/終了時刻プリセットで起動（既存 `TimeSlotCell.tsx` に選択状態を追加）
  - ②`CalendarEvent.tsx` に下端リサイズハンドル → `duration_minutes` 更新（既存 `updateSession` 流用）
  - ③繰り返しセッション（`recurrence_group_id`）のD&D/リサイズ時に「この回のみ/以降すべて」ダイアログ（既存 `RecurrenceDeleteDialog.tsx` のパターン流用）
  - ④日ヘッダのShift+クリック複数選択 → 「選択日を一括オフ」（課題4の trainer_days_off へ一括INSERT）
  - ⑤コピー作成: Alt+ドラッグで既存セッションを複製（同一クライアントの翌週分作成が高速化）
- **データモデル**: 追加なし（課題4の trainer_days_off に依存）。
- **バックエンド**: 追加なし。繰り返し一括更新のみ RPC `update_recurring_sessions(group_id, from_date, delta)` を追加すると安全（N回のUPDATEをトランザクション化）。
- **通知設計**: 拡張として、確定済みセッションの日時変更時に顧客へFCM「セッションが7/10 18:00に変更されました」（課題3の `_shared/push.ts` 流用）。**変更通知はD&Dの多用と相性が悪いため、保存後3分のデバウンス or 明示的な「顧客に通知」トグルを付ける**。
- **既存コードとの接続点**: `fit-connect/src/components/schedule/CalendarView.tsx`（DndContext/handleDragEnd 既存 L678, L250）、`CalendarEvent.tsx`（useDraggable 既存）、`TimeSlotCell.tsx`、`SessionModal.tsx`、`RecurrenceDeleteDialog.tsx`、`fit-connect/src/lib/supabase/updateSession.ts`
- **フェーズ分け**: MVP=①ドラッグ作成 → 拡張1=②リサイズ＋③繰り返し分岐 → 拡張2=④一括オフ＋⑤複製＋変更通知
- **規模感**: **M**（各機能はS、合計で1週弱）
- **リスク**: dnd-kit はリサイズ非対応のためリサイズのみ自前実装（pointer events）。既存D&Dとのイベント競合に注意。モバイルSafari等のタッチ対応はWebがトレーナー専用（PC前提）なら優先度低。

---

## 課題6: 外部カレンダー連携（Google Calendar等）なし

3案列挙。**推奨は A→C の段階導入**。B（双方向同期）は審査・保守コストが重く、SaaS初期には過剰。

### A. ICSカレンダーフィード配信（読み取り専用エクスポート）【推奨MVP】
- **解決する課題**: FIT-CONNECTのセッションをGoogle/Apple/Outlookカレンダーに購読表示させ、「私用カレンダーに手で転記する」二重管理を半減（FIT-CONNECT→外部の方向）。
- **ユーザーストーリー**:
  - トレーナーとして、Googleカレンダーに全セッションが自動で出てきてほしい
  - 顧客として、自分のセッションだけiPhoneカレンダーに出したい
- **機能仕様**: Web `/settings` に「カレンダー連携」→「購読URLを発行」（`https://<project>.functions.supabase.co/calendar-feed?token=xxx`）。コピー/QR表示、再発行（旧URL失効）。Mobile設定画面にも同UI（顧客は自分のセッションのみのフィード）。
- **データモデル**: 新テーブル `calendar_feed_tokens`: `id uuid PK` / `user_id uuid` / `user_type text (trainer/client)` / `token text UNIQUE`（十分長いランダム値）/ `revoked_at timestamptz` / `created_at`。RLS: 本人のみ。
- **バックエンド**: 新Edge Function `calendar-feed`: token検証→sessions（trainerは全件＋オフ日、clientは自分の分）をiCal形式で生成して返す（`verify_jwt=false`、token認証。service roleで読む）。
- **通知設計**: 不要。
- **既存コードとの接続点**: `sessions` テーブル、`trainer_days_off`（課題4）、`fit-connect/src/app/settings/` 配下、Mobile `features/settings/`
- **フェーズ分け**: MVP=トレーナー用フィード → 拡張=顧客用フィード＋オフ日含める
- **規模感**: **S**（1-2日）
- **リスク**: URL漏洩=予定漏洩なので再発行導線とtoken失効を必ず用意。Googleカレンダーの購読更新は最長24h遅延（仕様として設定画面に明記）。OAuth審査・API規約リスクは**ゼロ**なのが最大の利点。

### B. Google Calendar API 双方向同期
- **解決する課題**: 同上の完全版。FIT-CONNECT⇄Googleの双方向で、Google側の私用予定も取り込める。
- **機能仕様**: Google OAuth（`calendar.events` スコープ）接続、sessions作成/変更/削除をGoogleへpush、Google側変更をwebhook（watch channel）で受信。
- **データモデル**: `external_calendar_accounts`（refresh_token暗号化保存、sync_token、channel_id等）＋ `sessions.external_event_id`。
- **バックエンド**: Edge Functions `google-oauth-callback` / `calendar-sync-push` / `calendar-webhook`、watch channelの7日毎更新cron。
- **フェーズ分け**: A・Cの後、有料プラン差別化機能として。
- **規模感**: **L**（3週超＋審査期間）
- **リスク**: **Googleのセンシティブスコープ検証（動画提出・プライバシーポリシー・場合によりCASAセキュリティ評価）が必要で、個人開発規模だと審査に数週間〜数ヶ月**。refresh_token管理のセキュリティ責任も重い。当面非推奨。

### C. 外部カレンダーの空き時間取り込み（busy取り込み・片方向）
- **解決する課題**: 私用予定がある時間を課題1の空き枠計算から除外し、「空いてると思って予約リクエストしたのに断られる」を防ぐ。
- **機能仕様**: トレーナーが自分のGoogle/iCloudカレンダーの**公開ICS URL**を設定画面に登録 → cronで定期fetchし busy時間帯をキャッシュ → `get_available_slots` が除外。イベント内容（タイトル）は保存せず時間帯のみ（プライバシー配慮）。
- **データモデル**: `external_busy_blocks`: `trainer_id` / `starts_at` / `ends_at` / `source_url_hash` / `synced_at`。トレーナーのみRLS、顧客には空き枠計算結果としてのみ露出。
- **バックエンド**: Edge Function `sync-external-busy`（pg_cron 1h毎、ICSパース）。
- **フェーズ分け**: 課題1のAが定着した後に。OAuth不要のICS方式で始め、需要が立てばBへ。
- **規模感**: **M**
- **リスク**: ICSのURL共有設定をユーザーに正しく案内する必要（Googleの「限定公開URL」）。同期遅延1h前提の設計。

---

## カテゴリ内の推奨着手順

1. **Mobileセッション表示（課題2, S〜M）** — RLS追加＋ホームカード。最小工数で顧客体験が目に見えて向上し、以降すべての土台（SessionModel・sessions RLS）になる
2. **セッションリマインダーMVP（課題3, S）** — FCM送信の `_shared/push.ts` 共通化と pg_cron 管理をここで確立。無断キャンセル対策として営業価値も高い
3. **オフ日・ステータス（課題4, M）＋ カレンダー操作完成（課題5, M）** — トレーナー側の入力負荷と「返信プレッシャー」を同時に解消。trainer_days_off は次の予約機能の前提条件
4. **予約リクエスト（課題1-A, L）** — 1〜3で整えた RLS・通知基盤・オフ日データの上に本命機能を載せる。即効薬が必要なら 1-B（日程調整カード, M）を先行投入
5. **ICSフィード（課題6-A, S）** — 独立性が高くいつでも差し込めるが、Google双方向同期（6-B）は審査コストが重いため当面見送り
---

# カテゴリ5: 記録・データの拡充 — 機能設計

---

## 課題A: 歩数・活動量・心拍が未連携（消費カロリー側の欠落）

### A-1. ヘルスケア活動量連携（歩数・アクティブカロリー・心拍のREAD拡張）【推奨】

- **解決する課題**: HealthKit/Health Connect連携を体重・睡眠から活動量へ拡張し、消費カロリー側を自動取得。カロリー収支計算の欠落半分を埋める。
- **ユーザーストーリー**:
  - 顧客として、iPhone/Apple Watchの歩数・消費カロリーが自動で記録されてほしい（手入力したくない）
  - トレーナーとして、顧客の日々の活動量（NEAT）を見て「摂取は守れているのに痩せない」原因を特定したい
  - 顧客として、ホームの「今日のまとめ」で歩数目標の達成度を見たい
- **機能仕様**:
  - Mobile: `health_repository.dart` に `getActivityData()` を追加（`STEPS` / `ACTIVE_ENERGY_BURNED` / `BASAL_ENERGY_BURNED` / `HEART_RATE`(安静時・平均) / `EXERCISE_TIME` をREAD、日次集計で返す）。`health_settings_screen.dart` に「活動量を同期」トグル追加。ホーム「今日のまとめ」に歩数・消費kcal行、記録タブ「サマリ」に活動量カード追加
  - Web: クライアント詳細サマリータブに歩数・消費カロリー表示、`/report` のKPIに平均歩数を追加
- **データモデル**: 新テーブル `activity_records`（`id uuid PK`, `client_id uuid FK→clients ON DELETE CASCADE`, `recorded_date date`, `steps int`, `active_energy_kcal numeric`, `basal_energy_kcal numeric`, `exercise_minutes int`, `resting_heart_rate int`, `avg_heart_rate int`, `source text CHECK IN ('healthkit','manual')`, `created_at/updated_at`, `UNIQUE(client_id, recorded_date)`）。RLSは `sleep_records`（`20260422000000_create_sleep_records.sql`）の5ポリシーパターン（本人CRUD＋担当トレーナーSELECT）をそのまま踏襲
- **バックエンド**: 追加なし（クライアント側upsertのみ）。拡張フェーズで日次集計RPC `get_activity_stats(client_id, from, to)`
- **通知設計**: MVPでは不要。拡張で「歩数目標達成」ローカル通知（任意）
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/health/data/health_repository.dart`（体重・睡眠と同じ取得パターン）、`fit-connect-mobile/lib/features/health/providers/health_sync_provider.dart`（`_syncWeight` L212 / `_syncSleep` L307 と並列で `_syncActivity` 追加、既存のフォアグラウンドTimer 1h + resume同期に相乗り）、`fit-connect/src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx`
- **フェーズ分け**: MVP=歩数＋アクティブカロリーの日次同期＋ホーム表示 → 拡張1=心拍・エクササイズ分・Web表示 → 拡張2=時間帯別グラフ
- **規模感**: M（〜1週）
- **リスク・考慮事項**: Android の Health Connect 権限は Google Play の申告フォーム提出が必要（審査1〜2週見込み、リリース計画に織り込む）。iOS は Info.plist の利用目的文言更新のみ。当日データは確定前で変動するため「当日は毎同期で上書き、過去日は確定値」ルールにする。Apple Watch 非所持ユーザーは消費kcalが iPhone 歩数由来のみで過小になる点を UI で注記

### A-2. カロリー収支ダッシュボード（摂取 vs 消費）【推奨・A-1後】

- **解決する課題**: A-1で取得した消費側と既存 `meal_records` の摂取kcalを突き合わせ、「収支計算の半分が欠落」を最終的に解決する統合ビュー。
- **ユーザーストーリー**:
  - トレーナーとして、顧客の週次カロリー収支（±kcal）を一目で見て指導コメントの根拠にしたい
  - 顧客として、今日「あとどれくらい食べられるか/動くべきか」を知りたい
- **機能仕様**:
  - Mobile: ホーム「今日のまとめ」に収支バー（摂取kcal − (基礎代謝+活動kcal)）。記録タブサマリに週次収支チャート
  - Web: クライアント詳細サマリータブに収支カード、`WeightNutritionChart.tsx` に消費カロリー系列を重ねる
- **データモデル**: 新テーブル不要。基礎代謝は `clients` の身長・年齢・性別からMifflin-St Jeor式で算出（`activity_records.basal_energy_kcal` があれば優先）
- **バックエンド**: RPC `get_energy_balance(client_id, from_date, to_date)`（meal_records合計 − activity_records合計を日別返却）
- **通知設計**: 不要
- **既存コードとの接続点**: `fit-connect/src/components/clients/WeightNutritionChart.tsx`、`fit-connect/src/utils/weightPrediction.ts`（収支トレンドを予測モデルの入力に使える）、`fit-connect-mobile/lib/features/home/`
- **フェーズ分け**: MVP=日次収支表示 → 拡張=週次収支と体重変化の相関表示・予測統合
- **規模感**: S〜M
- **リスク・考慮事項**: 摂取記録の抜け漏れ日は収支が大幅マイナスに見える → 食事記録3食未満の日は「参考値」表示にするなど誤解防止が必須

### A-3. 外部ウェアラブルAPI連携（Fitbit/Garmin/Terra等アグリゲータ）【非推奨・当面見送り】

- **解決する課題**: HealthKit経由で取れないWeb側直接取得やバックグラウンド完全同期を実現。ただしFitbit/Garmin データは端末のヘルスアプリ経由でも大半流れてくるためA-1と重複が大きい。
- **ユーザーストーリー**: 顧客として、アプリを開かなくてもウェアラブルのデータが同期されてほしい
- **機能仕様**: 設定画面に外部サービス接続（OAuth）、Webhook受信で自動記録
- **データモデル**: `wearable_connections`（client_id, provider, access_token暗号化, refresh_token, expires_at）＋ A-1と同じ `activity_records` へ書き込み（source列に 'fitbit' 等を追加）
- **バックエンド**: Edge Function `wearable-webhook`（受信・正規化）、トークンリフレッシュcron
- **通知設計**: 不要
- **既存コードとの接続点**: A-1のテーブルを共用
- **フェーズ分け**: A-1の効果検証後に需要があれば
- **規模感**: L（数週）
- **リスク・考慮事項**: Terra等アグリゲータは従量課金でランニングコスト増。Fitbit APIは審査あり。トークン保管のセキュリティ責務が発生。**A-1で90%のユースケースを賄えるため優先度低**

---

## 課題B: 食品DB検索・バーコードスキャンなし

### B-1. バーコードスキャン＋食品DB照合【推奨】

- **解決する課題**: 市販品の栄養入力をバーコード1スキャンで正確・高速化。AI推定（誤差あり・Pro限定・rate limit 50/日）への依存を減らす。
- **ユーザーストーリー**:
  - 顧客として、コンビニ商品はバーコードを読ませて正確なPFCで即記録したい
  - 顧客として、DBにない商品は今まで通りAI推定にフォールバックしてほしい
- **機能仕様**:
  - Mobile: `MealTagForm`（`structured_tag_form.dart` 内）にバーコードアイコン追加 → `mobile_scanner` パッケージでスキャン → 商品ヒット時は商品名・PFC/100gを表示し分量（g or 個数）入力 → 計算済みPFCを既存の `onSendWithEstimation` フローに載せて `#食事:*` タグ送信（`messages.metadata` に `barcode`, `product_name` を格納）
  - 未ヒット時: 「見つかりませんでした → 写真でAI推定 / 手入力」の分岐
- **データモデル**: 新テーブル `food_products`（`barcode text PK`, `name text`, `brand text`, `kcal_per_100g numeric`, `protein_g/fat_g/carbs_g per 100g`, `serving_size_g numeric`, `source text ('openfoodfacts','user','jfc')`, `raw jsonb`, `fetched_at timestamptz`）— 全クライアント共有キャッシュ。RLS: authenticated全員SELECT、INSERT/UPDATEはEdge Function（service role）経由のみ
- **バックエンド**: Edge Function `lookup-food-barcode`（①`food_products` キャッシュ照会 → ②ミス時 Open Food Facts API 照会 → 正規化してキャッシュupsert → 返却）。`parse-message-tags/index.ts` は変更不要（PFC込みで送信されるためAI推定と同経路）
- **通知設計**: 不要
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart`（MealTagForm）、`fit-connect-mobile/lib/features/meal_records/data/meal_estimation_api.dart`（APIクライアントの実装パターン踏襲）、`supabase/functions/estimate-meal-nutrition/index.ts`（Edge Functionの認証・ログパターン踏襲）
- **フェーズ分け**: MVP=スキャン→OFF照合→分量計算→送信 → 拡張1=未ヒット商品のユーザー登録（`source='user'`、共有キャッシュに蓄積）→ 拡張2=スキャン履歴からのワンタップ再記録
- **規模感**: M（〜1週）
- **リスク・考慮事項**: Open Food Facts は無料・ODbLライセンスだが**日本商品カバレッジが低い**（ヒット率5〜6割想定）→ 未ヒット時のフォールバックUXが体験の要。カメラ権限の利用目的文言（iOS/Android両方）。OFF APIのレート制限は緩いがキャッシュ必須。栄養表示由来データの正確性免責を利用規約に記載

### B-2. 食品名検索（日本食品標準成分表のローカルDB）

- **解決する課題**: バーコードのない生鮮・自炊・外食チェーン定番品を、AIを使わず名前検索で正確に記録できるようにする。
- **ユーザーストーリー**: 顧客として、「鶏むね肉 200g」「白米 150g」のような定番食材は検索して確定値で記録したい
- **機能仕様**: MealTagForm に検索フィールド追加 → インクリメンタル検索 → 品目選択 → 分量入力 → PFC計算 → B-1と同じ送信経路。複数品目をカートのように積んで1食として送信
- **データモデル**: 新テーブル `food_items`（`id`, `name text`, `name_kana text`, `category text`, `kcal/protein/fat/carbs per 100g`, `standard_serving_g`）に文科省「日本食品標準成分表2023（八訂増補）」約2,500品目をシードmigrationで投入。`pg_trgm` インデックスで曖昧検索
- **バックエンド**: RPC `search_food_items(query text, limit int)`（trgm類似度順）。Edge Function不要（直接SELECT可、RLSはauthenticated SELECTのみ）
- **通知設計**: 不要
- **既存コードとの接続点**: B-1と同じ `structured_tag_form.dart` / `meal_estimation_api.dart` の送信経路
- **フェーズ分け**: MVP=単品検索・記録 → 拡張=複数品目合成、外食チェーンメニューデータ追加
- **規模感**: M
- **リスク・考慮事項**: 成分表データは出典明記すれば利用可（文科省公表データ）。かな検索の precision 調整が必要。B-1より先にやるとAI推定との住み分け説明が複雑になるため B-1 とセットが望ましい

### B-3. マイ食品・よく食べる物のクイック追加

- **解決する課題**: 同じ物を繰り返し食べる顧客（プロテイン、定番弁当）の入力を1タップ化。DB検索やAI推定より速い経路を作る。
- **ユーザーストーリー**: 顧客として、毎朝のプロテインを「マイ食品」から1タップで記録したい
- **機能仕様**: MealTagForm 上部に「最近の記録」「マイ食品」チップ行。過去の `meal_records`（PFC入り）から頻度順サジェスト。記録済み食事の「マイ食品に保存」ボタン
- **データモデル**: 新テーブル `my_foods`（`id`, `client_id FK`, `name`, `kcal/protein/fat/carbs`, `barcode text nullable`, `use_count int`, `last_used_at`）。RLS本人CRUDのみ
- **バックエンド**: 追加なし
- **通知設計**: 不要
- **既存コードとの接続点**: `structured_tag_form.dart`（MealTagForm）、`fit-connect-mobile/lib/features/meal_records/`
- **フェーズ分け**: MVP=最近の記録からの再送 → 拡張=マイ食品テーブル・並び管理
- **規模感**: S〜M
- **リスク・考慮事項**: ほぼなし。UIの詰め込みすぎに注意（チップ行は折りたたみデフォルト）

---

## 課題C: AI推定の精度フィードバック機構なし

### C-1. 推定→修正差分ログの収集【推奨・最初にやる】

- **解決する課題**: ユーザーが確認ビューで修正した「AIの推定値 vs 確定値」の差分を保存し、精度改善ループの原資データを作る。現状は修正後値しか残らず学習材料が消えている。
- **ユーザーストーリー**:
  - （運営として）どのメニュー・どの入力モードで推定が外れるかを定量把握したい
  - 顧客として、修正作業が将来の精度向上に繋がると感じたい
- **機能仕様**: `meal_estimation_confirm_view.dart` で送信確定時、AI原値と確定値の両方をAPIへ渡す。UI変更は最小（挙動は不変）
- **データモデル**: `ai_estimation_logs` に列追加: `estimated jsonb`（AI原値: kcal/PFC/品目）, `confirmed jsonb`（確定値）, `was_corrected boolean`, `correction_magnitude numeric`（kcal差の割合）。既存のrate limitロジックには影響なし
- **バックエンド**: `estimate-meal-nutrition/index.ts` のログinsert箇所（L257以降）を拡張、または軽量Edge Function `log-estimation-feedback` を追加（確定はクライアント操作後のため後者が素直）
- **通知設計**: 不要
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart`、`fit-connect-mobile/lib/features/meal_records/data/meal_estimation_api.dart`、`supabase/functions/estimate-meal-nutrition/index.ts`、`supabase/migrations/20260502120300_create_ai_estimation_logs.sql`
- **フェーズ分け**: MVP=差分保存のみ → 拡張=修正率・平均誤差の内部集計SQL
- **規模感**: S（〜1日）
- **リスク・考慮事項**: `confirmed` jsonbに食事内容が入るため個人情報扱いに準じた保持期間ポリシーを決める（例: 180日で匿名化）

### C-2. クライアント別 few-shot 個別化（過去の修正例をプロンプト注入）

- **解決する課題**: C-1で貯めた修正例を推定時プロンプトに注入し、その顧客の食生活（自炊傾向・盛り付け量）に合わせて推定精度を実際に向上させる。
- **ユーザーストーリー**: 顧客として、使い込むほど自分の食事に対する推定が正確になってほしい（Proの継続価値）
- **機能仕様**: 挙動のみ変更。推定リクエスト時に当該クライアントの直近 `was_corrected=true` ログ上位3〜5件を「過去の推定と実際の値」としてsystem promptに追加
- **データモデル**: C-1のスキーマで完結。`ai_estimation_logs(client_id, was_corrected, created_at)` の部分インデックス追加
- **バックエンド**: `estimate-meal-nutrition/index.ts` にログ照会＋プロンプト組み立てを追加（モデル選択ロジックL61は不変）
- **通知設計**: 不要
- **既存コードとの接続点**: `supabase/functions/estimate-meal-nutrition/index.ts`
- **フェーズ分け**: MVP=テキスト推定のみfew-shot → 拡張=画像推定にも適用、効果A/B測定
- **規模感**: S〜M
- **リスク・考慮事項**: 入力トークン増によるAPIコスト微増（haiku主体なら軽微）。逆効果ケース（外れ例の注入で引きずられる）があるため修正幅の大きい例のみ選ぶ等のフィルタが必要

### C-3. トレーナーによる栄養値修正（Web側）

- **解決する課題**: プロの目で見て明らかにおかしい推定値をトレーナーが直せるようにし、記録の信頼性とフィードバックデータの質を両方上げる。
- **ユーザーストーリー**: トレーナーとして、顧客の食事記録のkcal/PFCが実態とズレている時にその場で修正したい
- **機能仕様**: Web クライアント詳細の食事タブ（`MealTab.tsx`）と `/message` 記録サイドパネルの食事カードに編集ボタン → PFC編集モーダル → 保存
- **データモデル**: `meal_records.ai_source` の値に `'trainer_corrected'` を追加（既存 `20260531000000_add_ai_source_to_meal_records.sql` のCHECK制約を確認・拡張）。修正差分はC-1の `ai_estimation_logs` へ `corrected_by='trainer'` として記録（列追加）
- **バックエンド**: 追加なし（RLSでトレーナーの担当クライアントmeal_records UPDATEポリシーが必要 — 現状クライアント本人のみの可能性が高く、migrationで追加）
- **通知設計**: 修正時に顧客へFCMプッシュ「トレーナーが食事記録を修正しました」（任意・拡張）
- **既存コードとの接続点**: `fit-connect/src/app/(user_console)/clients/[client_id]/_components/MealTab.tsx`
- **フェーズ分け**: MVP=Web編集＋ログ → 拡張=修正通知・修正履歴表示
- **規模感**: M
- **リスク・考慮事項**: トレーナー修正と顧客再修正の競合はupdated_at楽観チェックで十分。「勝手に書き換えられた」感を避けるため修正者バッジ表示を必ず付ける

---

## 課題D: スクショ取込の1日サマリー一括生成・過去日付記録

### D-1. 過去日付・時刻指定での記録作成（全記録タイプ共通）【推奨・先行実装】

- **解決する課題**: 「昨日の夕食を今朝記録する」ができない問題を解消。D-2（1日サマリー取込）の前提条件でもある。
- **ユーザーストーリー**:
  - 顧客として、記録し忘れた昨日の食事・体重を翌日に正しい日付で入れたい
  - トレーナーとして、記録が実際の日付に紐づいてレポート集計が正確であってほしい
- **機能仕様**: `StructuredTagForm` の各フォーム（Weight/Meal/Exercise）に日付チップ（デフォルト「今日」、タップでDatePicker、過去30日まで）。送信時 `messages.metadata` に `recorded_date` を格納。チャット上は「昨日分」バッジ表示
- **データモデル**: スキーマ変更なし（`messages.metadata jsonb` 既存、各recordsの `recorded_at` 既存）
- **バックエンド**: `parse-message-tags/index.ts` の `createMealRecord` / `createWeightRecord` / `createExerciseRecord` で `metadata.recorded_date` があれば `recorded_at` を上書き（webhookペイロード再取得でmetadataは取得済み: index.ts L46-49）
- **通知設計**: 不要
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart`、`supabase/functions/parse-message-tags/index.ts`
- **フェーズ分け**: MVP=食事・体重の過去日付 → 拡張=運動、記録タブからの日付セル長押しでの追記導線
- **規模感**: S〜M
- **リスク・考慮事項**: 体重は「日ごと最新1件」表示ロジックが複数ある（`health_repository.dart` のdedupと同思想）ため、過去日付挿入時の重複表示を各画面で確認。未来日付は禁止

### D-2. スクショ→1日分一括記録（複数食事の自動分解）【推奨】

- **解決する課題**: あすけん・カロミル等他アプリの「1日サマリー画面」スクショから朝昼夕間食を一括生成。バックログのv1スコープ外項目を解消し、他アプリからの乗り換えコストを下げる。
- **ユーザーストーリー**:
  - 顧客として、今使っている食事管理アプリの1日画面を1枚撮るだけで全食事を移したい
  - トレーナーとして、乗り換え初期でも顧客の食事データが途切れず見えてほしい
- **機能仕様**:
  - Mobile: MealTagFormに「1日まとめ取込」モード追加 → スクショ選択＋対象日付選択（D-1のUI流用）→ AI が食事タイプ別に分解した結果をアコーディオン表示（食事ごとに個別修正・除外可能）→ 確定で食事ごとに複数レコード生成
  - 送信形態: 1メッセージ（画像付き、`#食事:一括` タグ）＋ `metadata.meals[]` に全食事のPFC・タイプ・recorded_dateを格納
- **データモデル**: スキーマ変更なし（`meal_records` は既存構造のまま複数行生成、`message_id` は同一メッセージを共有参照）
- **バックエンド**: ① `estimate-meal-nutrition/index.ts` に `mode: 'daily_summary'` を追加（返却スキーマを `meals: [{meal_type, items, kcal, protein, fat, carbs}]` 配列に。画像なのでsonnet固定）② `parse-message-tags/index.ts` に `#食事:一括` 分岐を追加し `metadata.meals[]` から複数 `meal_records` をINSERT（UPDATE時の再生成・削除ロジックも配列対応）
- **通知設計**: 不要
- **既存コードとの接続点**: `supabase/functions/estimate-meal-nutrition/index.ts`（画像=sonnet分岐 L61）、`supabase/functions/parse-message-tags/index.ts`（createMealRecord L170付近）、`meal_estimation_confirm_view.dart`（複数食事対応に拡張）、`ai_estimation_logs`（rate limit消費は1回=1リクエストのまま）
- **フェーズ分け**: MVP=1日サマリースクショ→複数食事生成 → 拡張=複数日ぶんの連続取込ウィザード、体重・歩数もスクショから同時抽出
- **規模感**: M〜L
- **リスク・考慮事項**: 他アプリUIのスクショ解析はレイアウト変更で精度が揺れる → 「読み取れた分だけ表示し、ユーザー確認必須」の設計を崩さない。sonnet利用増でAPIコスト増（Pro限定・rate limit内で吸収）。他アプリの著作物（UI）を保存する点は私的利用の範囲だがStorage保持期間に留意

---

## 課題E: 期間統計の拡充

### E-1. 期間選択付き統計サマリー（平均・最大・最小・変化量）【推奨】

- **解決する課題**: 「今週/今月/過去3ヶ月の平均・最大値」が見られない問題を解消。体重・睡眠・食事kcal・（A-1後）歩数に共通の期間統計UIを提供。
- **ユーザーストーリー**:
  - 顧客として、記録タブで「今月の平均体重は先月より-0.8kg」を確認してモチベーションにしたい
  - トレーナーとして、クライアント詳細で期間を切り替えて平均摂取kcalや平均睡眠時間を確認したい
- **機能仕様**:
  - Mobile: 記録タブの各サブタブ（`weight_record_screen.dart` 等）と `records_overview_screen.dart` に期間セグメント（週/月/3ヶ月/カスタム）＋統計カード（平均・最大・最小・期間変化量・前期間比）
  - Web: クライアント詳細の各タブ（`WeightTab.tsx` / `MealTab.tsx` / `SleepTab.tsx`）に同等の統計ヘッダ、`/report` の期間比較テーブルに睡眠・活動指標を追加
- **データモデル**: スキーマ変更なし
- **バックエンド**: RPC `get_period_stats(p_client_id uuid, p_metric text, p_from date, p_to date)`（metric別にavg/max/min/first/last/countを1クエリで返す）。モバイルは既存の取得済みリストからクライアント集計でも可（MVPはクライアント集計、レコード数が増えたらRPC化）
- **通知設計**: 不要
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/records_overview/presentation/screens/records_overview_screen.dart`、`fit-connect-mobile/lib/features/weight_records/presentation/screens/weight_record_screen.dart`、`fit-connect/src/app/(user_console)/clients/[client_id]/_components/WeightTab.tsx`、`fit-connect/src/app/(user_console)/report/`
- **フェーズ分け**: MVP=体重・睡眠の期間統計（Mobile記録タブ）→ 拡張1=食事kcal/PFC平均、Web側 → 拡張2=前期間比・カスタム期間
- **規模感**: M
- **リスク・考慮事項**: 記録の欠測日が多い期間の平均は誤解を生む → 「記録◯日分の平均」と母数を常に併記

### E-2. 週平均体重トレンドライン（7日移動平均）

- **解決する課題**: 日々の水分変動（±1kg）に一喜一憂する問題を、週平均のなだらかなトレンド線で解消。減量指導の業界標準指標。
- **ユーザーストーリー**:
  - 顧客として、日単位のブレでなく「本当に減っているか」を線で見たい
  - トレーナーとして、週平均の傾きで摂取カロリー調整の判断をしたい
- **機能仕様**: Mobile体重チャートとWeb `WeightChart.tsx` に7日移動平均線を追加（実測点は薄く、トレンド線を主役に切替可能）。既存の体重予測（`weightPrediction.ts`）の入力を移動平均ベースに変更して予測の安定性も向上
- **データモデル**: スキーマ変更なし（クライアント側計算）
- **バックエンド**: 追加なし
- **通知設計**: 不要
- **既存コードとの接続点**: `fit-connect/src/components/clients/WeightChart.tsx`、`fit-connect/src/utils/weightPrediction.ts`、`fit-connect-mobile/lib/features/weight_records/presentation/screens/weight_record_screen.dart`（fl_chart）
- **フェーズ分け**: MVP=移動平均線の描画 → 拡張=予測モデルへの統合、週平均どうしの比較表示
- **規模感**: S
- **リスク・考慮事項**: ほぼなし。欠測日の補間方法（線形補間 or スキップ）を体重予測と揃えること

---

## 課題F: 水分・体脂肪率・筋肉量・周囲径の記録項目がない

### F-1. 体組成記録（体脂肪率・筋肉量を体重記録に統合）【推奨】

- **解決する課題**: パーソナルトレーニングの中核指標である体組成が記録できない問題を、既存の体重フローに乗せて最小コストで解消。「体重だけ」からの脱却の第一歩。
- **ユーザーストーリー**:
  - 顧客として、体組成計の体脂肪率・筋肉量を体重と一緒に記録したい
  - トレーナーとして、「体重横ばいでも体脂肪率低下＝成功」をグラフで示して顧客を安心させたい
  - 顧客として、体組成計がヘルスケアに書き込む体脂肪率は自動で同期されてほしい
- **機能仕様**:
  - Mobile: `WeightTagForm` に体脂肪率(%)・筋肉量(kg)の任意入力フィールド追加（タグ例: `#体重 65.2kg 体脂肪18.5% 筋肉量52.3kg`）。体重チャートに体脂肪率の第2軸系列。HealthKit同期に `BODY_FAT_PERCENTAGE` / `LEAN_BODY_MASS` をREAD追加し体重と同時upsert
  - Web: `WeightTab.tsx` に体脂肪率チャート・最新値カード追加
- **データモデル**: **新テーブルではなく `weight_records` に列追加**（`body_fat_percent numeric CHECK (0-75)`, `muscle_mass_kg numeric`）。体重と同時計測が実態でありHealthKitも同時刻で返すため同一行が自然。migrationはWeb型定義（`fit-connect/src/types/`）とMobileモデル（`fit-connect-mobile/lib/shared/models/`）の両方更新が必須（CLAUDE.mdルール）
- **バックエンド**: `parse-message-tags/index.ts` の `createWeightRecord` で体脂肪・筋肉量の正規表現抽出を追加（タグregex L132 は `体重` のまま変更不要）
- **通知設計**: 不要
- **既存コードとの接続点**: `supabase/functions/parse-message-tags/index.ts`（createWeightRecord）、`fit-connect-mobile/lib/features/health/data/health_repository.dart`（getWeightData拡張）、`fit-connect-mobile/lib/features/health/providers/health_sync_provider.dart`（_syncWeight L212）、`structured_tag_form.dart`（WeightTagForm）、`fit-connect/src/components/clients/WeightChart.tsx`
- **フェーズ分け**: MVP=手入力＋チャート → 拡張1=HealthKit同期 → 拡張2=体脂肪量(kg)換算・除脂肪体重トレンド
- **規模感**: M
- **リスク・考慮事項**: 家庭用体組成計のインピーダンス値は機種間差・日内変動が大きい → 「同じ機種・同じ時間帯で」のガイドをUIに。体脂肪率は要配慮情報に準じるためトレーナー以外に見えないRLS維持を確認

### F-2. 周囲径（メジャー計測）記録

- **解決する課題**: ウエスト・ヒップ等のガース計測（月次計測のパーソナル標準メニュー）が記録できない問題を解消。体重に表れない体型変化を可視化。
- **ユーザーストーリー**:
  - トレーナーとして、セッション時に計測したウエスト・二の腕をその場でWebから入力したい
  - 顧客として、ウエストの推移グラフで「体重停滞中もサイズダウンしている」ことを確認したい
- **機能仕様**:
  - Web（主入力者はトレーナー想定）: クライアント詳細に「計測」セクション（体重タブ内 or 新タブ）。日付＋各部位cm入力フォームと推移チャート・前回比
  - Mobile: 記録タブに計測カード（閲覧＋自己入力）。入力は `#計測` タグフォーム（`quick_action_bar.dart` の「その他」メニューに追加）
- **データモデル**: 新テーブル `body_measurement_records`（`id`, `client_id FK`, `recorded_date date`, `waist_cm`, `hip_cm`, `chest_cm`, `arm_cm`, `thigh_cm`, `calf_cm`, `neck_cm` 各numeric nullable, `note text`, `measured_by text CHECK ('client','trainer')`, `UNIQUE(client_id, recorded_date)`）。RLSは sleep_records の5ポリシー＋**トレーナーINSERT/UPDATEポリシー**を追加（トレーナーが入力主体のため）
- **バックエンド**: `parse-message-tags/index.ts` のタグregex（L132: `#(食事|運動|体重)`）に `計測` を追加し `createMeasurementRecord` を実装。Web側は直接INSERT
- **通知設計**: トレーナーが計測を入力したら顧客へFCM「今月の計測結果が記録されました」（拡張）
- **既存コードとの接続点**: `supabase/functions/parse-message-tags/index.ts`、`fit-connect-mobile/lib/features/messages/presentation/widgets/quick_action_bar.dart`、`fit-connect/src/app/(user_console)/clients/[client_id]/_components/`（新Tabコンポーネント）
- **フェーズ分け**: MVP=Webトレーナー入力＋チャート（ウエスト・ヒップのみ）→ 拡張=全部位・Mobile自己入力・前回比サマリー → 将来=バックログの進捗写真/3Dスキャンと同画面統合
- **規模感**: M
- **リスク・考慮事項**: 部位定義（おへそ位置か最細部か）で数値がブレる → 部位ごとの計測ガイド（イラスト）を添付。将来の進捗写真機能との画面統合を見越してタブ設計する

### F-3. 水分記録（クイック加算式）

- **解決する課題**: 水分摂取（減量・コンディショニングの基本指標）が記録できない問題を、1日複数回の入力に耐えるワンタップUIで解消。
- **ユーザーストーリー**:
  - 顧客として、コップ1杯飲むたびに+250mlをワンタップで積み上げたい
  - トレーナーとして、顧客の1日水分量が目標（例: 2L）に達しているか確認したい
- **機能仕様**:
  - Mobile: ホーム「今日のまとめ」に水分行（現在量/目標、＋250ml/＋500mlボタンでその場加算 — **メッセージを介さず直接upsert**。タグ経由だとチャットが水分メッセージで溢れるため）。記録タブサマリに日別バーチャート。目標量は設定画面で変更（デフォルト2,000ml）
  - Web: クライアント詳細サマリータブに水分行、食事タブに日別水分表示
- **データモデル**: 新テーブル `water_records`（`id`, `client_id FK`, `recorded_date date`, `amount_ml int`, `goal_ml int`, `UNIQUE(client_id, recorded_date)` — 日次合計を加算update方式）。RLSは sleep_records パターン
- **バックエンド**: 追加なし（クライアント直upsert）。拡張でHealthKit `WATER` READ同期を `health_sync_provider.dart` に追加
- **通知設計**: 拡張で「20時時点で目標の半分未満」ローカルリマインダー（任意ON）
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/home/`（今日のまとめ — 睡眠行統合と同パターン: commit 838d719）、`fit-connect-mobile/lib/features/health/providers/health_sync_provider.dart`（拡張時）
- **フェーズ分け**: MVP=加算ボタン＋日次合計＋今日のまとめ表示 → 拡張=HealthKit WATER同期・リマインダー・Web表示
- **規模感**: S〜M
- **リスク・考慮事項**: 記録疲れしやすい項目のため「全員に見せる」より設定でON/OFFできるオプトイン設計に。取り消し（−ボタン）を必ず用意

---

## カテゴリ内の推奨着手順

1. **D-1 過去日付記録（S）→ C-1 修正差分ログ（S）**: どちらも小粒で他機能（D-2, C-2）の前提。既存タグ基盤の薄い拡張で即効性が高い。
2. **F-1 体組成（M）→ E-1/E-2 期間統計・週平均（S〜M）**: 「体重しか見えない」問題を1〜2週で解消。新テーブル不要または最小のスキーマ変更で、トレーナーの指導価値（体脂肪率トレンド・週平均）が直接上がる。
3. **A-1 活動量連携（M）→ A-2 カロリー収支（S〜M）**: Health Connect審査のリードタイムがあるため早めに申請だけ先行。収支ダッシュボードは本プロダクトの差別化の核。
4. **B-1 バーコード＋B-3 マイ食品（M）**: AI推定と補完関係の入力高速化。D-2（スクショ一括）はB-1の後、乗り換え施策として実施。
5. **F-2 周囲径 / F-3 水分（M/S）**: 独立性が高く隙間で並行可能。F-2は将来の進捗写真機能とタブ設計を揃えておく。
---

# カテゴリ6: コミュニケーション — 機能設計

前提となる調査結果（実コード確認済み）:

- `supabase/functions/parse-message-tags/index.ts` には **FCM v1 送信実装が既に存在**し（サービスアカウントOAuth + `messages:send`）、`sendMessageNotification()` は `receiver_type` に応じて `clients.fcm_token` / **`trainers.fcm_token`** の両方を参照している（L508-561）。つまりサーバー側は「トレーナーへのFCM通知」に既に対応済み
- `fit-connect-mobile/lib/services/notification_service.dart` も userType 判定で `trainers.fcm_token` へトークンを保存する分岐を持つ（L214-220）。**モバイルアプリにトレーナーがログインすれば通知だけは今日でも動く設計**
- ただし `fcm_token` カラムは `supabase/migrations/` に CREATE/ALTER が見当たらない（スキーマドリフト。本番に手動追加された疑い）
- Web Push 送信は `fit-connect/src/app/api/push-notify/route.ts`（web-push + VAPID + X-API-Key）だが、**src内・mobile内・Edge Function内のどこからも呼ばれていない**（呼び出し元は `.next` 生成物のみヒット）。実質デッドコードか、外部から直接叩かれている可能性あり。要棚卸し
- 添付は `message-photos` バケットのみ（`20260102075114_create_message_photos_bucket.sql`、5MB、public read）
- `workout_exercises`（`20260221000000_create_workout_tables.sql`）は `name/target_sets/target_reps/memo/sort_order` のみで、メディア列なし

---

## 課題1: トレーナーへの通知経路がWeb Pushのみ

アプローチは4つ。**推奨: 1-A（LINE通知）を先行、1-C（トレーナーモード）を中期本命**。1-B（メール）は保険として安価に併設。1-D（Web Push改善）は棚卸しのみ。

### 1-A. LINE通知連携（トレーナー向け）【推奨・先行】

- **解決する課題**: PCを開いていないトレーナーに、日本で最も確実に届く経路（LINE）で新着メッセージを即時通知する。
- **ユーザーストーリー**:
  - トレーナーとして、外出中でも顧客からのメッセージにLINEで気づき、返信遅延で信頼を落とさないようにしたい。
  - トレーナーとして、通知のON/OFFと時間帯（深夜は止める等）を設定したい。
- **機能仕様**:
  - Web `/settings` の `NotificationSection.tsx` に「LINE通知」ブロックを追加。FIT-CONNECT公式LINEアカウントの友だち追加QR + アカウント連携（LINE Login の `link` フロー or ワンタイムコード入力）で `trainers.line_user_id` を紐付け。
  - 通知内容: 「{顧客名}から新着メッセージ: 本文冒頭50字」+ Webメッセージ画面へのリンク。
  - 通知条件: 受信者がトレーナーのメッセージINSERT時。オンライン在席中（`trainers.is_online = true`）は抑制するオプション。
- **データモデル**:
  - `trainers` に `line_user_id text`, `line_notify_enabled boolean default false`, `notify_quiet_hours jsonb`（例 `{"start":"22:00","end":"7:00"}`）を追加。
  - `line_link_codes`（`code text pk, trainer_id uuid, expires_at timestamptz`）— 連携用ワンタイムコード。
- **バックエンド**:
  - `parse-message-tags/index.ts` の `sendMessageNotification()` に分岐追加: `receiver_type === 'trainer'` かつ `line_user_id` ありなら LINE Messaging API `push` を送信（FCMと並列）。
  - 新Edge Function `line-link-webhook`: 公式アカウントへのコード送信を受けて紐付け（レガシー `/api/line/webhook` は流用せず新設。旧LIFFコードは別途削除対象）。
- **通知設計**: トレーナーへ・顧客メッセージINSERT直後・LINE Push。quiet hours内はスキップ（または朝にまとめ送信）。
- **既存コードとの接続点**: `supabase/functions/parse-message-tags/index.ts`（送信フック集約点）、`fit-connect/src/components/settings/NotificationSection.tsx`、レガシー `fit-connect/src/app/api/line/webhook` と `lineService`（参考実装・要整理）。
- **フェーズ分け**: MVP=紐付け+新着メッセージ通知のみ → 拡張=quiet hours、記録未提出アラート等の通知種別追加。
- **規模感**: M（3-4日）
- **リスク・考慮事項**: LINE Notifyは2025年3月終了済みのため **Messaging API一択**。無料枠は月200通/アカウントなので、通知量が増えたらライトプラン（月5,000通・5,000円）へ。トレーナー数×受信数で試算必須。LINEアカウントBAN時の代替経路としてメール併設が望ましい。

### 1-B. メール未読ダイジェスト通知

- **解決する課題**: 即時性は低いが確実・無料枠が広い経路として、未読メッセージの取りこぼしを防ぐ。
- **ユーザーストーリー**: トレーナーとして、30分以上未読の顧客メッセージがあればメールで知りたい。
- **機能仕様**: 「未読があり、かつ最終通知から30分経過」でメール送信（連投抑制のためダイジェスト形式: 「3名から5件の未読」）。`/settings` にON/OFF。
- **データモデル**: `trainers` に `email_notify_enabled boolean`, `last_email_notified_at timestamptz`。
- **バックエンド**: 新Edge Function `notify-unread-digest` + pg_cron（15分毎）。既存RPC `get_unread_counts_for_trainer` をトレーナー横断版に拡張して未読集計。送信は Resend（月3,000通無料）。
- **通知設計**: トレーナーへ・未読30分経過時・メール。1時間に1通まで。
- **既存コードとの接続点**: RPC `get_unread_counts_for_trainer`、`messages.read_at`。
- **フェーズ分け**: MVP=固定閾値30分 → 拡張=閾値カスタマイズ、日次サマリーメール。
- **規模感**: S（1日）
- **リスク・考慮事項**: メールはSPF/DKIM設定必須。ドメイン未取得なら先に必要。

### 1-C. トレーナーモード（既存Flutterアプリにトレーナーログイン追加）【中期本命】

- **解決する課題**: 通知経路問題を根本解決し、外出先での返信まで完結させる。「このアプリがないと仕事にならない」ビジョンに最も寄与。
- **ユーザーストーリー**:
  - トレーナーとして、スマホのネイティブプッシュで新着に気づき、その場で返信したい。
  - トレーナーとして、移動中に今日のセッション予定と顧客の今朝の記録を確認したい。
- **機能仕様**:
  - `fit-connect-mobile` にトレーナーロールでのログインを許可し、専用の縮小UI（v1は2タブ: 顧客リスト付きメッセージ / 設定）を出し分け。記録閲覧はメッセージ内の既存 RecordCard 相当で代替。
  - FCMトークン保存・受信通知は `notification_service.dart` と `parse-message-tags` が既に対応済みのため、**新規開発の中心はUIのみ**。
- **データモデル**: 追加なし。ただし**先に `trainers.fcm_token` / `clients.fcm_token` のmigrationを起こしてスキーマドリフトを解消すること**（現状リポジトリに定義が無い）。
- **バックエンド**: 変更ほぼなし（通知は既存Edge Functionが送る）。トレーナー用RLS（messages/clientsは既存ポリシーで可、要検証）。
- **通知設計**: トレーナーへ・メッセージINSERT時・FCM（既実装）。タップで該当顧客のチャットへディープリンク（`notification_service.dart` のタップ遷移拡張）。
- **既存コードとの接続点**: `fit-connect-mobile/lib/services/notification_service.dart`（trainers分岐 L214-220, L309-310）、`supabase/functions/parse-message-tags/index.ts` L508-561、`fit-connect-mobile/lib/features/messages/`（チャットUI流用）。
- **フェーズ分け**: MVP=ログイン+顧客一覧+チャット+プッシュ → 拡張=スケジュール閲覧、在席トグル、記録閲覧タブ。
- **規模感**: L（2-3週）
- **リスク・考慮事項**: 1アプリ2ロールはUX複雑化リスク（起動時ロール判定を確実に）。App Store審査は既存アプリの機能追加なので低リスク。`fcm_token` が単一カラムのため複数端末非対応（トレーナーはPC+スマホ併用が濃厚。将来 `device_tokens` テーブル化を検討）。

### 1-D. Web Push経路の棚卸し・修理

- **解決する課題**: 現状「Web Pushのみ」とされるが、`/api/push-notify` の呼び出し元が見当たらず**実際には何も届いていない疑い**がある。まず事実確認と修理。
- **機能仕様**: 呼び出し元調査 → 死んでいれば `parse-message-tags` から Web Push も送るよう統合（通知送信を1箇所に集約）。iOS/Android のモバイルブラウザPWAプッシュ対応（ホーム画面追加ガイド表示）も検討。
- **既存コードとの接続点**: `fit-connect/src/app/api/push-notify/route.ts`、`fit-connect/public/sw.js`、`push_subscriptions` テーブル、`savePushSubscription.ts`。
- **規模感**: S（半日〜1日）
- **リスク**: PUSH_API_KEY 未設定だと認証スキップになる実装（route.ts L16-22）。統合時にservice_role経由に整理すべき。

---

## 課題2: 一斉送信・配信機能なし

アプローチ: 2-A（即時一斉送信）が本体、2-B（予約配信）は同じ基盤の拡張。**推奨: 2-A → 2-B の順で同一テーブル設計に載せる**。

### 2-A. ブロードキャストメッセージ（一斉送信）【推奨】

- **解決する課題**: 全顧客への休業案内・キャンペーン告知等を1回の操作で配信できるようにする。
- **ユーザーストーリー**:
  - トレーナーとして、年末年始の休業案内を全顧客に一度で送りたい。
  - トレーナーとして、「チケット残1回以下の顧客」だけに更新案内を送りたい。
  - 顧客として、一斉送信でも通常のメッセージと同じ場所で受け取り、返信もそのままできてほしい。
- **機能仕様**:
  - Web `/message` に「一斉送信」ボタン → モーダルで宛先選択（全員/個別チェック/フィルタ: チケット残数・最終セッション日）+ 本文 + 画像 → 送信。
  - 実体は**各顧客の `messages` 行として個別INSERT**する方式（配信専用チャネルは作らない）。これにより既存のRealtime購読・FCM通知・未読管理・既読が一切改修なしで動く。
  - 送信済み一覧画面（誰に送って誰が既読か）をモーダル内タブで表示。
  - Mobile側は改修ゼロ（通常メッセージとして届く）。バブルに「一斉送信」バッジを出すなら `messages.metadata` に `{"broadcast_id": ...}` を入れて `message_bubble.dart` で判定（拡張）。
- **データモデル**:
  - `broadcasts`: `id uuid pk, trainer_id uuid, content text, image_urls text[], filter jsonb, recipient_count int, created_at`。RLS: trainer本人のみ全操作。
  - `messages.metadata` に `broadcast_id` を格納（カラム追加不要、既存jsonb活用）。
- **バックエンド**: 新Edge Function `send-broadcast`（service_role で対象顧客を解決し `messages` へバルクINSERT。50件ずつチャンク）。INSERTにより既存 `parse-message-tags` webhook が発火して顧客FCM通知も自動で飛ぶ（**タグ解析はスキップさせるため metadata に `skip_tag_parse` フラグを入れ、webhook側で早期return を追加**）。
- **通知設計**: 各顧客へ・送信時・FCM（既存経路に相乗り）。
- **既存コードとの接続点**: `fit-connect/src/lib/supabase/sendMessage.ts`（単発送信の型を流用）、`supabase/functions/parse-message-tags/index.ts`（webhook発火とスキップ判定）、`fit-connect/src/components/message/`（モーダル新設）。
- **フェーズ分け**: MVP=全員/個別選択+テキストのみ → 拡張=フィルタ条件、画像添付、既読率表示。
- **規模感**: M（3-4日）
- **リスク・考慮事項**: 顧客数が多いトレーナーでFCM送信がwebhook毎に走る（1通/INSERT）。100人規模までは問題ないが、レート制御をEdge Function側に用意。誤爆防止に送信前確認ダイアログ（宛先数明示）必須。

### 2-B. 予約配信・繰り返し配信

- **解決する課題**: 「明朝8時に送りたい」「毎週月曜に週初めの声かけ」を自動化し、一斉送信を定型業務にまで拡張する。
- **ユーザーストーリー**: トレーナーとして、日曜夜に書いた案内を月曜朝8時に予約配信したい。
- **機能仕様**: 2-Aのモーダルに「予約日時」「繰り返し（毎日/毎週X曜）」を追加。予約一覧・取消UI。
- **データモデル**: `broadcasts` に `scheduled_at timestamptz`, `recurrence text`（'none'/'daily'/'weekly:1'）, `status text`（'draft'/'scheduled'/'sent'/'cancelled'）を追加。
- **バックエンド**: pg_cron（5分毎）→ Edge Function `process-scheduled-broadcasts`（`status='scheduled' and scheduled_at <= now()` を送信）。`auto-skip-workouts` と同じcron運用パターン。
- **既存コードとの接続点**: `supabase/functions/auto-skip-workouts`（cron実装の参照）。
- **フェーズ分け**: MVP=1回限りの予約 → 拡張=繰り返し。
- **規模感**: S-M（2日、2-Aの上に載せる前提）
- **リスク**: cron設定がリポジトリ外にある既存問題と同根。cron定義をmigration化して管理下に置くこと。

---

## 課題3: メッセージテンプレート/定型文なし

アプローチ: 3-A（テンプレート管理+差し込み）が本体。3-B（自動声かけ）は2-Bと合流。**推奨: 3-A**。

### 3-A. メッセージテンプレート【推奨】

- **解決する課題**: 毎朝の声かけ・セッション前日リマインド等の定型文を保存・即呼び出しにし、手打ち業務を削減する。
- **ユーザーストーリー**:
  - トレーナーとして、「おはようございます、{name}さん。今朝の体重記録をお願いします」を2タップで送りたい。
  - トレーナーとして、テンプレートをカテゴリ（挨拶/リマインド/フォロー）で整理したい。
- **機能仕様**:
  - Web `/message` のチャット入力欄横にテンプレートアイコン → ポップオーバーで一覧（検索・カテゴリタブ）→ 選択で入力欄に挿入、`{{name}}` は選択中顧客名に自動置換して編集可能な状態にする（即送信はしない）。
  - 管理UI: `/settings` に「テンプレート管理」セクション（CRUD、並び替え）。
  - 2-Aの一斉送信モーダルからも同じピッカーを呼べるようにする（`{{name}}` は受信者ごとに展開）。
- **データモデル**: `message_templates`: `id uuid pk, trainer_id uuid, title text, body text, category text, sort_order int, usage_count int default 0, created_at, updated_at`。RLS: `trainer_id = auth.uid()` のみ全操作。
- **バックエンド**: 追加なし（通常のCRUD）。初回導入時にデフォルトテンプレート5-6本をseed。
- **通知設計**: 不要。
- **既存コードとの接続点**: `fit-connect/src/components/message/` のチャット入力コンポーネント（ChatHeader.tsx と同階層に TemplatePicker.tsx 新設）、`fit-connect/src/lib/supabase/sendMessage.ts`。Zustandに templateStore 追加。
- **フェーズ分け**: MVP=CRUD+挿入+`{{name}}`のみ → 拡張=変数追加（`{{next_session_date}}`, `{{weight_diff}}`）、使用回数順ソート、一斉送信連携。
- **規模感**: S-M（2日）
- **リスク・考慮事項**: 変数展開の失敗時（データ欠損）はプレースホルダーを残して送信前に気づける設計に。テンプレ乱用で機械的な印象にならないよう「送信前に必ず編集可能」をUX原則とする。

### 3-B. 定型メッセージの自動送信（モーニングルーティン）

- **解決する課題**: 「毎朝の声かけ」を完全自動化する（テンプレート×予約配信の合成）。
- **ユーザーストーリー**: トレーナーとして、平日朝7時に記録リマインドを担当顧客全員へ自動送信したい。
- **機能仕様**: 2-Bの繰り返し配信で `template_id` を指定できるようにするだけ（`broadcasts.template_id uuid` 追加）。送信時にテンプレを展開。
- **フェーズ分け**: 2-B・3-A完了後の統合タスク。
- **規模感**: S（1日）
- **リスク**: 自動送信は既読無視されやすく通知疲れを招く。頻度上限（1日1本）とトレーナーへの効果表示（返信率）を検討。

---

## 課題4: 音声メッセージ・動画添付なし

アプローチ: 4-A（動画添付）が本命（フォーム指導の本丸）、4-B（音声メッセージ）は補完。**推奨: 4-A先行**。前提整備として新バケットは private + signed URL とする（既存バケットの public read 問題を繰り返さない）。

### 4-A. メッセージ動画添付【推奨】

- **解決する課題**: フォーム指導・フォームチェックを動画でやり取り可能にする。顧客が自分のフォームを撮って送り、トレーナーが添削動画を返す双方向を実現。
- **ユーザーストーリー**:
  - 顧客として、スクワットの自撮り動画を送ってフォームを見てもらいたい。
  - トレーナーとして、お手本動画を撮ってその場で送りたい。
- **機能仕様**:
  - Mobile: `chat_input.dart` の添付メニューに「動画」追加（カメラ撮影/ライブラリ選択、`video_compress` で720p圧縮、最大60秒・目安50MB）。`message_bubble.dart` にサムネイル+再生ボタン → タップでフルスクリーン再生（`video_player` + `chewie`）。アップロード中プログレス表示。
  - Web: `ImageUploader.tsx` を `MediaUploader.tsx` に拡張（video/mp4, video/quicktime 受付）。`MessageBubble.tsx` に `<video>` プレビュー。
- **データモデル**:
  - 新バケット `message-videos`: **private**, `file_size_limit 52428800`（50MB）, mime `video/mp4, video/quicktime`。RLS: 参照は当事者（送信者/受信者）のみ、書き込みは自フォルダのみ。
  - `messages` に `video_urls text[]`（または既存 `image_urls` を `attachments jsonb`（`[{type:'video', path, thumb, duration}]`）へ発展。**推奨は `attachments jsonb` 新設**（音声も同枠に載る）。
- **バックエンド**: サムネイル生成が必要なら Edge Function は重いので、**クライアント側でサムネイルJPEGを生成し同時アップロード**（Flutter: `video_thumbnail`、Web: canvas）。`parse-message-tags` は `content` 空+attachmentsのみのメッセージでタグ解析をスキップするよう防御追加。
- **通知設計**: 既存FCM/新設トレーナー通知に「動画が届きました」文言分岐。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/messages/presentation/widgets/chat_input.dart`, `message_bubble.dart`, `data/message_repository.dart`、`fit-connect/src/components/message/ImageUploader.tsx`, `MessageBubble.tsx`, `ImageModal.tsx`、`supabase/migrations/20260102075114_create_message_photos_bucket.sql`（バケット定義の雛形）。
- **フェーズ分け**: MVP=撮影/選択→圧縮→送信→再生（両プラットフォーム受信対応、送信はMobile優先） → 拡張=Web側送信、動画上へのペン注釈・スロー再生（フォーム添削ツール化）。
- **規模感**: M-L（1-1.5週）
- **リスク・考慮事項**: ストレージコスト（Supabase Pro 100GB超過分 $0.021/GB/月。60秒720p ≒ 20-40MB。顧客100人×月10本で最大40GB/月増）→ 保持期間ポリシー（例: 90日で削除するcron）を初期から設計。private化に伴い表示は署名URL（有効1h、クライアントでキャッシュ）。App Store審査影響なし（1:1のUGCでモデレーション要件は軽微だが、利用規約に不適切コンテンツ条項を追加推奨）。

### 4-B. 音声メッセージ

- **解決する課題**: 「文字を打つのが面倒」なトレーナーの移動中返信、ニュアンス伝達を解決。動画より軽い指導手段。
- **ユーザーストーリー**: トレーナーとして、移動中に30秒の音声で励ましを送りたい。
- **機能仕様**: Mobile: `chat_input.dart` に長押し録音ボタン（`record` パッケージ、AAC/m4a、最大120秒）。バブルに再生UI（`just_audio`、再生速度1x/1.5x/2x）。Web: MediaRecorder API で録音（拡張フェーズ）、再生は `<audio>`。
- **データモデル**: 4-Aの `attachments jsonb` に `{type:'audio', path, duration}`。バケットは `message-videos` を `message-media` に改名して共用（private, mime に audio/mp4, audio/aac 追加）。
- **バックエンド**: 追加なし。
- **通知設計**: 「音声メッセージが届きました（0:32）」。
- **既存コードとの接続点**: 4-Aと同一。
- **フェーズ分け**: MVP=Mobile録音・両側再生 → 拡張=Web録音、波形表示、文字起こし（Whisper等、コスト次第）。
- **規模感**: M（3-5日、4-Aの基盤の上）
- **リスク**: マイク権限の説明文言（Info.plist / AndroidManifest）追加でストア審査時に用途説明必要。トレーナーがモバイルを持たない現状では送信側がWeb必須になる点に注意（1-C とセットで価値最大化）。

---

## 課題5: 宿題ワークアウトへの解説動画添付なし

アプローチ3つ。**推奨: 5-A（URL添付）で即日解決 → 5-B（種目ライブラリ）で資産化**。5-C（自前ホスティング）は5-Bの格納先オプションとして吸収。

### 5-A. 種目への参考URL添付（最速MVP）【推奨・先行】

- **解決する課題**: YouTube限定公開等の既存動画URLを種目に貼るだけで「テキストだけでフォームが分からない」を最短で解消。
- **ユーザーストーリー**:
  - トレーナーとして、自分のYouTube限定公開のお手本動画URLを種目に添付したい。
  - 顧客として、ワークアウト実行画面から1タップでお手本動画を見たい。
- **機能仕様**:
  - Web: `PlanFormModal` の種目行に「参考URL」入力欄を追加。
  - Mobile: `workout_screen.dart` の種目カードに「お手本を見る」ボタン → YouTube/URLなら外部ブラウザ or アプリ内WebView で開く。
- **データモデル**: `workout_exercises` に `reference_url text` を追加（1本のALTER migration）。
- **バックエンド**: 追加なし。
- **既存コードとの接続点**: `supabase/migrations/20260221000000_create_workout_tables.sql`（現行スキーマ）、`fit-connect-mobile/lib/features/.../workout_screen.dart`、Web `PlanFormModal` / `ExerciseListModal`。Mobileの `workout_exercises` モデル（`fit-connect-mobile/lib/shared/models/`）とWeb型（`fit-connect/src/types/`）の両方更新（CLAUDE.mdルール）。
- **フェーズ分け**: これ自体がMVP。5-Bへの布石。
- **規模感**: S（1日）
- **リスク**: YouTube埋め込みは規約上問題なし（外部起動なら尚更）。リンク切れ検知はしない割り切り。

### 5-B. 種目ライブラリ（動画付き種目マスタ）【本命】

- **解決する課題**: 種目ごとに動画・説明・注意点を一度登録すれば全顧客・全プランで再利用でき、プラン作成の速度と指導品質を同時に上げる。既存バックログの「ワークアウト種別分け」「宿題動画添付」と合流。
- **ユーザーストーリー**:
  - トレーナーとして、よく使う30種目を動画付きで登録し、プラン作成時は選ぶだけにしたい。
  - 顧客として、種目名タップで動画+ポイント解説をアプリ内で見たい。
- **機能仕様**:
  - Web: `/settings` または `/schedule` 配下に「種目ライブラリ」管理画面（種目名/カテゴリ/動画アップロード or URL/説明/注意点）。`ExerciseListModal`・`TemplatePanel` をライブラリ参照に接続し、プラン作成時に種目を選ぶと動画が自動で紐づく。
  - Mobile: `workout_screen.dart` の種目タップで解説シート（動画プレーヤー+説明文+注意点）。
- **データモデル**:
  - `exercise_library`: `id uuid pk, trainer_id uuid, name text, category text, video_url text, video_type text('upload'/'youtube'), thumbnail_url text, description text, cautions text, is_archived boolean, created_at, updated_at`。RLS: 書き込みはtrainer本人、SELECTは本人+担当顧客（`clients.trainer_id` 経由）。
  - `workout_exercises` に `library_exercise_id uuid references exercise_library(id)` を追加（`name` は非正規化コピーで残し、ライブラリ削除に耐える）。
  - 新バケット `exercise-videos`: private, 100MB, video/mp4。顧客への配信は署名URL。
- **バックエンド**: 追加なし（署名URL発行はクライアントSDKで可）。動画圧縮はアップロード前にクライアント側。
- **通知設計**: 不要。
- **既存コードとの接続点**: Web `PlanFormModal` / `TemplatePanel` / `ExerciseListModal`、`fit-connect-mobile/.../workout_screen.dart`、`workout_assignments/workout_exercises` スキーマ。
- **フェーズ分け**: MVP=ライブラリCRUD+YouTube URLのみ+Mobile解説シート → 拡張=動画アップロード（4-Aの動画基盤流用）、カテゴリ/検索、プリセット種目集の提供（初期データ）。
- **規模感**: L（2週。ただしMVPをURL限定にすればM=1週）
- **リスク・考慮事項**: 自前ホスティング動画のストレージコストは4-Aと同様（ライブラリは本数有限なのでチャット添付より軽い）。プリセット種目集を運営が提供する場合、動画の権利処理（自社撮影 or ライセンス素材）が必要。Pro プラン限定機能にして `subscription_plan` で出し分ける選択肢あり（収益化レバー）。

---

## カテゴリ内の推奨着手順

1. **5-A 種目URL添付（S）+ 1-D Web Push棚卸し（S）+ 1-B メールダイジェスト（S）** — 計2-3日で「動画指導ゼロ」「通知取りこぼし」の出血を止める。
2. **3-A テンプレート（S-M）→ 2-A 一斉送信（M）** — 同じチャット入力周りの改修なので連続実施が効率的。2-B/3-B（予約・自動化）はその直後に小さく載せる。
3. **1-A LINE通知（M）** — トレーナー即時通知の本命短期解。並行して `fcm_token` migration化でスキーマドリフト解消。
4. **4-A 動画添付（M-L）→ 4-B 音声（M）** — `attachments jsonb` + private `message-media` バケットを共通基盤として先に設計。
5. **1-C トレーナーモード（L）と 5-B 種目ライブラリ（L）** — 大玉。1-Cは通知基盤が既にあるためUI集中で着手可、5-Bは4-Aの動画基盤完成後が効率的。
---

# カテゴリ7: セキュリティ・技術基盤の負債 — 機能設計

## 課題1: clients テーブルの anon 全開放ポリシー（最優先）

`supabase/migrations/20251230131753_remote_schema.sql` L843-851 に以下が現存する。

```sql
CREATE POLICY "LINEユーザー登録の許可_INSERT" ON "public"."clients" FOR INSERT TO "anon" WITH CHECK (true);
CREATE POLICY "LINEユーザー登録の許可_SELECT" ON "public"."clients" FOR SELECT TO "anon" USING (true);
CREATE POLICY "LINEユーザー登録の許可_UPDATE" ON "public"."clients" FOR UPDATE TO "anon" USING (true) WITH CHECK (true);
```

anon キーは Web/Mobile 双方のクライアントに埋まっているため、**未ログイン状態で全顧客の氏名・身体情報を読み書き可能**。

### 施策1-A: anon ポリシーの即時 DROP（推奨・単独で先行リリース可）
- **解決する課題**: 未認証ロールによる clients 全行の SELECT/INSERT/UPDATE を遮断する。
- **修正内容**: 新規 migration（例 `2026070900xxxx_drop_line_anon_policies.sql`）:
  ```sql
  DROP POLICY IF EXISTS "LINEユーザー登録の許可_INSERT" ON public.clients;
  DROP POLICY IF EXISTS "LINEユーザー登録の許可_SELECT" ON public.clients;
  DROP POLICY IF EXISTS "LINEユーザー登録の許可_UPDATE" ON public.clients;
  ```
- **移行手順**:
  1. 影響確認: 現行の正規経路を grep で確認済み — Mobile は authenticated（Supabase Auth ログイン後）で clients を参照、Web の管理系操作は `supabaseAdmin`（service_role、RLS 非対象）。anon で clients に触るのは LINE レガシー（`saveLineUser.ts` / `/liff`）のみ。
  2. まず staging（ローカル `supabase db reset`）で Web ログイン前画面・Mobile 未ログイン起動がエラーにならないことを確認。
  3. `supabase db push` で本番適用。既存データ・既存アプリの変更は不要（authenticated 用ポリシーは別途存在）。
  4. 適用後、anon キーで `select * from clients` を叩いて 0 行になることを確認。
- **既存コードとの接続点**: `supabase/migrations/20251230131753_remote_schema.sql`（原因）、`fit-connect/src/lib/supabase/saveLineUser.ts`、`fit-connect/src/app/liff/page.tsx`（唯一の anon 利用箇所＝レガシー）
- **規模感**: S（半日）
- **リスク・考慮事項**: 切り戻しは同名 CREATE POLICY の再適用で即可能。唯一壊れるのは LIFF ページだが既に廃止対象（課題6で撤去）。なお同 migration には `GRANT ALL ... TO anon` が多数あるが、これは Supabase 標準の grant で RLS が実ゲートのため、ポリシー DROP が本質対応。

### 施策1-B: anon ロールのテーブル権限 REVOKE（追加ハードニング・任意）
- **解決する課題**: 将来誰かが `TO public` / permissive なポリシーを誤追加しても anon が読めない多層防御。
- **修正内容**: `REVOKE INSERT, UPDATE, DELETE ON public.clients FROM anon;` など、書き込み系 grant を anon から剥がす migration。`ALTER DEFAULT PRIVILEGES` も anon への書き込み付与を外す。
- **移行手順**: 施策1-A の安定稼働を1〜2週間確認後に適用。PostgREST のスキーマキャッシュリロード（`NOTIFY pgrst, 'reload schema'`）を migration 末尾に入れる。
- **既存コードとの接続点**: 同上 migration の L997-1273（GRANT 群）
- **規模感**: S
- **リスク・考慮事項**: anon で正当に使う機能（今後の招待リンク等）を作る際に権限再付与が必要になる点をドキュメント化しておく。

---

## 課題2: Storage 2バケットの public read

`20260102075114_create_message_photos_bucket.sql` / `20260204100000_create_client_avatars_bucket.sql` で `public=true` かつ全員 SELECT 可。加えて **message-photos の INSERT ポリシーが `WITH CHECK (bucket_id = 'message-photos')` のみで、他人のフォルダにもアップロード可能**という副次的不備がある。さらに Web は migration 管理外の `profile-images`（`uploadProfileImage.ts`）と `client-notes`（`uploadNoteFile.ts`）バケットも使用しており、これらも同時に棚卸しが必要。

### 施策2-A: private バケット化 + 署名付きURL（推奨）
- **解決する課題**: URL 推測・漏洩による顧客の食事・身体写真の第三者閲覧を防ぐ。
- **修正内容**:
  1. DB 側 migration:
     ```sql
     UPDATE storage.buckets SET public = false WHERE id IN ('message-photos', 'client-notes');
     -- SELECT ポリシーを「本人 or 担当トレーナー」に限定
     DROP POLICY IF EXISTS "Public read access for message photos" ON storage.objects; -- 実名は要確認
     CREATE POLICY "message_photos_select_owner_or_trainer" ON storage.objects FOR SELECT TO authenticated
       USING (
         bucket_id = 'message-photos' AND (
           (storage.foldername(name))[1] = auth.uid()::text
           OR EXISTS (SELECT 1 FROM public.clients c
                      WHERE c.client_id::text = (storage.foldername(name))[1]
                        AND c.trainer_id = auth.uid())
         )
       );
     -- INSERT も自フォルダ限定に修正
     CREATE POLICY "message_photos_insert_own_folder" ON storage.objects FOR INSERT TO authenticated
       WITH CHECK (bucket_id = 'message-photos' AND (storage.foldername(name))[1] = auth.uid()::text);
     ```
  2. アプリ側: `getPublicUrl` → `createSignedUrl`（表示時に有効期限付きURLを都度発行、TTL 1時間程度）へ置換。**DB にはフルURLではなく Storage パス（`userId/uuid.jpg`）を保存する形へ移行**するのが本筋。
- **移行手順**（既存データを壊さない段取りが重要）:
  1. **Phase 0（互換準備）**: 両アプリに「URL/パス両対応」の表示ヘルパーを実装。値が `http` で始まればフルURLからパス抽出（Mobile `deleteImage` に既存の抽出ロジックあり）→ `createSignedUrl` で解決、パスならそのまま署名。public のうちは `getPublicUrl` フォールバックで従来通り表示。
  2. **Phase 1**: 新規アップロードは URL でなくパスを `messages.image_urls` / `meal_records.images` に保存するよう Web/Mobile を変更しリリース。
  3. **Phase 2**: 旧アプリ利用者がほぼ更新された時点（強制アップデート or 2〜4週間後）で `UPDATE storage.buckets SET public=false` を適用。既存 DB のフルURL文字列はヘルパーがパス抽出して署名するため表示は壊れない。
  4. **Phase 3**: バッチ SQL で既存レコードのフルURL→パスへ正規化（`regexp_replace` で `.../object/public/message-photos/` 以降を残す）。
  5. `client-avatars` は「アバターは実質公開情報」なら public 維持も選択肢（施策2-B）。private 化するなら同手順。
- **既存コードとの接続点**:
  - Mobile: `fit-connect-mobile/lib/services/storage_service.dart`（`getPublicUrl` 3箇所、URL→パス抽出ロジック L145-165）
  - Web: `fit-connect/src/lib/supabase/uploadMessageImage.ts`、`uploadNoteFile.ts`、`uploadProfileImage.ts`
  - migrations: `20260102075114_create_message_photos_bucket.sql`、`20260204100000_create_client_avatars_bucket.sql`
- **規模感**: M（両アプリ改修 + 段階リリースで1週間強）
- **リスク・考慮事項**: 切り戻しは `public=true` に戻すだけで即復旧可。署名URLはキャッシュが効きにくいため Mobile 側は `cached_network_image` のキー設計（パスをキーに）が必要。FCM/Web Push のサムネイル等でURLを直接埋めている箇所がないか横断確認すること。`profile-images` / `client-notes` バケットは **migration 自体が存在しない**ため、課題3と同様に定義を migration 化してから方針を適用する。

### 施策2-B: 折衷案 — message-photos のみ private、client-avatars は public 維持
- **解決する課題**: 実害が大きい食事・身体写真のみ保護し、改修範囲を最小化。
- **修正内容**: 施策2-A を message-photos に限定。avatars は UUID パスで実質推測困難として現状維持（INSERT の自フォルダ制限は既に正しい）。
- **移行手順**: 施策2-A の Phase 1-3 を message-photos のみに適用。
- **規模感**: M（2-Aより2〜3日短縮）
- **リスク・考慮事項**: 「public バケットが1つ残る」ことをセキュリティ方針として明文化する必要。推奨は 2-A（全 private）だが、リリース速度優先なら 2-B。

---

## 課題3: client_notes の CREATE TABLE migration 欠落（スキーマドリフト）

migrations には `20260215115338_add_client_notes_select_policy.sql`（SELECT ポリシーのみ）しかなく、テーブル本体はリモート直作成。ローカル `db reset` や新環境構築が壊れる状態。

### 施策3-A: 実コードからのスキーマ復元 migration 追加（推奨）
- **解決する課題**: `supabase db reset` / CI / 新環境でスキーマが再現できない状態を解消し、以後の変更をコード管理下に置く。
- **修正内容**: Web API（`/api/client-notes/route.ts`）で使用中のカラムから復元した冪等 migration を、**既存ポリシー migration より前のタイムスタンプ**（例 `20260215115337_create_client_notes.sql`）で追加:
  ```sql
  CREATE TABLE IF NOT EXISTS public.client_notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    trainer_id uuid NOT NULL REFERENCES public.trainers(id) ON DELETE CASCADE,
    client_id uuid NOT NULL REFERENCES public.clients(client_id) ON DELETE CASCADE,
    title text NOT NULL,
    content text NOT NULL DEFAULT '',
    file_urls text[] NOT NULL DEFAULT '{}',
    is_shared boolean NOT NULL DEFAULT false,
    shared_at timestamptz,
    session_number integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  );
  ALTER TABLE public.client_notes ENABLE ROW LEVEL SECURITY;
  CREATE INDEX IF NOT EXISTS idx_client_notes_client ON public.client_notes(client_id, created_at DESC);
  -- トレーナー用ポリシー（現状 Web は supabaseAdmin 経由で RLS を素通りしているため、リモートに無い可能性が高い）
  DROP POLICY IF EXISTS "trainers_manage_own_notes" ON public.client_notes;
  CREATE POLICY "trainers_manage_own_notes" ON public.client_notes FOR ALL TO authenticated
    USING (trainer_id = auth.uid()) WITH CHECK (trainer_id = auth.uid());
  ```
- **移行手順**:
  1. リモート実スキーマと照合できないため、まず `supabase db diff --linked`（またはダッシュボードで `\d client_notes` 相当）で実カラムを確認し、上記 DDL を補正（**確認できるまでは推測カラムを NOT NULL にしない**）。
  2. 冪等（IF NOT EXISTS / DROP POLICY IF EXISTS）で書き、リモートには実質 no-op、新環境ではフル作成になるようにする。
  3. ローカル `supabase db reset` → Web のカルテ CRUD と Mobile の共有ノート閲覧を回帰確認 → `db push`。
  4. 併せて `client-notes` **ストレージバケットの作成 migration も追加**（`uploadNoteFile.ts` が使用、これも管理外）。
- **既存コードとの接続点**: `fit-connect/src/app/api/client-notes/route.ts`（カラムの根拠）、`fit-connect/src/lib/supabase/getClientNotes.ts`、`fit-connect/src/lib/supabase/uploadNoteFile.ts`、`supabase/migrations/20260215115338_add_client_notes_select_policy.sql`
- **規模感**: S（1日）
- **リスク・考慮事項**: タイムスタンプを既存 migration の間に挿入するとリモートの migration 履歴とズレる場合がある → その場合は最新タイムスタンプで作成し `supabase migration repair` は使わず冪等 SQL に頼る方が安全。既存データへの影響はゼロ（no-op 設計）。

---

## 課題4: workout_assignments.status 列の migration 欠落

`20260221000000_create_workout_tables.sql` には `is_completed boolean` のみだが、`auto-skip-workouts/index.ts` と Mobile（`workout_repository.dart` L72/115/145/164、`workout_assignment_model.dart` で `status` が required）は `status`（pending/completed/skipped）を全面使用。リモート直付けの列。

### 施策4-A: status 列の追認 migration + is_completed の段階廃止（推奨）
- **解決する課題**: コード管理外の列を migration 化し、`is_completed` との二重管理を解消する。
- **修正内容**:
  ```sql
  -- Step1: 追認（リモートでは no-op）
  ALTER TABLE public.workout_assignments
    ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending';
  -- 既存 CHECK が無ければ付与（NOT VALID→VALIDATE で安全に）
  ALTER TABLE public.workout_assignments
    ADD CONSTRAINT workout_assignments_status_check
    CHECK (status IN ('pending','completed','skipped')) NOT VALID;
  ALTER TABLE public.workout_assignments VALIDATE CONSTRAINT workout_assignments_status_check;
  -- Step2: 新環境向けバックフィル（is_completed=true → completed）
  UPDATE public.workout_assignments SET status = 'completed' WHERE is_completed = true AND status = 'pending';
  CREATE INDEX IF NOT EXISTS idx_workout_assignments_status ON public.workout_assignments(status, assigned_date);
  ```
  将来 migration で `is_completed` を GENERATED 列化（`GENERATED ALWAYS AS (status = 'completed') STORED`）または DROP。Mobile の `workout_repository.dart` は L40/54 で `is_completed` も書いているため、先にアプリ側を status 単独へ寄せる。
- **移行手順**:
  1. 追認 migration（Step1+index）を即適用 — 既存アプリは無影響。
  2. Mobile `workout_repository.dart` から `is_completed` 書き込みを撤去し status のみに（Web は該当クエリなしを確認済み）。
  3. 旧アプリバージョンの利用が消えた後、`is_completed` を DROP する migration を別途適用。
- **既存コードとの接続点**: `supabase/functions/auto-skip-workouts/index.ts`、`fit-connect-mobile/lib/features/workout/data/workout_repository.dart`、`fit-connect-mobile/lib/features/workout/models/workout_assignment_model.dart`、`supabase/migrations/20260221000000_create_workout_tables.sql`
- **規模感**: S（追認のみなら半日、is_completed 廃止まで含めて M）
- **リスク・考慮事項**: リモートの実 CHECK 制約名・DEFAULT と衝突しないよう `ADD CONSTRAINT` は例外握り潰しの DO ブロックで包むか、事前に `db diff` で確認。切り戻しは列 DROP 不要（追認なので戻す対象がない）。

---

## 課題5: auto-skip-workouts の cron がリポジトリ管理外

### 施策5-A: pg_cron + pg_net + Vault による cron の migration 化（推奨）
- **解決する課題**: スケジュール実行設定がダッシュボード手作業依存で、環境再現・監査ができない状態を解消。
- **修正内容**: migration 例:
  ```sql
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  CREATE EXTENSION IF NOT EXISTS pg_net;
  -- 冪等: 既存ジョブがあれば削除
  SELECT cron.unschedule('auto-skip-workouts')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-skip-workouts');
  SELECT cron.schedule(
    'auto-skip-workouts',
    '0 18 * * *',  -- 毎日 03:00 JST (18:00 UTC)
    $$
    SELECT net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/auto-skip-workouts',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
      ),
      body := '{}'::jsonb
    );
    $$
  );
  ```
  Vault への `project_url` / `service_role_key` 登録はダッシュボード or `vault.create_secret()`（キー値自体は migration に書かない）。
- **移行手順**:
  1. Vault にシークレット2件を手動登録（1回だけの環境セットアップ、手順を `docs/tasks/` に記録）。
  2. migration 適用 → `SELECT * FROM cron.job;` と `cron.job_run_details` で実行確認。
  3. ダッシュボードに既存の手動 cron があれば重複防止のため削除。
- **既存コードとの接続点**: `supabase/functions/auto-skip-workouts/index.ts`（`Authorization: Bearer <service_role>` を検証しているため上記ヘッダー方式と整合）。既存パターン参考: `supabase/migrations/20260102073239_fix_webhook_url_for_production.sql`
- **規模感**: S（1日）
- **リスク・考慮事項**: 二重実行されても `status='pending'` 条件により冪等なので実害は小さい。ローカル環境では vault シークレットが無く cron が失敗するだけ（無害）。切り戻しは `cron.unschedule`。

### 施策5-B: Edge Function 内スケジュール実行を Deno.cron / Supabase Scheduled Functions に移す（代替案）
- Supabase の Scheduled Functions（config.toml 管理）が利用可能なら `supabase/config.toml` にスケジュール定義を書く方式。CLI バージョン依存のため、5-A（pg_cron）が確実。規模感 S。

---

## 課題6: レガシー LINE 連携コードの撤去

### 施策6-A: LINE 関連コード・型・列の段階的撤去（推奨）
- **解決する課題**: anon ポリシーの温床かつ攻撃面となっている未使用エンドポイント（webhook は認証なしで叩ける Route）を除去する。
- **修正内容**:
  1. コード削除: `/liff` ページ、`/api/line/webhook` Route、`saveLineUser.ts`。
  2. 型整理: `fit-connect/src/types/client.ts` から `line_user_id` を optional 化 → 最終的に削除。
  3. DB: `clients.line_user_id` 列は当面残置（DROP は最後）。将来 migration で `ALTER TABLE clients DROP COLUMN line_user_id;`。
  4. Vercel の LINE 系環境変数（LIFF_ID, LINE_CHANNEL_ACCESS_TOKEN）を削除。
- **移行手順**:
  1. 課題1（anon ポリシー DROP）を先に適用 — LIFF が機能停止するのはこの時点なので、コード削除は同一リリースにまとめると整合が取れる。
  2. コード削除 → ビルド確認（`line_user_id` 参照のコンパイルエラーを潰す）→ デプロイ。
  3. 1〜2リリース安定後、`line_user_id` 列 DROP の migration（Mobile 側モデルに同名フィールドが無いことを確認の上）。
- **既存コードとの接続点**: `fit-connect/src/app/liff/page.tsx`、`fit-connect/src/app/api/line/webhook/route.ts`、`fit-connect/src/lib/supabase/saveLineUser.ts`、`fit-connect/src/types/client.ts`
- **規模感**: S（1日、列 DROP 含めても S+）
- **リスク・考慮事項**: 既存 clients 行に `line_user_id` 値が入っている可能性があるため、列 DROP 前に値の有無を確認（歴史データとして残すなら DROP せず COMMENT で deprecated 明記でも可）。切り戻しは git revert のみ。

---

## 課題7: Mobile のオフライン対応ゼロ

記録作成が「メッセージ送信 → parse-message-tags Edge Function がサーバー側で記録生成」という構造のため、**オフライン対応は「メッセージ送信の Outbox キュー化」に集約できる**のが本プロダクトの利点。

### 施策7-A: Outbox パターン（送信キュー）+ 楽観的UI（推奨・第1段階）
- **解決する課題**: 圏外のジムで記録（タグ付きメッセージ）が送れず消失する問題。
- **修正内容**:
  1. ローカルDB導入: `drift`（SQLite）推奨。`outbox_messages` テーブル（client_generated_id(uuid), content, tags, metadata, local_image_paths[], status: queued/sending/sent/failed, retry_count, created_at）。
  2. `message_repository.dart` の insert（L116 付近）を「まず outbox に書く → 送信ワーカーが flush」に変更。**messages テーブルに `client_generated_id uuid UNIQUE` 列を追加する migration** を入れ、insert 時に付与（再送時の重複挿入防止。UNIQUE 違反 = 送信済みとして成功扱い）。
  3. `connectivity_plus` で復帰検知 → キュー flush（指数バックオフ、画像は local path から `StorageService.uploadImage` → URL 差し替え → メッセージ insert の順）。
  4. UI: チャット画面で queued 状態を「時計アイコン/送信待ち」表示（楽観的挿入）、失敗時に再送/削除アクション。
- **移行手順**:
  1. DB migration（`client_generated_id` 追加、NULL 許容・UNIQUE）→ Web/parse-message-tags には影響なし（列を読まないため）。
  2. Mobile に outbox 層を追加し、オンライン時は従来と同じ即時送信（キュー経由でも遅延ほぼゼロ）としてリリース。旧バージョンアプリは列を送らないだけで共存可能。
  3. AI 栄養推定（Edge Function 呼び出し）はオンライン必須のため、圏外時は「タグのみ記録し、推定はスキップ」のフォールバックを明示。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/messages/data/message_repository.dart`（L116 の insert）、`fit-connect-mobile/lib/services/storage_service.dart`（画像アップロード）、`supabase/functions/parse-message-tags/`（挿入後の記録生成、変更不要）
- **規模感**: M（1週間）
- **リスク・考慮事項**: 二重送信防止が肝 — `client_generated_id` の UNIQUE 制約で担保。時刻は送信時刻でなく記録時刻（キュー投入時刻）を `created_at`/metadata に載せないと「翌朝送信された昨夜の体重」が誤った日付になる点に注意（parse-message-tags の recorded_at 決定ロジックの確認が必要）。切り戻しはフラグでキューをバイパスし即時送信に戻せる設計にする。

### 施策7-B: 読み取りキャッシュ（第2段階・任意）
- **解決する課題**: 圏外で過去の記録・ワークアウト指示が見られない問題。
- **修正内容**: 7-A で導入した drift に records/messages/workout_assignments の read-through キャッシュを追加。Riverpod の provider 層で「キャッシュ即返し → ネット取得で更新」の stale-while-revalidate。
- **移行手順**: 7-A 安定後に画面単位で段階導入（優先: workout_screen → messages → 記録タブ）。
- **規模感**: L（数週。7-Aと切り離して計画）
- **リスク・考慮事項**: キャッシュ不整合は TTL + pull-to-refresh で許容範囲に。まず 7-A のみで「記録が消えない」という最重要価値は達成できる。

---

## 課題8: AI 推定画像の orphan cleanup 未実装

`StorageService.uploadAiImage` が `message-photos/${userId}/ai/${uuid}.jpg` に先行アップロードし、ユーザーが「挿入」せず離脱すると孤児化する（パス分離は済んでおり cleanup 前提の設計になっている）。

### 施策8-A: 定期 cleanup Edge Function + pg_cron（推奨）
- **解決する課題**: 参照されない AI 画像によるストレージ肥大とプライバシーリスク（写真が無期限に残る）。
- **修正内容**: 新 Edge Function `cleanup-ai-images`:
  1. service_role で `storage.objects` を直接 SQL 検索:
     ```sql
     SELECT name FROM storage.objects
     WHERE bucket_id = 'message-photos'
       AND name LIKE '%/ai/%'
       AND created_at < now() - interval '48 hours';
     ```
  2. 各パスについて参照チェック: `messages.image_urls`（フルURL格納のため `LIKE '%' || name` で照合）、`meal_records.images`、`ai_estimation_logs` に image 参照があればそれも対象。未参照のみ `storage.remove()`。
  3. 課題5と同じ pg_cron migration に日次ジョブを追加（auto-skip-workouts と同一の Bearer service_role 認証パターンを踏襲）。
- **移行手順**:
  1. まず dry-run モード（削除対象を返すだけ）でデプロイし、数日分のログで誤検知ゼロを確認。
  2. 猶予 48h は「アップロード→挿入までの最長想定時間」より十分長く設定（挿入済み画像は messages に URL が載るので誤削除されない）。
  3. 削除モードに切替 + cron 登録。
- **既存コードとの接続点**: `fit-connect-mobile/lib/services/storage_service.dart`（`aiImagePath` L66-68、パス規約の根拠）、`supabase/functions/estimate-meal-nutrition/`、`supabase/migrations/20260502120300_create_ai_estimation_logs.sql`
- **規模感**: S〜M（2〜3日）
- **リスク・考慮事項**: 照合は「URL文字列 LIKE」なので、課題2でパス保存へ移行した後は照合条件を両対応にすること（実装順に注意）。誤削除の切り戻しは不可能なため dry-run 期間を必ず設ける。

### 施策8-B: クライアント側ベストエフォート削除（併用推奨）
- **解決する課題**: 明示キャンセル時の即時削除で orphan 発生量自体を減らす。
- **修正内容**: AI 推定シートで「キャンセル/挿入せず閉じる」時に `StorageService.deleteImage()`（実装済み）を fire-and-forget で呼ぶ。
- **移行手順**: Mobile の該当シート（meal 推定フロー）に1フック追加のみ。アプリ強制終了・圏外時は取りこぼすため 8-A の補完であり代替ではない。
- **規模感**: S（半日）
- **リスク・考慮事項**: 挿入済み画像を誤って消さないよう「挿入完了フラグが立っていない場合のみ削除」をガードする。

---

## カテゴリ内の推奨着手順

1. **施策1-A + 6-A**（anon ポリシー DROP + LINE コード撤去）— 未認証で全顧客情報が読める穴の即時封鎖。同一PRで半日〜1日。
2. **施策3-A + 4-A + 5-A**（client_notes / workout status / cron の migration 化）— スキーマドリフト3点をまとめて解消し、以後の `db reset`・環境再現を正常化。約2日。
3. **施策2-A**（Storage private 化 + 署名URL）— 両アプリの段階リリースが必要なため計画的に約1週間。
4. **施策8-B → 8-A**（AI 画像 cleanup）— 8-B は即日、8-A は dry-run を挟んで 2-A の照合条件と整合させて実施。
5. **施策7-A**（Mobile Outbox）— 独立して並走可能な最大の UX 改善。7-B（読み取りキャッシュ）は次期スプリントへ。

---

# 8. グロース・差別化 — 機能設計

---

## 課題 8-1: SNSへの成果シェア機能なし

### 8-1-A. シェアカード生成（Mobile・顧客側）【推奨】
- **解決する課題**: 顧客が体重変化・ワークアウト完了・連続記録などを画像1枚のカードとしてX/Instagram/LINEへシェアでき、顧客のモチベーション向上とアプリ・トレーナーの露出を同時に獲得する。
- **ユーザーストーリー**:
  - 顧客として、-3kg達成や30日連続記録の瞬間をきれいなカードでSNSに投稿したい。
  - 顧客として、ワークアウト完了時のconfetti画面からそのままシェアしたい。
  - トレーナーとして、カードに自ジム/自分の名前が入ることで無料の販促にしたい。
- **機能仕様**:
  - Mobile: `RepaintBoundary`→`toImage()`でウィジェットをPNG化し、既存導入済みの `share_plus: ^10.1.1`（`fit-connect-mobile/pubspec.yaml:54` 確認済み）の `Share.shareXFiles` でOSシェアシートを起動。X/Instagram側のAPI審査は不要（OS標準シェア）。
  - カードテンプレ3種: ①体重推移（開始→現在、グラフ付き）②ワークアウト完了（種目数・総ボリューム）③期間サマリ（記録日数・ストリーク）。数値の表示ON/OFFトグル必須（体重を隠して「-2.5kg」だけ出す等）。
  - フッターに「FIT-CONNECT」ロゴ＋トレーナー名（トレーナー側設定でジム名/ロゴに差し替え可）。
  - 導線: 記録タブのサマリ（`records_overview_screen.dart`）にシェアボタン、ワークアウト完了ダイアログ（`workout_screen.dart` のconfetti後）に「シェア」ボタン、目標達成時（`check_goal_achievement` RPC発火時）にシェア提案シート。
- **データモデル**: 新テーブル不要。トレーナーのブランド設定として `trainers` に `brand_name TEXT`, `brand_logo_url TEXT` を追加（migration 1本）。任意で `share_events(id, client_id, card_type, created_at)` を計測用に追加。
- **バックエンド**: 不要（画像生成は端末内）。
- **通知設計**: 不要。目標達成時のシェア提案はアプリ内表示のみ。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/records_overview/presentation/screens/records_overview_screen.dart`、`nutrition_trend_chart.dart`（グラフ描画パターン流用）、`workout/`のworkout_screen.dart 完了フロー、`supabase/migrations/`（trainersカラム追加）。
- **フェーズ分け**: MVP=体重推移カード＋ワークアウト完了カード（OSシェアシートのみ）→ 拡張=トレーナーブランド設定、ストリークカード、シェア計測。
- **規模感**: M（〜1週）
- **リスク・考慮事項**: 体重等の健康データをシェア画像に含めるため「数値を隠す」デフォルトONが安全。Instagram Storiesへの直接投稿APIは使わない（規約・審査コスト回避、OSシェアで十分）。

### 8-1-B. ビフォーアフター画像出力（Web・トレーナー側）
- **解決する課題**: トレーナーが顧客の成果（同意取得済み）を自身のSNS販促素材として出力できる。
- **ユーザーストーリー**: トレーナーとして、顧客の3ヶ月の体重グラフ＋統計を1枚画像にして自分のInstagramに載せ、集客に使いたい。
- **機能仕様**: Web `/report` または `/clients/[client_id]` に「シェア画像を出力」ボタン。既存PDF出力と同様にcanvas/`html-to-image`でPNG生成しダウンロード。顧客名は自動でイニシャル/匿名化。「顧客の同意を得ました」チェック必須。
- **データモデル**: `clients.share_consent BOOLEAN DEFAULT false`（同意記録）。
- **バックエンド**: 不要。
- **既存コードとの接続点**: `fit-connect/src/components/clients/WeightChart.tsx`, `PfcBalanceCard.tsx`、`/report` のPDF出力実装。
- **フェーズ分け**: MVP=体重グラフ画像1種 → 拡張=テンプレ選択・進捗写真組み込み（8-4-Aと連動）。
- **規模感**: S〜M
- **リスク・考慮事項**: 顧客の個人情報・肖像の扱い。同意フラグをUI上必須にし、匿名化をデフォルトにする。

---

## 課題 8-2: ユーザーコミュニティ機能なし

### 8-2-A. トレーナー内チャレンジ＆匿名リーダーボード【推奨】
- **解決する課題**: フルSNS型コミュニティの重さ（モデレーション・過疎リスク）を避けつつ、同じトレーナーの顧客同士の「ゆるい連帯」で継続率を上げる。
- **ユーザーストーリー**:
  - トレーナーとして、「今月は全員で記録日数20日を目指す」チャレンジを作って顧客全体を活性化したい。
  - 顧客として、他の参加者がどのくらい頑張っているかをニックネーム表示で見て刺激を受けたい。
- **機能仕様**:
  - Web: `/clients` または新設 `/challenges` にチャレンジ作成UI（期間・指標: 記録日数/ワークアウト完了数/歩行時間、参加者選択）。進捗一覧表示。
  - Mobile: ホームタブに「チャレンジカード」（順位・自分の進捗・上位3名のニックネーム）。詳細画面でリーダーボード全体。実名は出さずニックネーム＋アバター。
  - 進捗は既存の `weight_records` / `exercise_records` / `workout_assignments` から日次集計（新規の記録動作は不要＝参加ハードルゼロ）。
- **データモデル**:
  - `challenges(id, trainer_id, title, metric TEXT CHECK(record_days/workout_count/exercise_minutes), start_date, end_date, created_at)`
  - `challenge_participants(challenge_id, client_id, nickname TEXT, joined_at, PRIMARY KEY(challenge_id, client_id))`
  - RLS: trainerは自分の`trainer_id`行をALL、clientは自分が参加するチャレンジ行と同一チャレンジ参加者の進捗ビューのみSELECT（進捗はニックネーム列のみ返すVIEW `challenge_leaderboard` を作り実名秘匿）。
- **バックエンド**: RPC `get_challenge_leaderboard(challenge_id)`（既存記録テーブルを集計、SECURITY DEFINERで実名を落として返す）。cron不要（読み取り時集計で開始）。
- **通知設計**: チャレンジ開始時・終了時・順位変動（週1まで）にFCM。※モバイルFCMトークンのサーバ保存テーブルが未整備のため、`device_tokens(client_id, fcm_token, platform, updated_at)` の新設が前提（他カテゴリと共通基盤）。
- **既存コードとの接続点**: Mobile `lib/features/home/`（ホームカード追加）、`notification_service.dart`、Web `/clients` ページ群、`supabase/functions/parse-message-tags`（記録生成のトリガ地点＝進捗の元データ）。
- **フェーズ分け**: MVP=記録日数チャレンジ1指標＋リーダーボード → 拡張=複数指標・リアクション（絵文字応援）・トレーナー横断の全体チャレンジ。
- **規模感**: L（数週）
- **リスク・考慮事項**: 体重系の指標は序列化がセンシティブなので指標を「行動量」に限定する。過疎対策としてトレーナーの顧客数が少ない場合は非表示推奨。

### 8-2-B. フル機能タイムライン型コミュニティ（非推奨・保留）
- **解決する課題**: 同上だが投稿・コメント型。
- **機能仕様/リスク**: 投稿・コメント・通報・モデレーションが必要で、UGCを持つ瞬間にApp Store審査でモデレーション体制（通報・ブロック・利用規約）が必須(Guideline 1.2)。現フェーズのユーザー規模では過疎リスクが高くROIが悪い。8-2-Aの成功後に再検討。
- **規模感**: L+（数週〜）

---

## 課題 8-3: 独自スタンプ生成（AI）なし

### 8-3-A. AIスタンプ生成＆メッセージ添付
- **解決する課題**: トレーナー/ジム独自のスタンプをAI画像生成で作成し、メッセージの温度感を上げ他社チャットツール（LINE等）との差別化にする。
- **ユーザーストーリー**:
  - トレーナーとして、自分の似顔絵ベースの「ナイス！」「あと少し！」スタンプセットを作って返信に使いたい。
  - 顧客として、トレーナーからの独自スタンプで褒められると嬉しい。
- **機能仕様**:
  - Web `/settings` に「スタンプ工房」タブ: プロンプト（＋任意で顔写真参照）→8種の定型感情（賞賛/励まし/OK/お疲れ/など）を一括生成→プレビュー→保存。再生成は月N回制限。
  - メッセージ画面（Web `/message`・Mobile メッセージタブ）にスタンプピッカーを追加。送信は `messages` に `metadata.sticker_id` ＋ `image_urls` にスタンプURLを入れる方式（既存のメッセージ描画・Realtimeがそのまま使える）。
  - 生成はProプラン限定（既存 `trainers.subscription_plan` で判定、AI栄養推定と同じゲート）。
- **データモデル**:
  - `stickers(id, trainer_id, emotion_key TEXT, image_url TEXT, prompt TEXT, created_at)`
  - Storage: 新バケット `stickers`（生成後は変化しないためpublic read可、ただし既存バケットのpublic read問題と合わせて署名URL化を検討）。
  - RLS: trainerは自分の行をALL、clientは自分のトレーナーのスタンプをSELECT。
- **バックエンド**: Edge Function `generate-sticker`（画像生成API呼び出し→Storage保存→stickers INSERT）。レート制限は `ai_estimation_logs` と同様のログテーブル方式（`ai_generation_logs` に汎用化するのが望ましい）。
- **通知設計**: スタンプ送信は通常メッセージと同じ既存Push経路（Web Push/FCM）に乗る。
- **既存コードとの接続点**: `supabase/functions/estimate-meal-nutrition/`（Edge FunctionのAI呼び出し・レート制限パターンを踏襲）、`messages.metadata jsonb`、Mobile `lib/features/messages/` の quick_action_bar.dart 付近にピッカー導線、Web `/message` の入力欄。
- **フェーズ分け**: MVP=生成なしの「プリセットスタンプ送信」機能（ピッカー＋metadata方式）→ 拡張=AI生成（トレーナー独自セット）→ さらに顧客の実績連動スタンプ（「10回目のワークアウト達成」記念など）。
- **規模感**: MVP=M、AI生成込み=L
- **リスク・考慮事項**: 画像生成APIのコスト（生成は低頻度・キャッシュ前提なら軽微）。顔写真を使う場合は肖像・生成物の権利説明が必要。生成失敗/不適切画像への再生成UIを必ず用意。優先度は他施策より低め — まずMVPのプリセット送信だけ切り出す価値あり。

---

## 課題 8-4: 3Dボディスキャン（将来の差別化ネタ）

### 8-4-A. 進捗写真（プログレスフォト）機能【推奨・先行必須】
- **解決する課題**: 3Dスキャンの前提となる「体の見た目変化の記録」を写真で実現する。バックログの「体写真記録」と同一。8-1のシェア機能とも直結する。
- **ユーザーストーリー**:
  - 顧客として、毎週同じポーズの写真を撮り、開始時と並べて変化を見たい。
  - トレーナーとして、顧客の見た目変化をカルテと合わせて確認したい。
- **機能仕様**:
  - Mobile: 記録タブに「写真」サブタブ追加（既存6サブタブ→7）。前回写真の半透明オーバーレイ付きカメラガイド（正面/横/背面）。ビフォーアフター比較スライダー。
  - Web: `/clients/[client_id]` に写真タブ追加（時系列グリッド＋2枚比較ビュー）。
- **データモデル**:
  - `progress_photos(id, client_id, pose TEXT CHECK(front/side/back), image_path TEXT, taken_at DATE, memo TEXT, created_at)`
  - Storage: 新バケット `progress-photos` — **必ずprivate**＋署名URL（既存 message-photos のpublic read を踏襲しないこと）。
  - RLS: client本人ALL、担当trainerはSELECT。
- **バックエンド**: 不要（Storage＋テーブルのみ）。
- **通知設計**: 週1の撮影リマインダー（リマインダー基盤ができ次第。それまでは無し）。
- **既存コードとの接続点**: Mobile 記録タブ（`records_overview` と同階層に `progress_photos` featureを新設）、既存の画像アップロード実装（メッセージ画像添付処理）、Web clients詳細タブ構成。
- **フェーズ分け**: MVP=撮影・一覧・2枚比較 → 拡張=オーバーレイガイド・シェアカード連携（8-1-A）・カルテ埋め込み。
- **規模感**: M
- **リスク・考慮事項**: 極めてセンシティブな画像。private bucket＋署名URL必須、トレーナー閲覧可否を顧客側でOFFにできる設定を検討。App Store審査上は問題なし（健康記録目的）。

### 8-4-B. LiDAR/写真測位による3Dスキャン（調査スパイクのみ）
- **解決する課題**: 「3Dで体型変化が見える」という強い差別化。ただし現時点では投資対効果が不明。
- **機能仕様（調査項目）**: ①iPhone Pro系LiDAR＋ARKit `Object Capture` での体型メッシュ取得可否 ②サードパーティSDK（Bodygram等の写真2枚→採寸API）のコストと精度 ③出力（周囲径推定: ウエスト/ヒップ/腕囲）をどう保存・表示するか。スパイク成果は `docs/tasks/` にレポート。
- **データモデル（将来）**: `body_measurements(id, client_id, source TEXT, waist_cm, hip_cm, chest_cm, arm_cm, thigh_cm, scan_asset_path, recorded_at)` — 3D以前に手動メジャー入力にも使える汎用設計にする。
- **フェーズ分け**: スパイク（S）→ 手動採寸入力（S）→ SDK連携 or LiDAR（L）。
- **規模感**: スパイク=S、本実装=L
- **リスク・考慮事項**: 外部SDKは従量課金＋身体データの外部送信（プライバシーポリシー改定必須）。Android非対応SDKが多い。差別化ネタとしては8-4-Aの写真比較で当面十分。

---

## 課題 8-5: トレーニング記録アプリ（Strong等）との連携なし

### 8-5-A. スクリーンショットAI取り込み【推奨・最小コスト】
- **解決する課題**: Strong/ヘビーユーザーが既存アプリのワークアウトログをFIT-CONNECTに移せない問題を、公式API不要のスクショ解析で解決する。
- **ユーザーストーリー**: 顧客として、Strongの完了画面スクショを送るだけで運動記録がFIT-CONNECTに入り、トレーナーに共有されるようにしたい。
- **機能仕様**: 既存のAI栄養推定に「他アプリのスクショ解析」パスが既にある（`estimate-meal-nutrition` の画像=claude-sonnet-4-6）。同じパターンで運動版を追加: Mobileの `#運動` タグフォーム（`structured_tag_form.dart`）に「スクショから読み取る」ボタン→画像添付→Edge Functionが種目/セット/重量/回数をJSON抽出→確認・修正ビュー→ `exercise_records`（＋詳細は `metadata` or 新 `exercise_sets`）に保存。
- **データモデル**: `exercise_records` に `ai_source TEXT`（meal_recordsと同様）と `details JSONB`（種目別セット配列）を追加。レート制限は既存 `ai_estimation_logs` を `kind` カラム追加で共用。
- **バックエンド**: Edge Function `estimate-workout-log`（estimate-meal-nutritionをフォークし、抽出スキーマを運動用に）。
- **通知設計**: 不要（既存のメッセージ経路で自動的にトレーナーへ流れる）。
- **既存コードとの接続点**: `supabase/functions/estimate-meal-nutrition/`、`fit-connect-mobile/lib/.../meal_estimation_api.dart`（API呼び出し・確認修正UIのパターン）、`structured_tag_form.dart`。
- **フェーズ分け**: MVP=スクショ→exercise_records（合計値）→ 拡張=セット単位の詳細保存・Web側での詳細表示。
- **規模感**: M
- **リスク・考慮事項**: 解析コスト（sonnet画像）はrate limitで制御。抽出誤りが前提なので確認・修正ビューは必須（既存パターン踏襲）。

### 8-5-B. Strong CSVインポート
- **解決する課題**: 過去履歴の一括移行（スクショは1回分しか運べない）。
- **機能仕様**: StrongはワークアウトログをCSVエクスポート可能。Mobile設定画面（またはWebトレーナー側）に「CSVインポート」→ファイルピッカー→パース→プレビュー→ `exercise_records` 一括INSERT（`source='import_strong'`）。Hevy等の他アプリCSVもパーサ追加で対応。
- **データモデル**: `exercise_records.source` の許容値追加のみ。
- **バックエンド**: 端末内パースでも可だが、大量行はEdge Function `import-workout-csv` でバッチINSERTが安全。
- **既存コードとの接続点**: `exercise_records` migration、Mobile 設定タブ。
- **フェーズ分け**: 8-5-Aの後。MVP=Strong形式のみ。
- **規模感**: M
- **リスク・考慮事項**: CSVフォーマットはアプリのバージョンで変わり得る（列名マッピングを設定化）。重複排除（日時＋種目キー）必須。

### 8-5-C. HealthKit/Health Connectワークアウト読み取り
- **解決する課題**: Strong等の多くはHealthKitにワークアウトを書き込むため、直接連携なしで自動取り込みできる。
- **機能仕様**: 既存のhealth同期（体重・睡眠READ）に `HealthDataType.WORKOUT` を追加。取得したworkout（種別・時間・消費kcal）を `exercise_records(source='healthkit')` に冪等挿入。既存の重複排除・1時間Timer・resume時同期のインフラをそのまま使う。
- **データモデル**: 変更なし（`exercise_records.source` に healthkit を追加）。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/health/`（health_repository.dart, health_sync_provider.dart）、`android/app/src/main/AndroidManifest.xml`（`android.permission.health.READ_EXERCISE` の追加が必要。現状はREAD_BODY_MEASUREMENTS/READ_SLEEPのみ・確認済み）。
- **フェーズ分け**: MVP=種別+時間+kcalの取り込み → 拡張=セット詳細（HealthKitのworkout eventsは粒度が粗いため期待値調整）。
- **規模感**: S〜M（既存同期基盤があるため小さい）
- **リスク・考慮事項**: iOS審査でHealthKit使用目的の説明追記（既に体重・睡眠で通している導線に追加）。重複リスク: 8-5-Aや手動記録と同一ワークアウトが二重計上されないようsource別表示・時間帯重複チェック。
- **推奨**: 8-5-C（S〜M・自動）→ 8-5-A（体験が良い）→ 8-5-B（移行需要が出たら）の順。

---

## 課題 8-6: Android対応の検証状況が不明

### 8-6-A. Android QA基盤の整備（android-emulator-qa スキル＋実機検証）【推奨】
- **解決する課題**: Health Connectコード・Manifest権限（READ_BODY_MEASUREMENTS/READ_SLEEP・確認済み）はあるがQA導線がiOS Simulatorのみで、Android品質が未知数という状態を解消する。
- **ユーザーストーリー**: 開発者として、Flutterコード変更後にiOSと同様にAndroidエミュレータでも自動QAが走ってほしい。
- **機能仕様（施策）**:
  1. `.claude/skills/android-emulator-qa/` を新設（ios-simulator-qaと同構成: `fvm flutter build apk --debug` → `emulator -avd` 起動 → `adb install` → screenshot静的確認）。
  2. Android固有チェックリストの整備: Health Connectの権限フロー（Health Connectアプリ未インストール端末の分岐）、FCM通知チャネル、戻るボタン挙動、Impeller/レンダリング差異。
  3. Health Connectはエミュレータで動作しない場合があるため、体重・睡眠同期のみ実機（Pixel系）で四半期ごとに手動検証する手順書を `fit-connect-mobile/docs/` に追加。
  4. CI: GitHub Actionsで `flutter build apk` をPRごとに実行（ビルド破壊の早期検知のみでも価値大）。
- **データモデル/バックエンド/通知設計**: なし。
- **既存コードとの接続点**: `.claude/skills/ios-simulator-qa/`（テンプレ）、`fit-connect-mobile/android/app/src/main/AndroidManifest.xml`、`fit-connect-mobile/.fvm/`（Flutter 3.41.9固定をCIにも反映）。
- **フェーズ分け**: MVP=apkビルドCI＋emulatorスクショQAスキル → 拡張=Health Connect実機検証手順・Playストア internal testing 配信。
- **規模感**: S〜M
- **リスク・考慮事項**: lucide_iconsのFlutter 3.44+問題（メモリ記載）があるためCIのFlutterバージョンをfvmと厳密一致させる。Health ConnectはAndroid 14で標準搭載・13以下は別アプリ必要という分岐のテストを忘れない。Google Play公開時はHealth Connect利用の申告フォーム（Health Apps Declaration）が必要。

---

## 課題 8-7: 招待コードで割引・無料化（バイラル獲得）

### 8-7-A. 紹介コード基盤（referral_codes）＋トレーナー紹介プログラム【推奨】
- **解決する課題**: 現状の招待は「生のtrainerId(UUID)をQR/コードとして渡す」だけで（`ClientInviteModal.tsx` 確認済み: trainerIdをそのままコピー/QR化）、紹介インセンティブが存在しない。トレーナー→トレーナー紹介で「紹介した側もされた側もPro1ヶ月無料」を実現しバイラル獲得する。
- **ユーザーストーリー**:
  - トレーナーとして、自分の紹介コードを同業者に渡し、登録されたら自分のProが1ヶ月無料になってほしい。
  - 新規トレーナーとして、紹介コード入力でPro無料トライアルが延長されると登録の後押しになる。
- **機能仕様**:
  - Web `/settings` に「紹介プログラム」セクション: 自分の紹介コード（短い英数6-8桁）表示・コピー・シェア文言生成。紹介実績（人数・獲得済み特典）一覧。
  - Web signup フローに「紹介コード（任意）」入力欄。
  - 特典付与: Stripe未導入のため、当面は `trainers` にクレジット概念を持たせ、課金導入時にStripe couponへマッピングする設計にしておく。
- **データモデル**:
  - `referral_codes(code TEXT PK, trainer_id UUID UNIQUE, created_at)` — トレーナー1人1コード。
  - `referrals(id, referrer_trainer_id, referred_trainer_id UNIQUE, code TEXT, status TEXT CHECK(pending/qualified/rewarded), qualified_at, created_at)` — qualifiedは「被紹介者が初回課金 or 30日継続」で不正防止。
  - `trainers.pro_credit_days INT DEFAULT 0`（無料日数の残高。課金導入前はsubscription_plan判定に加味）。
  - RLS: 自分がreferrer/referredの行のみSELECT。INSERT/UPDATEはservice roleのみ（signup API経由）。
- **バックエンド**: signup時のAPI Route（Web `src/app/api/` に `referral/claim`）でコード検証→referrals INSERT。cron（月次）またはトリガで qualified→rewarded 遷移と `pro_credit_days` 加算。
- **通知設計**: 紹介成立時にreferrerへメール or Web Push（既存 `push_subscriptions` 基盤）。
- **既存コードとの接続点**: `fit-connect/src/components/clients/ClientInviteModal.tsx`（顧客招待UIの隣に配置）、Web `(auth)/signup`、`trainers.subscription_plan` の判定ロジック（AI機能ゲート箇所）。
- **フェーズ分け**: MVP=コード発行・入力・referrals記録（特典は手動付与運用）→ 拡張=pro_credit_days自動付与 → Stripe導入時にcoupon連動。
- **規模感**: M
- **リスク・考慮事項**: 課金（Stripe）が未実装のため「割引」の実体がまだ無い — 本施策は課金導入と同時期にリリースするのが効果最大。自己紹介・複垢の不正対策（同一メールドメイン/デバイスの簡易チェック）。アプリ内課金を将来モバイルに載せる場合、Appleの外部特典訴求ルールに注意（トレーナー課金はWeb完結なら問題なし）。

### 8-7-B. 顧客招待コードの正規化（invite_codesテーブル化）
- **解決する課題**: 生UUIDを招待コードにしている現状はセキュリティ的にも体験的にも悪い（trainerIdの漏洩＝推測不能とはいえ識別子の直接配布）。短命な招待コードに置き換え、将来「顧客経由の友達紹介」にも拡張できる土台を作る。
- **機能仕様**: `ClientInviteModal` を「有効期限付き8桁コード＋QR」を発行する方式に変更。Mobile側の `invite_code_screen.dart` / `qr_scan_screen.dart` はコード→trainer解決APIを叩くように変更。既存UUID方式は移行期間中併用。
- **データモデル**: `invite_codes(code TEXT PK, trainer_id, expires_at, max_uses INT, used_count INT, created_at)`。RLS: trainer本人ALL。コード解決はEdge Function経由（anonからのclientsテーブル直アクセスを排除 — 既知のanonポリシー問題の解消と同時に実施すべき）。
- **バックエンド**: Edge Function or RPC `resolve_invite_code(code)`（trainer名・アバターのみ返す）。
- **既存コードとの接続点**: `fit-connect/src/components/clients/ClientInviteModal.tsx`、`fit-connect-mobile/lib/features/auth/presentation/screens/invite_code_screen.dart`, `qr_scan_screen.dart`, `trainer_confirm_screen.dart`（確認済み）。
- **フェーズ分け**: MVP=コード発行/解決 → 拡張=顧客からの友達紹介（顧客が同トレーナーへ友人を招待→トレーナーに特典）。
- **規模感**: M
- **リスク・考慮事項**: セキュリティ改善（anonポリシー撤去）とセットで行うと工数効率が良い。既存顧客のオンボーディングを壊さない移行順序に注意。

---

## 課題 8-8: AIワークアウトプラン自動生成・解説動画生成なし

### 8-8-A. AIワークアウトプラン下書き生成【推奨】
- **解決する課題**: トレーナーのプラン作成工数（週次で顧客ごとに手作業）をAI下書きで大幅削減。「このアプリがないと仕事にならない」依存度に直結する本命機能。
- **ユーザーストーリー**:
  - トレーナーとして、顧客のプロフィール（目的・年齢・直近の実施履歴）から1週間分のプラン下書きを生成し、修正して配信したい。
  - トレーナーとして、前週の実施率・実重量を踏まえた漸進的な負荷提案がほしい。
- **機能仕様**:
  - Web `/schedule` のプラン作成UI（PlanFormModal / TemplatePanel）に「AIで下書き生成」ボタン。入力: 対象顧客・期間・週あたり日数・重点部位・利用可能器具（自由記述）。出力: `workout_assignments` + `workout_exercises` 形式のドラフトをプレビュー表示→トレーナーが編集→確定で既存の保存フローに乗せる（**AIが直接配信はしない。必ずトレーナー承認を挟む**）。
  - コンテキストとして clients（purpose/goal_description/age/gender）、直近4週の workout_assignments 実績（actual sets）、exercise_records を渡す。
  - Pro限定（`trainers.subscription_plan` ゲート、AI栄養推定と同一ポリシー）。
- **データモデル**: 新テーブル不要。`ai_generation_logs`（8-3と共用のレート制限ログ、`kind='workout_plan'`）。生成メタを残すなら `workout_assignments.generation_source TEXT`。
- **バックエンド**: Edge Function `generate-workout-plan`（claude-sonnet系、structured output でexercises配列を返す。estimate-meal-nutritionの認証・レート制限パターンを踏襲）。
- **通知設計**: 不要（配信自体は既存プラン配信フローが担う）。
- **既存コードとの接続点**: `fit-connect/src/components/schedule/` 配下（AssignmentMiniCard.tsx等・確認済み）とPlanFormModal/TemplatePanel、`supabase/functions/estimate-meal-nutrition/`（実装テンプレ）、`workout_assignments`/`workout_exercises` スキーマ。
- **フェーズ分け**: MVP=プロフィール＋自由記述からの1週間下書き → 拡張=前週実績を踏まえた漸進提案・テンプレとして保存 → さらにバックログの「ワークアウト種別分け」と統合。
- **規模感**: L（プロンプト設計・プレビューUI含む）
- **リスク・考慮事項**: 安全性（怪我リスクのある提案）— 必ず「トレーナー承認必須」のワークフローにし、免責文言を表示。禁忌情報（怪我・疾患）がカルテ（client_notes）にある場合はコンテキストに含める設計とし、生成品質の評価期間を設ける。APIコストはレート制限（例: 20回/trainer/day）で制御。

### 8-8-B. 種目解説ライブラリ（動画URL＋AIテキスト解説）
- **解決する課題**: 「解説動画生成」ニーズの本質は“顧客が種目のやり方を分からない”こと。動画をAI生成する前に、種目マスタ＋解説で9割解決する。
- **ユーザーストーリー**: 顧客として、プランの種目名をタップしたらフォームのポイントと参考動画が見たい。
- **機能仕様**:
  - 種目マスタ `exercise_library` を新設し、AIで各種目のテキスト解説（フォーム手順・よくあるミス・注意点）を事前一括生成（ランタイムコストゼロ）。トレーナーは自分用にYouTube URLや自撮り動画（Storage）を上書き登録可能（バックログの「宿題動画添付」を吸収）。
  - Mobile: `workout_screen.dart` の種目行に「?」アイコン→解説ボトムシート（テキスト＋動画埋め込み/外部リンク）。
  - Web: ExerciseListModal に解説編集導線。
- **データモデル**: `exercise_library(id, name, muscle_group, description_md TEXT, common_mistakes TEXT, default_video_url TEXT, created_at)`、`trainer_exercise_overrides(trainer_id, exercise_id, video_url, note, PRIMARY KEY(trainer_id, exercise_id))`。RLS: libraryは全認証ユーザーSELECT、overridesはtrainer本人ALL＋担当顧客SELECT。
- **バックエンド**: 一括生成はローカルスクリプトで実行しseed migration化（Edge Function不要）。
- **既存コードとの接続点**: `fit-connect-mobile/lib/features/workout/`、Web ExerciseListModal、`workout_exercises`（種目名→libraryへのFK移行は段階的に: まず名前マッチ）。
- **フェーズ分け**: MVP=主要100種目のテキスト解説＋YouTube URL → 拡張=トレーナー自撮り動画（宿題動画添付と統合）。
- **規模感**: M
- **リスク・考慮事項**: YouTube埋め込みは規約上リンク/公式埋め込みプレーヤーのみ（動画DL・改変不可）。トレーナー動画はStorage容量とprivate配信（署名URL）に注意。

### 8-8-C. AI解説動画の完全生成（非推奨・ウォッチのみ）
- **解決する課題**: 同上をフル動画生成で。
- **リスク・判断**: 動画生成AIのコスト・品質（フォームの正確性が担保できず、誤ったフォーム提示は怪我リスク＝プロダクトの信頼を毀損）が現状見合わない。8-8-Bで解説ニーズを満たし、生成動画は年1回程度の技術再評価に留める。
- **規模感**: L+

---

## カテゴリ内の推奨着手順

1. **8-1-A シェアカード（Mobile）** — share_plus導入済み・新テーブル不要でM規模、顧客モチベーションとバイラルの即効性が最も高い。8-4-A 進捗写真をすぐ続けて相乗効果を狙う。
2. **8-8-A AIプラン下書き生成** — トレーナーの時給を直接買う機能で解約防止の本命。既存AI Edge Functionパターン流用で着手可能。8-8-B 種目解説はその補完として並行可。
3. **8-5-C HealthKitワークアウト読み取り（S〜M）＋ 8-6-A Android QA基盤** — 小さく地力を上げる系。特にAndroid apkビルドCIは即日入れる価値がある。
4. **8-7 招待・紹介基盤** — 8-7-Bのコード正規化（anonポリシー撤去とセット）を先行し、8-7-Aの紹介特典はStripe課金導入と同時リリース。
5. **8-2-A チャレンジ / 8-3 スタンプ** — ユーザー数が一定規模に達してから。スタンプはプリセット送信MVPのみ先行切り出し可。
---

# 横断レビュー: 考慮漏れ・依存関係・優先順位

レビュー対象: `/private/tmp/claude-501/-Users-hosidayuya-Documents-work-fit-connect/48aee1d1-4dcd-448d-a12f-fc6b94a19149/scratchpad/sections/section_1.md` 〜 `section_8.md`（全8ファイル読了）。個別カテゴリの設計品質は総じて高い（コード実読に基づく接続点の明示、IAP規約・public バケット問題への言及等）。以下は**カタログを横断して初めて見える問題**に絞る。

---

## 1. 重大な考慮漏れ

### 1-1. 【審査ブロッカー】アカウント削除機能と Sign in with Apple が全カタログに存在しない
コード検証の結果、Mobile は OTP メール＋ **Google Sign-In でアカウント作成が可能**（`/Users/hosidayuya/Documents/work/fit-connect/fit-connect-mobile/lib/features/auth/data/auth_repository.dart`）だが、**アカウント削除機能がどこにもなく、Sign in with Apple も未実装**。
- App Store Guideline **5.1.1(v)**: アカウント作成できるアプリはアプリ内からのアカウント削除が必須。健康データ＋写真を持つ本アプリでは、auth 削除だけでなく records / Storage 画像のカスケード削除設計が必要（工数は小さくない）。
- App Store Guideline **4.8**: サードパーティログイン（Google）を提供する場合、Sign in with Apple 相当の選択肢が必須。
カテゴリ3の法務（4-A）はプライバシーポリシー URL までしかカバーしておらず、この2つは**モバイルリリース自体を止める**。8カテゴリのどこにも記載がないのは最大の抜け。

### 1-2. カテゴリ1の通知設計が「死んでいる疑いのある配管」の上に建っている
カテゴリ1は異常検知・トリアージ・週次サマリーの通知経路をすべて `/api/push-notify`（Web Push）流用としているが、**カテゴリ6の1-D が「呼び出し元が存在せず実際には何も届いていない疑い」と指摘している**。同一カタログ内の矛盾。さらに Web Push は iOS Safari では PWA ホーム画面追加が前提で、スマホでWebを見るトレーナーには届かない。**カテゴリ6の 1-D（棚卸し）はカテゴリ1全体の前提条件**であり、着手順を明示的に依存関係化すべき。トレーナー向け即時通知の実効性は 1-A（LINE）か 1-C（トレーナーモード）が担保するまで「届かない前提」で設計するのが安全。

### 1-3. 通知の横断ガバナンス（通知疲れ対策）が存在しない
各カテゴリが個別に通知上限を設けているが、合算すると顧客宛は「記録リマインダー×2 + セッション前日 + 2時間前 + スキップ前警告 + ストリーク + バッジ + 一斉送信 + 計測 + 週次サマリー」、トレーナー宛は「アラート + 朝トリアージ + 週次 + 未読ダイジェスト + LINE + 予約 + 支払 + 進捗写真」。**ユーザー単位の通知設定センター（種別ごとの opt-in/out）、日次合計上限、quiet hours の共通テーブルがどのカテゴリにも設計されていない**。個別 ON/OFF が各機能の設定画面に散らばると後から統合できなくなる。`notification_preferences` を通知基盤（後述）と同時に先行設計すべき。

### 1-4. AI 機能群のユニットエコノミクス未検証・コスト監視なし
新規 AI 機能は8本以上（返信候補、AI相談=sonnet、週次講評、顧客向け文面、スクショ一括=sonnet、運動ログ推定=sonnet、AIプラン生成=sonnet、スタンプ生成=画像API）。個別 rate limit はあるが、**Pro 月額（未定）に対する AI 原価の試算、トレーナー横断のコスト集計・予算アラートが皆無**。特に AI 相談（2-3万トークン×sonnet×30回/日/trainer 上限）は1人のヘビーユーザーで月数千円級になり得る。ログテーブルも `ai_estimation_logs` / `ai_reply_logs` / `ai_consultation_messages` / `ai_generation_logs` に分散し横断集計が困難な設計。**汎用 `ai_usage_logs(kind, tokens, model)` への統一とコストダッシュボードが先**。

### 1-5. Supabase の枠・egress への言及が動画添付の1箇所のみ
- **Realtime**: Mobile は messages / trainer_schedule で Realtime 購読済み（`/Users/hosidayuya/Documents/work/fit-connect/fit-connect-mobile/lib/features/messages/providers/messages_provider.dart` 等）。カテゴリ3の「plan の Realtime 反映」、カテゴリ4の sessions 購読を足すと、顧客あたり同時接続×チャンネル数が増える。無料枠200同時接続/Pro 500 の上限にトレーナー50人×顧客20人規模で接触し得る。
- **Egress**: 動画（message-media / exercise-videos）と進捗写真の**再生・閲覧による下り帯域課金**（Pro 250GB/月超過分課金）が未考慮。ストレージ容量の試算（カテゴリ6 4-A）はあるが egress の方が先に効く可能性が高い。
- 保持期間ポリシーがバケットごとにバラバラ（動画90日、AI画像48h、進捗写真無期限）。全バケット横断のストレージ予算とライフサイクル表を1枚作るべき。

### 1-6. 「顧客本人の同意」の設計が薄い
健康データ（体重・食事・写真・体脂肪）は要配慮個人情報に準ずる。カテゴリ3の 4-A は同意記録テーブルまで設計しているが、**AI へのデータ送信（AI相談・週次講評は顧客の生活データを本人の操作なしに外部送信する）について、トレーナー同意だけでは足りず顧客側の明示同意が必要**という論点が各カテゴリで「要法務確認」と先送りされたまま、依存タスクとして 4-A に統合されていない。また、トレーナー＝個人情報取扱事業者 / FIT-CONNECT＝委託先という責任分界（規約での明記）も未検討。カテゴリ5 C-3「トレーナーによる記録の書き換え」は本人データの第三者編集であり、監査ログ（後述3節）とセットでないと危うい。

### 1-7. HealthKit 同期の制約が異常検知と干渉する
HealthKit 同期はフォアグラウンド Timer + resume 時のみ（カテゴリ5が正しく現状把握）。つまり**顧客がアプリを開かない限りデータが来ない**。カテゴリ1の「記録途絶3日」検知は「アプリを開いていないだけで実際は計測している」顧客を誤検知し、狼少年化の主要因になる。バックグラウンド配信（HKObserverQuery）はアプリ kill 時の信頼性が低くタイプ別頻度制限もある。検知ルール側で `source='healthkit'` の同期ラグを織り込む設計（例: 途絶判定を「最終アプリ起動」と分離）が必要だがどこにも書かれていない。

### 1-8. カテゴリ間の設計矛盾（決定が必要）
1. **オフライン Outbox（7-A） vs 直接記録（カテゴリ2 4-A）**: 7-A は「記録＝メッセージ送信だから Outbox 一本で済む」ことを設計根拠にしているが、カテゴリ2 4-A は記録をメッセージ非経由の直接 INSERT に変える。両方採用すると Outbox は messages と各 records の両対応が必要になり工数が変わる。**実装順と方式の調停が必須**。
2. **FCM トークンの持ち方**: カテゴリ2・4は「`clients.fcm_token` カラムで十分・テーブル新設不要」、カテゴリ8（8-2-A）は「`device_tokens` テーブル新設が前提」、カテゴリ6（1-C）は「単一カラムは複数端末非対応、将来 device_tokens 化」。トレーナーモード（1アプリ2ロール・PC+スマホ併用）を見据えるなら**最初から `device_tokens` に倒すべき**で、3カテゴリが別前提で走ると手戻りになる。
3. **Pro 降格時の挙動**: Stripe 導入（カテゴリ3）で past_due→free 降格が自動化されるが、降格した瞬間に**顧客のモバイル側 AI 機能が黙って消える**体験、AI相談履歴・週次講評などProデータの扱い（閲覧可/不可）のダウングレードパスがどこにも設計されていない。

---

## 2. カテゴリ間の依存関係・重複（先に作るべき共通基盤）

同じ基盤を複数カテゴリが独立設計している箇所が多数ある。**重複設計（統合必須）**:

| 重複 | カテゴリと内容 |
|---|---|
| 進捗写真 | カテゴリ2 5-A と カテゴリ8 8-4-A が**ほぼ同一の `progress_photos` を二重設計**（スキーマ微差: taken_on/taken_at、weight_kg 有無）。 |
| 周囲径 | カテゴリ5 F-2 `body_measurement_records` と カテゴリ8 8-4-B `body_measurements` が重複。 |
| 種目ライブラリ | カテゴリ6 5-B（trainer_id 所有）と カテゴリ8 8-8-B（グローバルマスタ＋trainer_exercise_overrides）が**同名 `exercise_library` で所有モデルが異なる**。データモデルの根幹なので先に一本化。 |
| 紹介コード | カテゴリ3 5-A と カテゴリ8 8-7-A が同名 `referral_codes`/`referrals` を別内容（Stripe promotion 前提 vs pro_credit_days 前提）で設計。 |
| テンプレート | カテゴリ1 3-B `reply_templates`・7-A `note_templates`、カテゴリ6 3-A `message_templates` — **3カテゴリで「トレーナー定型文」を3テーブル**。カテゴリ1自身が提案する `templates(kind)` 統一に寄せる。 |
| 統計RPC | カテゴリ1 `get_client_stats_summary` と カテゴリ5 E-1 `get_period_stats` は機能が重なる。共用設計を明言しているのはカテゴリ1のみ。 |
| 記録途絶/ストリーク判定 | カテゴリ1 1-A（途絶検知）、カテゴリ2 2-A（streak RPC）・1-B（未記録抽出）で「4テーブル横断の記録日付集合」集計が3箇所。共通ビュー化すべき。 |
| notification_logs | カテゴリ2（notification_logs + dedup_key）と カテゴリ4（sessions に sent_at カラム2本）で冪等化方式が割れている。 |

**先に作るべき共通基盤（着手順込みで具体列挙）**:

1. **migration 欠落修復パック**（1回のPRで）: `fcm_token`（カテゴリ1/2/4/6が各々「先行修復」と重複記載）、`client_notes`、`ticket_templates`/`ticket_subscriptions`、`workout_assignments.status`、`profile-images`/`client-notes` バケット。カテゴリ7 施策3-A/4-A に集約。
2. **pg_cron の migration 化＋cron 失敗監視**（カテゴリ7 5-A）: 本カタログで新設される cron は8本以上（異常検知・週次サマリー・記録リマインダー・セッションリマインダー・予約配信・cleanup・未読ダイジェスト・overdue 更新）。全部この上に載るのに、**job 失敗の監視・アラートはどのカテゴリにもない**。
3. **統一通知ディスパッチャ** `supabase/functions/_shared/push.ts`: FCM v1（parse-message-tags から切り出し）＋ Web Push ＋ 将来 LINE を1モジュールに。`device_tokens` テーブル化の判断、`notification_logs`（冪等）、`notification_preferences`（1-3節）、quiet hours をここで一元化。カテゴリ2 1-B・カテゴリ4・カテゴリ6 がそれぞれ「共通化する」と言っているので、**誰が最初にやるかを決めないと3回作られる**。
4. **署名 URL 両対応ヘルパー＋private バケット標準**（カテゴリ7 2-A Phase 0）: 動画（cat6）、進捗写真（cat2/8）、スタンプ（cat8）、種目動画（cat6/8）の全新バケットがこの上に載る。
5. **`messages.metadata` スキーマレジストリ**: record_ref / silent / recorded_date / meals[] / broadcast_id / skip_tag_parse / payment_request / schedule_proposal / sticker_id と**9種類の metadata 拡張が独立設計**されている。Web/Mobile/parse-message-tags の3者が解釈するため、docs での規約管理と「旧アプリが未知 metadata を受けた時のフォールバック描画」の共通方針が必須。parse-message-tags のスキップ分岐増殖も1箇所の early-return テーブルに整理。
6. **`ai_usage_logs(kind)` 統一＋コスト監視**（1-4節）。

---

## 3. カタログ全体から漏れている改善領域

- **アカウント削除・データエクスポート**（1-1節。App Store 必須＋個情法の開示請求対応。トレーナー退会時の顧客データ清算・引継ぎも未設計）
- **Sign in with Apple**（1-1節）
- **強制アップデート機構**: カテゴリ7 2-A の Storage private 化は「強制アップデート or 2〜4週間待ち」に依存しているのに、バージョンチェック API・強制更新ダイアログ自体がカタログにない。metadata 拡張の多さ（2節）からも早期に必要。
- **エラー監視・可観測性**: Sentry 等の導入、Edge Function / cron / webhook の失敗アラート。数十本の非同期処理を追加する計画に対して監視がゼロ。
- **監査ログ**: トレーナーによる顧客健康データの閲覧・編集（カテゴリ5 C-3 の記録書き換え等）の操作ログ。要配慮データを扱う SaaS の信頼要件。
- **バックアップ/障害復旧**: PITR 有効化、Storage のバックアップ。カテゴリ7 8-A 自身が「誤削除の切り戻しは不可能」と書いているのに復旧手段の設計がない。RPO/RTO 未定義。
- **利用分析基盤**: LP の Vercel Analytics 言及のみ。機能採用率・記録率・返信時間などのプロダクト KPI 計測（PostHog 等）が横断的に欠落。優先順位のチューニング（アラート閾値、スコア式、通知効果）は全部「計測できる」ことが前提なのに。
- **トレーナー複数人・ジム法人対応**: 全テーブルが trainer_id 単一所有前提。組織対応はスキーマの根幹に効くため、少なくとも「v1ではやらない」の明文化と、**顧客の担当トレーナー変更（trainer_id 付け替え時のデータ・RLS の挙動）**だけは先に決めるべき。
- **RLS の自動テスト**: 本カタログは新規 RLS ポリシーを20本以上追加する。anon 全開放事故（カテゴリ7 課題1）の再発防止は「ポリシーを直す」だけでなく「RLS をCIでテストする」仕組みで担保すべき。
- **運営→ユーザーのお知らせチャネル・サポート導線**: 一斉送信はトレーナー→顧客のみ。障害告知・規約改定通知・FAQ・問い合わせ（mailto 言及のみ）の運営側チャネルがない。
- **アクセシビリティ / 多言語**: 言及ゼロ。当面優先度低で構わないが、方針の明文化（対応しない範囲の宣言）は必要。

---

## 4. 優先順位への提言（全体横断トップ10）

「収益ゼロ・セキュリティ穴あり・審査ブロッカーあり」という現状から、**出血停止 → 売れる状態 → 基盤 → 価値機能**の順。

| # | 施策 | 根拠 |
|---|---|---|
| 1 | **anon ポリシー DROP＋LINE レガシー撤去**（cat7 1-A/6-A、〜1日） | 未認証で全顧客の健康データが読み書き可能。存続リスクの即時封鎖。全カテゴリが「先にやれ」と言っている唯一の項目。 |
| 2 | **migration 欠落修復パック＋pg_cron migration 化**（cat7 3-A/4-A/5-A＋fcm_token/ticket系、2-3日） | 8カテゴリ中5カテゴリが個別に「先行修復」を前提化。1回で全部やる。 |
| 3 | **法務一式＋アカウント削除＋Sign in with Apple**（cat3 4-A＋本レビュー1-1節） | 課金・LP・App Store 審査すべての前提。アカウント削除と Apple ログインをスコープに追加しないと審査で止まる。 |
| 4 | **Stripe SaaS 課金＋LP**（cat3 1-A/3-A、計1-2週） | 受け皿（subscription_plan・Mobile ゲート）は実装済みで、最小工数で収益ゼロ→有に。`allow_promotion_codes` も同時有効化。 |
| 5 | **通知基盤の統一**（cat6 1-D 棚卸し → `_shared/push.ts`＋device_tokens＋notification_logs/preferences → cat2 3-A 権限プライミング） | cat1/2/4/6 の通知系機能すべての前提。Web Push が死んでいる疑いの解消が最初。 |
| 6 | **ワークアウト繰越不具合修正**（cat2 8-A） | 唯一の「既存機能が壊れている」項目。既存ユーザーの信頼を毀損中で、新機能より先。 |
| 7 | **Storage private 化**（cat7 2-A、強制アップデート機構もここで導入） | 食事・身体写真の漏洩リスク解消＋進捗写真/動画系（cat2 5-A、cat6 4-A、cat8 8-4-A）全部の前提。 |
| 8 | **Mobile セッション表示＋セッションリマインダー MVP**（cat4 課題2/3） | S〜M 規模で顧客体験が即改善。#5 の通知基盤の最初の消費者としてちょうど良い。 |
| 9 | **異常検知＋デイリートリアージ**（cat1 1-A/2-A） | トレーナー価値の核。alerts テーブルは cat1 内の他機能すべてが消費するため 3-A（AI返信）より先。 |
| 10 | **顧客リテンション束**（cat2 1-A ローカルリマインダー → 4-A 直接記録 → 2-A ストリーク。※4-A 採用時は cat7 7-A Outbox の設計を records 対応に改訂） | 記録の摩擦低減→習慣化の順。1-8節の Outbox 矛盾はここで決着させる。 |

**11位以下（次スプリント候補）**: AI 返信候補（cat1 3-A、Pro の目玉として #4 直後でも可）、LINE 通知（cat6 1-A）、動画添付（cat6 4-A）、体組成＋期間統計（cat5 F-1/E-1）、予約リクエスト（cat4 1-A）、Stripe Connect（cat3 2-B）。**シェアカード（cat8 8-1-A）とチャレンジ（8-2-A）はユーザー母数が立つまで着手見送り**が妥当（cat8 自身の自己評価どおり）。

最後に一言。このカタログの最大の弱点は個々の機能設計ではなく、**「8人が別々に家を建てている」こと**。特に通知・テンプレート・進捗写真・種目ライブラリ・紹介コードの5つは、統合の意思決定をしないまま並行着手すると確実に二重実装になる。実装前に本レビュー2節の統合判断だけは親タスクで確定させることを強く推奨する。