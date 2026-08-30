# FIT-CONNECT - 新機能タスク一覧

**作成日**: 2026年3月29日
**バージョン**: 2.0
**進捗状況**: フェーズ1 完了 / フェーズ2 2.1〜2.5 完了（2.4 任意項目のみバックログ）/ フェーズ3〜10 未着手
**最終更新**: 2026年8月30日 - フェーズ8.2 完了（Storage 4バケット private 化 + 署名URL + 強制アップデート機構 + AI画像 orphan cleanup。リモート適用済み）。各タスクの詳細設計は `docs/tasks/2026-07-08-solution-catalog.md`、共通基盤の設計決定は `docs/tasks/2026-07-10-integration-decisions.md` を参照

> **2026-04-26 モノレポ化完了**: 旧 `fit-connect-mobile` リポジトリを `git subtree` で取り込み、単一 git リポジトリで Web/Mobile 両方を管理する構成に移行。詳細は `docs/tasks/2026-04-26-monorepo-migration.md`。

---

## 目次

1. [フェーズ1: ヘルスケア連携（Mobile）](#フェーズ1-ヘルスケア連携mobile)
2. [フェーズ2: LLM（Claude）カロリー計算（Mobile + Supabase）](#フェーズ2-llmclaudeカロリー計算mobile--supabase)
3. [フェーズ3: オンボーディングフロー（Mobile）](#フェーズ3-オンボーディングフローmobile)
4. [フェーズ4: ランディングページ（Web）](#フェーズ4-ランディングページweb)
5. [フェーズ5: セキュリティ・基盤修復【緊急】](#フェーズ5-セキュリティ基盤修復緊急)
6. [フェーズ6: 収益化・リリース準備](#フェーズ6-収益化リリース準備)
7. [フェーズ7: 通知基盤統一](#フェーズ7-通知基盤統一)
8. [フェーズ8: 不具合修正・顧客体験の底上げ](#フェーズ8-不具合修正顧客体験の底上げ)
9. [フェーズ9: トレーナー介入機能](#フェーズ9-トレーナー介入機能)
10. [フェーズ10: リテンション機能](#フェーズ10-リテンション機能)
11. [バックログ（フェーズ11以降の候補）](#バックログフェーズ11以降の候補)

---

## 実装状況サマリー

| フェーズ | 機能 | 対象 | 進捗 | 状態 |
|---------|------|------|------|------|
| 1 | ヘルスケア連携（体重・睡眠） | Mobile + Web | 100% | 🟢 体重・睡眠連携・バックグラウンド同期・トレーナー可視化 完了 |
| 2 | LLM カロリー計算 | Mobile + Supabase | 90% | 🟢 2.1〜2.5 完了（スクショ取り込み含む）/ 2.4任意項目のみバックログ |
| 3 | オンボーディングフロー | Mobile | 90% | 🟡 3.1〜3.4 完了（cat2 3-A: 同意ダイアログ・通知権限プライミング・後段フロー・はじめの3ステップカード。2026/07/19、PR: feature/mobile-onboarding）/ コーチマーク・PageView式アプリ紹介の拡張のみ残 |
| 4 | ランディングページ | Web | 90% | 🟡 4.1〜4.4 + メタタグ・OGP + アナリティクス（GA4）完了（2026/07/12）/ Lighthouse最適化 残 |
| 5 | セキュリティ・基盤修復【緊急】 | Supabase + Web | 75% | 🟡 5.1・5.2・5.5 完了 / 5.3 cron migration 化済み・Vault 登録はユーザー作業待ち（手順書: `2026-07-10-cron-vault-setup.md`）/ 5.4 未着手 |
| 6 | 収益化・リリース準備（Stripe/法務/アカウント削除/Apple Sign-In） | Web + Mobile + Supabase | 70% | 🟡 6.2 完了（アカウント削除 + Sign in with Apple）/ 6.1 完了（法務3ページ + user_consents + signup同意。Mobile側の顧客同意UIはフェーズ3の同意ダイアログとして実装済み 2026/07/19）/ 6.3 Stripe課金コア実装済み（テスト・本番切替はオーナーのStripeセットアップ待ち。手順書: 2026-07-12-stripe-setup-guide.md）/ 6.4 完了（フェーズ4として実装済み）/ 6.5 支払記録 実装済み（領収書PDF・Stripe Connect は後回し） |
| 7 | 通知基盤統一（device_tokens + 共通ディスパッチャ） | Supabase + Web + Mobile | 100% | 🟢 7.1〜7.4 完了（7.4 通知権限プライミングはフェーズ3の 3.2 として実装。2026/07/19） |
| 8 | 不具合修正・顧客体験の底上げ | Mobile + Web + Supabase | 70% | 🟡 8.1 完了（2026/07/10）/ 8.2 Storage private化+署名URL+強制アップデート+orphan cleanup 完了（2026/08/30、リモート適用済み）/ 8.3 未着手 |
| 9 | トレーナー介入機能（異常検知・トリアージ） | Web + Supabase | 0% | 🔴 未着手 |
| 10 | リテンション機能（リマインダー・直接記録・ストリーク） | Mobile + Supabase | 0% | 🔴 未着手 |

> フェーズ5〜10 の出典: `docs/tasks/2026-07-08-solution-catalog.md`（施策詳細）/ `docs/tasks/2026-07-10-integration-decisions.md`（共通基盤の設計決定。**カタログと矛盾する場合はこちらが優先**）。「cat〇 △-△」はカタログ内の施策番号。

---

## フェーズ1: ヘルスケア連携（Mobile）

**目的**: Apple HealthKit / Google Health Connect から体重・睡眠データを取得し、アプリ内の記録と連携する

**概要**: 要件は実装着手時に詳細化する

### タスク

- [x] **1.1 HealthKit / Health Connect プラグイン導入**
  - [x] health パッケージ導入・権限設定
  - [x] iOS Info.plist / Android permissions 設定
  - [x] HealthRepository クラス作成（権限リクエスト・データ取得の抽象化）

- [x] **1.2 体重データ連携**
  - [x] HealthKit/Health Connect から体重データ読み取り（読み取りのみ）
  - [x] 既存の weight_records との同期ロジック（重複排除・メッセージ記録優先）
  - [x] 専用ヘルスケア連携設定画面（設定画面から遷移）
  - [x] アプリ起動時 + 手動同期ボタン
  - [x] 体重記録リストにソースアイコン表示

- [x] **1.3 睡眠データ連携** （2026-04-25 完了）
  - [x] HealthKit/Health Connect から睡眠データ読み取り（HealthRepository.getSleepData）
  - [x] 睡眠データモデル作成（sleep_records テーブル + RLS 5ポリシー、SleepRecord モデル + enums）
  - [x] 睡眠記録画面の作成（SleepRecordScreen: サマリー/週間/履歴）
  - [x] ホーム画面への睡眠サマリー表示（SleepSummaryCard: 3状態 + エラー時UX）
  - [x] 朝の目覚めダイアログ（4:00-12:00 JST、設定でON/OFF）
  - [x] 設定画面に睡眠トグル + 朝ダイアログトグル追加
  - 注: ローカル/リモートの Supabase に migration `20260422000000_create_sleep_records.sql` の適用が必要

- [x] **1.4 バックグラウンド同期** （2026-04-26 完了）
  - [x] バックグラウンドでの定期同期設定（フォアグラウンド時 `Timer.periodic` 1時間 + アプリ resume 時に lastSync が1時間超で再同期、`lib/app.dart`）
  - [x] 同期状態の表示（相対時間 + status アイコン + エラー詳細行、`HealthSettingsState` に `lastSyncStatus` `lastSyncError` 追加、SharedPreferences 永続化）
  - [x] エラー時のリトライ・通知（`_runWithRetry` 指数バックオフ最大3回 1s/2s、永続失敗時に `NotificationService.showSyncErrorNotification` 通知 ID=9001）
  - 注: `workmanager` は採用せず（iOS 制約と native 設定の複雑さを考慮）。フォアグラウンド/resume ベースで日常利用に十分な頻度を確保
  - 注: build_runner / flutter analyze はサンドボックスで未実行のため、ローカル環境で `dart run build_runner build --delete-conflicting-outputs` の実行を推奨

- [x] **1.5 睡眠データのトレーナー可視化（Web）** （2026-04-27 完了）
  - [x] Web側の型定義追加（`fit-connect/src/types/client.ts`: `SleepRecord`, `WAKEUP_RATING_OPTIONS`, `SLEEP_SOURCE_LABELS`）
  - [x] 担当トレーナーが閲覧可能になる RLS 調整 → 1.3 の `sleep_records_trainer_select` ポリシーで既に対応済（追加マイグレーション不要）
  - [x] クライアント詳細画面への睡眠サマリー・履歴表示
    - 新規タブ「睡眠」追加（page.tsx 統合 + lucide `Moon` アイコン）
    - `SleepChart`（Recharts ComposedChart, 推奨睡眠帯 7-9h ハイライト, 内訳ツールチップ）
    - `SleepTab`（期間フィルター 1W/1M/3M/ALL, 4種統計, 直近5件リスト, ソースバッジ）
    - `getSleepRecords`（直近180日, RLS委任）
  - [x] 睡眠データを踏まえたコメント/指導フローとの統合検討
    - `SummaryTab` に「睡眠（直近7日）」カード追加 — 平均睡眠時間・平均目覚め評価・記録日数
    - 平均6h未満 or 評価1.5以下で「改善余地あり」バッジ表示
    - メッセージ画面への明示的動線追加は次回タスクへ繰り延べ

---

## フェーズ2: LLM（Claude）カロリー計算（Mobile + Supabase）

**目的**: 食事の写真・テキスト入力、および他社食事アプリ（あすけん等）の画面スクリーンショットから、Claude API を使ってカロリー・栄養素を自動推定／取り込みする

**概要**: 要件は実装着手時に詳細化する

### タスク

- [x] **2.1 Claude API 連携基盤（Supabase Edge Function）**（2026-05-03 完了）
  - [x] Edge Function `estimate-meal-nutrition` 作成（Haiku 4.5 + prompt caching）
  - [x] プロンプト設計（食事内容 → 食品リスト + カロリー + PFC 推定）
  - [x] レスポンスのパース・バリデーション（コードフェンス除去 + totals 再計算）
  - [x] API キー管理（Supabase Secrets `ANTHROPIC_API_KEY`）
  - [x] Rate limit (`ai_estimation_logs` テーブル: 50/client/day, 1000/trainer/day)
  - [x] Subscription gate（`trainers.subscription_plan = 'pro'` のクライアントのみ）

- [x] **2.2 テキスト入力からのカロリー推定**（2026-05-03 完了）
  - [x] `MealTagForm` を 3-state ステートマシン化（input → loading → confirm）
  - [x] 推定結果の表示 UI（食品リスト + 編集可能な合計 kcal/P/F/C）
  - [x] 推定結果の確認・修正フロー（送信前にトレーナーへ送るデータをクライアントが調整可能）
  - [x] meal_records への保存統合（`messages.metadata` 経由 + `parse-message-tags` webhook 改修）
  - [x] `aiFeaturesEnabledProvider` で課金ゲート（free プランは AI を呼ばず既存挙動）
  - [x] エラー時フォールバック（snackbar + 「AIなしで送信」アクション）

- [x] **2.3 画像からのカロリー推定**（2026-05-09 完了 / QA: 2026-05-16）
  - [x] 食事写真撮影/選択 → Edge Function → Claude Vision → 結果表示
  - [x] 画像のアップロード・前処理（既存 image_picker quality 80 / max 1920x1080 で対応）
  - [x] 複数料理の認識・個別推定（最大3枚を1リクエストにまとめて claude-sonnet-4-6 へ）
  - [x] 推定結果の確認・修正フロー（PFC 編集可、画像は確認シートで読み取り専用ロック）
  - 注: image_urls の有無で claude-sonnet-4-6（画像）/ claude-haiku-4-5（テキスト）を動的切替。EMPTY_RESULT(422) エラーコード新設で「食事を識別できなかった」UI 分岐を実現
  - 注: 「挿入」時に message-photos/${userId}/ai/ へ upload、File↔URL Map で「戻る」再試行時の再 upload を防止。orphan cleanup ジョブは未実装（パス分離済み、将来課題）
  - 注: QA で発見した「推定中ネットワーク断→無限ロード」を client timeout（estimate 45s / upload 30s）追加で修正済み

- [x] **2.4 既存フローとの統合**（2026-05-31 (a) 完了 / 任意項目はバックログ）
  - [x] 「AI推定」ボタンの明示化（食事記録画面は閲覧専用のまま維持する方針に決定。AI推定をメッセージ #食事 タグフォーム内の明示ボタンへ分離）
    - 入力ステートの「挿入」1ボタンを、Pro クライアントでは「**AI推定**」（主・FilledButton・sparklesアイコン）＋「**AIなしで挿入**」（副・OutlinedButton）の2ボタンへ。free クライアントは従来どおり「挿入」1つ
    - **挿入経路から暗黙のAI推定を完全撤去**し、「挿入＝テキスト挿入」「AI推定＝推定」と責務分離（`_handleInsert` を `_handleInsert`(テキストのみ) と `_handleEstimate`(AI専用) に分割）
    - フラッシュ対策: `aiFeaturesEnabledProvider` 未解決時は保守的に free 版を表示（lessons.md「AsyncValueゲート」原則踏襲）
    - Pro 2ボタン版の `@Preview` 追加（`previewMealTagFormPro`, provider override）
    - 対象: `lib/features/messages/presentation/widgets/structured_tag_form.dart`（1ファイル）
  - 注: 食事記録画面への直接入力UI新設は見送り（プロダクトモデル「食事記録はメッセージ経由のみ」を維持）
  - [ ] メッセージタグ（#食事）からの自動推定（任意）→ **バックログ**（現状すでに明示AI推定で対応。手入力 #食事 送信の自動推定は将来課題）
  - [ ] 推定履歴・精度フィードバック機能（任意）→ **バックログ**（スキーマ・モデル・UIをゼロ新設要、規模大）

- [x] **2.5 食事アプリスクショ画像分析**（2026-05-31 完了）
  - [x] スクショ判定・抽出用プロンプト設計 → Edge Function に `input_kind='screenshot'` 分岐＋専用 `SCREENSHOT_SYSTEM_PROMPT`（「画面の数値を読み取る／推定しない」「app_name 自動検出」）
  - [x] Edge Function 拡張（2.1 を再利用、`input_kind='screenshot'` 分岐。claude-sonnet-4-6 画像ルート流用）
  - [x] 抽出フィールド: カロリー・PFC・食品名リスト・app_name（v1スコープ＝1食分の合計のみ。食事区分はフォーム選択を維持）
  - [x] 抽出結果の確認・修正フロー（2.3 の `MealEstimationConfirmView` を流用＋「<app名> から読み取り」ラベル）
  - [x] meal_records への保存統合（新カラム `ai_source` に `screenshot:<app名>` を記録。`text`/`photo` 経路も保存）
  - [x] 失敗時のフォールバック（`EMPTY_RESULT(422)` → 料理写真/テキスト入力へ誘導）
  - 入口: 食事タグフォーム上部にセグメント切替「料理を記録 / 他アプリから取込」（**Pro のみ**表示。free は従来フォーム）
  - 設計: `docs/superpowers/specs/2026-05-31-meal-screenshot-import-design.md` / 計画: `docs/superpowers/plans/2026-05-31-meal-screenshot-import.md`
  - 注: リモート反映（migration 適用 + Edge Function 2件デプロイ）は QA 後にユーザー確認のうえ実施
  - **バックログ（v1スコープ外）**: 1日サマリーからの複数記録一括生成 / スクショからの日付・食事区分自動読み取り（過去日付記録）
  - 補足: 他アプリユーザーの流入導線として位置付け（`docs/tasks/2026-04-29-feature-backlog.md` 1. AI機能より昇格）

---

## フェーズ3: オンボーディングフロー（Mobile）

**目的**: 新規ユーザーがアプリの使い方を理解し、初期設定をスムーズに完了できるフローを実装する

**詳細設計**: カタログ cat2 3-A（+ 3-B はじめの3ステップカード）

### タスク

- [x] **3.1 同意ダイアログ**（cat3 4-A の Mobile 側 = 6.1 残タスクの解消）
  - [x] terms / privacy / ai_processing の3 document をバージョン付きで `user_consents` に記録
  - [x] 初回サインイン後に表示・規約改定時は再同意を要求
  - 注: `ai_processing` は migration `20260719020000_onboarding_and_ai_consent.sql` で `user_consents.document` の CHECK を拡張して追加（健康データの AI 送信への顧客本人の明示同意。横断レビュー1-6節対応）

- [x] **3.2 通知権限プライミング**（= 7.4）
  - [x] 起動時の即時 requestPermission を廃止し、価値説明画面経由の権限リクエストに変更

- [x] **3.3 オンボーディング後段フロー**
  - [x] ヘルスケア連携提案（フェーズ1と連動）
  - [x] ~~夕食リマインダー提案（21:00）~~ → 2026-08-10 オーナー判断で削除（夕食のみ特別扱いする根拠が薄いため。フェーズ10で時刻・記録種類を選べる汎用記録リマインダーとして再検討）
  - [x] 完了状態の DB 管理: `clients.onboarding_completed_at`（migration `20260719020000`。Mobile が本人 RLS（clients_update_own）で自行 UPDATE。NULL = 未完了。既存ユーザーは NULL のまま）

- [x] **3.4 はじめの3ステップカード**（cat2 3-B）
  - [x] ホーム最上部に表示・達成状態はデータから導出・14日で消滅

- [ ] **3.5 拡張（任意・バックログ）**
  - [ ] コーチマーク（主要画面での初回表示ツールチップ）
  - [ ] PageView ベースのスワイプ式アプリ紹介（インジケーター・スキップ・次へボタン）

---

## フェーズ4: ランディングページ（Web）

**目的**: FIT-CONNECT のサービス紹介ランディングページを作成する（fit-connect リポジトリ）

**概要**: 要件は実装着手時に詳細化する

### タスク

- [x] **4.1 ページ構成・デザイン**
  - [x] ワイヤーフレーム・セクション構成の策定
  - [x] デザイントークン適用（Noto Sans JP、border-radius: 6px）
  - [x] レスポンシブデザイン（モバイル/タブレット/デスクトップ）

- [x] **4.2 ヒーローセクション**
  - [x] キャッチコピー・CTA ボタン
  - [x] アプリスクリーンショット or モックアップ表示

- [x] **4.3 機能紹介セクション**
  - [x] 主要機能の紹介（メッセージ・記録・ワークアウト等）
  - [x] アイコン・イラスト付き説明カード

- [x] **4.4 料金・CTA セクション**
  - [x] 料金プラン表示（あれば）
  - [x] サインアップ/問い合わせ CTA
  - [x] フッター（利用規約・プライバシーポリシーリンク）
  - 補足: 4.1〜4.4 は LP実装 2026/07/12、PR: feature/landing-page。実績・お客様の声はリリース前のため未掲載

- [ ] **4.5 SEO・パフォーマンス**
  - [x] メタタグ・OGP 設定
    - layout.tsx の metadata（metadataBase/title template/OGP/Twitter Card）+ robots.ts + sitemap.ts + opengraph-image.tsx（2026/07/12、同PR。URL は NEXT_PUBLIC_APP_URL で切替、src/lib/siteConfig.ts に一元化）
  - [ ] Lighthouse スコア最適化
  - [x] アナリティクス導入（ツール選定はオーナー判断待ち）
    - GA4 選定（2026/07/12 オーナー決定）。コード実装済み・計測IDの設定待ち（手順書: 2026-07-12-ga4-setup-guide.md）

---

## フェーズ5: セキュリティ・基盤修復【緊急】

**目的**: 未認証アクセス可能な個人情報の穴を即時封鎖し、スキーマドリフトを解消して以後の全フェーズの土台を正常化する
**詳細設計**: カタログ カテゴリ7 / 規模: 合計 3〜4日

### タスク

- [x] **5.1 anon ポリシー DROP + LINE レガシー撤去**（cat7 1-A + 6-A、同一PR推奨・〜1日）
  - [x] `clients` の anon 全行 SELECT/INSERT/UPDATE ポリシー3本を DROP する migration
  - [x] `/liff` ページ・`/api/line/webhook`・`saveLineUser.ts` の削除、`line_user_id` 型参照の整理
  - [x] 適用後、anon キーで `clients` が 0 行になることを確認
  - [x] （後続・任意）anon への書き込み系 GRANT の REVOKE（cat7 1-B、安定稼働1〜2週間後）
  - 2026-07-10 完了（PR #62）。リモート適用済み・anon キーで `clients` が 0 行になることを検証済み
- [x] **5.2 migration 欠落修復パック**（cat7 3-A / 4-A + 追加発見分、〜2日）
  - [x] `client_notes` の CREATE TABLE 復元 migration（冪等・リモート実スキーマと `db diff` で照合してから）
  - [x] `workout_assignments.status` 列の追認 migration + バックフィル（`is_completed` の段階廃止は別タスク）
  - [x] `clients.fcm_token` / `trainers.fcm_token` カラムの追認 migration（フェーズ7の device_tokens 移行の前提）
  - [x] `profile-images` / `client-notes` Storage バケットの作成 migration（現状コード管理外）
  - [x] ローカル `supabase db reset` が通ることを確認
  - 2026-07-10 完了（PR #63）。実際のドリフトは上記に加え workout 系全域（workout_plans / workout_exercises / workout_assignments / workout_assignment_exercises）・tickets 系・Seed.sql にまで及んでいたため、修復 migration 3本（`20260710010000`〜`010002`）で追認
  - 空DBからの `supabase db reset` が通ることを確認し復旧済み
- [ ] **5.3 pg_cron の migration 化**（cat7 5-A、〜1日）
  - [ ] Vault に `project_url` / `service_role_key` を登録（手順を docs に記録）→ **ユーザー作業待ち**（手順書: `docs/tasks/2026-07-10-cron-vault-setup.md`）
  - [x] `auto-skip-workouts` の cron を pg_cron + pg_net で migration 化（2026-07-10、`20260710020000_codify_cron_jobs.sql`）
  - [ ] `cron.job_run_details` の失敗監視ジョブの設計（フェーズ7の通知ディスパッチャ完成後に配線）
  - 発見事項（2026-07-10 リモートDB実測）:
    - `issue_recurring_tickets()` 関数 + cron ジョブ `issue-recurring-tickets` も migration 管理外だった → `20260710020000` で追認（既存ジョブには触れない存在チェック付き・リモート no-op）
    - `auto-skip-workouts` は Edge Function がデプロイ済み ACTIVE なのに cron が存在せず、機能が休眠していた → **無効(inactive)状態で cron 登録**。有効化すると現存25件の期限切れ pending 課題が初回実行で一括スキップされるため、有効化は繰越問題（cat2 8-A）修正後にユーザー判断
- [ ] **5.4 RLS の CI テスト基盤**（統合判断7-4、任意だが推奨）
  - [ ] anon/authenticated/他人ロールでのアクセス可否テストを `supabase/tests/` に新設（再発防止）
- [x] **5.5 チケット系ほか API Route の認証ハードニング**（cat7 派生、〜1日）
  - [x] `src/lib/api/guards.ts` を新設: `requireTrainer()`（@supabase/ssr の cookie セッション認証・401）+ `notFoundResponse()`（404）+ `trainerOwns*` 所有検証10種（client/ticket/template/subscription/note/message/plan/assignment/assignmentExercise/session）。ユニットテスト付き
  - [x] 未認証で `supabaseAdmin`(service_role) を使い、リクエストの trainerId/clientId/userId を無検証で信頼していた **22 ルートファイル（全32 export メソッド）** をガード。trainer_id は必ず `auth.user.id` から導出、対象リソースの所有をサーバー側で検証（RLS バイパス穴の封鎖）
  - [x] レスポンス規約: 未認証→401 `UNAUTHORIZED` / 非所有・不在→404 `NOT_FOUND` / trainers/[id] の id≠self のみ 403 `FORBIDDEN`
  - [x] フロントの fetch から now-ignored な trainerId/userId 送信を撤去（挙動不変のクリーンアップ）
  - [x] 対象外: `/api/billing/*`（既にセッション認証）・`/api/stripe/webhook`（署名認証）・`/api/push-notify`（supabaseAdmin 不使用・PUSH_API_KEY ゲート）
  - [x] tsc / vitest 70 / lint 0 / next build 通過。ブラウザでチケット・カルテ CRUD / メッセージ送信を確認、未ログイン時に対象12ルートが 401 を返すことを curl で確認
  - 2026-07-13 完了（PR fix/api-auth-hardening）。フェーズ6.3 の billing 認証パターンを全ルートに横展開

---

## フェーズ6: 収益化・リリース準備

**目的**: 「Proプランを売る手段が無い」「App Store 審査に通らない」状態を解消し、収益ゼロ→有にする
**詳細設計**: カタログ カテゴリ3 + 横断レビュー1-1節 / 規模: 合計 3〜4週

### タスク

- [x] **6.1 法務一式 + 同意フロー**（cat3 4-A、全ての前提）
  - [x] 利用規約・プライバシーポリシー・特商法表記ページ（Web）+ サインアップ時同意記録
    - 3ページ + `user_consents` テーブル（migration `20260711000000`）+ Web signup 同意チェック実装済み（2026/07/11）。事業者情報は【要記入】プレースホルダのまま、公開前に弁護士レビュー推奨
  - [x] 健康データのAI送信（外部API）に関する顧客側の明示同意の設計（横断レビュー1-6節）
  - [x] トレーナー＝個人情報取扱事業者 / FIT-CONNECT＝委託先の責任分界を規約に明記
    - 上記2件は規約・プライバシーポリシーの文面で対応済み。残っていた **Mobile側の同意UI（顧客の登録フロー）** はフェーズ3の 3.1 同意ダイアログ（`ai_processing` 同意を含む）として実装（2026/07/19、PR: feature/mobile-onboarding）
- [ ] **6.2 アカウント削除 + Sign in with Apple**【App Store 審査ブロッカー】（横断レビュー1-1節）
  - [x] Mobile アプリ内からのアカウント削除（Guideline 5.1.1(v)）: auth 削除 + records/Storage 画像のカスケード削除 Edge Function
    - Edge Function `delete-account` 新設（JWT 自前検証・削除順序: clients DELETE(子は CASCADE) → messages DELETE → Storage ベストエフォート → auth.users 削除。設定画面から2段階確認で実行）
  - [x] Sign in with Apple 追加（Guideline 4.8。Google Sign-In があるため必須）
    - 実装済み・実機ログイン確認済み（2026/07/11、PR #68）
  - [ ] （関連）データエクスポート（個情法の開示請求対応）の方針決定
- [ ] **6.3 Stripe SaaS 課金**（cat3 1-A、トレーナーサブスク）
  - 価格確定（2026-07-12）: Free ¥0（顧客3人・AI月30回プール）/ Pro ¥2,980税込（〜10人）/ Business ¥6,980税込（〜30人）。14日Proトライアル（クレカ無し）・月額のみ・税込表示。レートリミット 10回/顧客/日 + 100回/顧客/月（超過時テキストのみ）。詳細: docs/tasks/2026-07-11-pro-pricing-proposal.md §8
  - [x] Stripe Checkout + Customer Portal + webhook（`subscription_plan` 自動更新）
    - PR: `feature/stripe-billing-core`（API Routes: checkout / portal / status / webhook 署名検証）。14日トライアルは DB 管理（`trial_ends_at`、Stripe 非関与）、`trainer_billing` テーブル新設、`subscription_plan` のクライアント改ざん穴もカラム権限で封鎖（2026/07/12）。テスト・本番切替はオーナーの Stripe セットアップ待ち（手順書: docs/tasks/2026-07-12-stripe-setup-guide.md）
  - [ ] Pro 降格時のモバイル側挙動の設計（AI機能・Pro データの扱い。横断レビュー1-8節）
  - [ ] Mobile 内では Pro 購入導線に言及しない（IAP 規約対応。表示は機能ゲートのみ。現状違反なしを確認済みだが継続ルールとして残す）
  - [x] `allow_promotion_codes` 有効化（将来の紹介コード cat3 5-A の受け皿）
    - Checkout Session 作成時に有効化済み（`feature/stripe-billing-core`、2026/07/12）
  - [x] 顧客数上限の enforcement（Free 3 / Pro 10 / Business 30。DB側ゲート + 超過時アップグレード誘導UI）【PR2スコープ】
    - DBトリガー enforce_client_limit + Web招待モーダルの誘導UI + Mobile登録エラーハンドリング（2026/07/12、PR: feature/plan-limits-enforcement）
  - [x] AIクォータ新値への書き換え（10回/顧客/日 + 100回/顧客/月 + Free 月30回プール、超過時テキストのみ）【PR2スコープ】
    - 10回/顧客/日 + 100回/顧客/月（超過時テキストのみ）+ Free月30回プール。Freeにも AI お試し開放、Mobile の AI ボタンゲートも開放（2026/07/12、同PR）
  - [ ] 特商法ページの価格記入（提供開始時）【PR2スコープ】
- [x] **6.4 LP + 料金ページ**（cat3 3-A = 既存フェーズ4 を包含。フェーズ4のタスクリストで管理）— フェーズ4として実装済み（2026/07/12）
- [ ] **6.5 支払記録・未払い管理**（cat3 2-A、チケット/月契約と金銭の接続。Stripe Connect 決済代行 cat3 2-B はバックログ）
  - [x] price_yen 追加（テンプレート/チケット）
  - [x] payments テーブル + RLS + RLSテスト
  - [x] 発行時・月契約発行時の支払予定自動生成（issue_recurring_tickets 改修）
  - [x] /tickets 支払いタブ（未払い一覧・消込）
  - [x] ダッシュボード売上・未収金カード
  - [ ] 領収書PDF（拡張1・後回し）
  - [ ] Stripe Connect 決済代行（cat3 2-B、バックログ）
  - 補足: overdue は cron を作らず due_date から UI 導出（2026/07/12 設計判断）。PR: feature/payment-records

---

## フェーズ7: 通知基盤統一

**目的**: フェーズ8以降の全通知系機能（リマインダー・アラート・一斉送信）の共通土台を1回だけ作る
**詳細設計**: 統合判断1 + カタログ cat6 1-D / 規模: 合計 1〜2週
**前提**: フェーズ5.2（fcm_token 追認）完了

### タスク

- [x] **7.1 通知配管の棚卸し・修理**（cat6 1-D）✅ 完了（2026/07/19）
  - [x] messages webhook payload の `receiver_type` 有無をリモートで確認（無ければ通知が skip されている）
  - [x] 死んでいる `/api/push-notify`（呼び出し元ゼロ確認済み）の廃止判断
  - 補足: receiver_type はリモート payload に含まれることを実測確認（2026/07/19）。ただし migrations 側の関数定義にドリフトがあり repair migration 20260719000000 で追認。/api/push-notify は呼び出し元ゼロを全数grepで確定 — 7.3 で削除実施（2026/07/19。web-push / @types/web-push 依存も除去）
- [x] **7.2 `device_tokens` テーブル + 移行**（統合判断1）✅ 完了（2026/07/19）
  - [x] `device_tokens` 新設 migration（user_type/platform 対応、UNIQUE(user_id, token)）✅ 完了（migration 20260719000100 + RLSテスト）
  - [x] Mobile: `clients.fcm_token` との両書き → 両読み → 新テーブルのみ の3段階移行 ✅ stage1（両書き）完了（両読み・新テーブル単独化は 7.3 以降で実施）
  - [x] トレーナーのトークン登録経路の新設（現状トレーナー通知は実質不達）✅ 完了（Web Push 購読の device_tokens 両書きで到達経路を確保。送信側の切替は 7.3）
- [x] **7.3 統一通知ディスパッチャ `_shared/push.ts`** ✅ 完了（2026/07/19）
  - [x] `parse-message-tags` 内のベタ書き FCM 送信（JWT生成含む）を切り出し
  - [x] Web Push 送出の統合（`push_subscriptions` → device_tokens(platform='web_push') 移行）※送信の有効化は Edge Functions への VAPID シークレット設定待ち（手順書: `2026-07-19-webpush-vapid-setup.md`）。未設定の間は Web Push はスキップされ Mobile FCM のみ送信
  - [x] `notification_preferences`（種別 opt-in/out + quiet hours）+ `notification_logs`（dedup_key 冪等）新設
  - [x] 通知設定センター UI（Mobile 設定画面 / Web 設定画面に各1箇所）※種別トグル（メッセージ受信 / 目標達成）のみ。quiet hours の UI は未実装（スキーマとディスパッチャ側は対応済み）
  - 補足: 死にコード `/api/push-notify` の削除もここで実施（2026/07/19）
- [x] **7.4 通知権限プライミング**（cat2 3-A の一部先行。オンボーディング＝フェーズ3と連動）✅ 完了（フェーズ3の 3.2 として実装済み。2026/07/19）

---

## フェーズ8: 不具合修正・顧客体験の底上げ

**目的**: 既存機能の壊れ・危険を直し、顧客が毎日開く理由を増やす
**詳細設計**: カタログ cat2 8-A / cat7 2-A / cat4 課題2・3 / 規模: 合計 2〜3週

### タスク

- [ ] **8.1 ワークアウト繰越の不具合修正**（cat2 8-A。唯一の「既存機能が壊れている」項目・最優先）
  - [x] リスケ時にプランが消える問題の設計整理（履歴保持 + 表示修正）✅ 完了（2026/07/10）
    - 根本原因は表示範囲の非対称（リスケ先は+30日先まで選べるが画面は期限切れ/今日/今週の3窓のみ描画）。Mobileワークアウト画面に「今後の予定」セクション（今日+1〜+30日のpending一覧、日付変更可）を追加し、リスケ時に status を pending へ復帰（auto-skip cronとのレース対策）、成功時スナックバー表示
    - original_date カラム追加・Web側修正は調査の結果不要と判断
  - [ ] （拡張）スキップ前警告通知（cat2 8-B、フェーズ7完了後）
- [x] **8.2 Storage private 化 + 署名URL**（cat7 2-A）✅ 実装完了・リモート適用済み（2026-08-30、PR: feature/storage-private-signed-urls。設計: `2026-08-29-storage-private-plan.md`）
  - [x] URL/パス両対応ヘルパー（Web: `storagePaths.ts`(純関数) + `signedStorageUrls.ts`('use client') / Mobile: `shared/storage/` + `StorageImage`）→ 新規はパス保存 → **4バケット全て private 化** → 既存データ正規化（migration `20260829000200`。リモートで http 残存 0 件・Google 外部URL 2 件保全を実測確認）
  - [x] message-photos の INSERT ポリシー修正（自フォルダ限定）+ client-notes の全ポリシー再編（authenticated 全員が全フォルダ読み書き削除できた重大不備を当事者限定に）+ profile-images の DELETE 新設（migration `20260829000000`）
    - 注: ポリシーのサブクエリ内 `name` は必ず `objects.name` と修飾（clients.name に誤解決する実バグを RLS テスト `storage_policies_rls_test.sql` が検出・修正済み。lessons.md 参照）
  - [x] 強制アップデート機構（`app_config` 単一行テーブル + `lib/features/app_update/` + `AppUpdateGate`。fail-open 3秒タイムアウト。設定画面にバージョン表示追加。package_info_plus 導入）
  - [x] AI 画像 orphan cleanup（8-B: AI推定フローのキャンセル/戻る/dispose で未送信画像を即時削除・送信済みガード付き / 8-A: `find_orphan_ai_images()` + Edge Function `cleanup-ai-images`(dry_run 対応) + pg_cron 日次ジョブを **inactive 登録**。リモート dry-run 相当の SQL 検証で orphan 24件中5件のみ検出=誤検知なし）
  - [x] `estimate-meal-nutrition` を URL/パス両対応 + service_role 署名URL(600s)で Anthropic へ渡す方式に改修（private 化で AI 推定が壊れる問題の対処）。両 Edge Function デプロイ済み
  - [ ] （残・オーナー作業）cleanup-ai-images cron の有効化判断（Vault 登録が前提: `2026-07-10-cron-vault-setup.md`）/ App Store 公開後に `app_config.ios_store_url` 設定
  - [ ] （残・QA）ログイン後の対話 QA（Web: メッセージ/食事/カルテ画像表示、Mobile: 同+AI推定フロー）は認証が必要なため未実施。ヘッドレス検証済み: 全テスト(Web 112/Mobile 111)・next build・db reset・RLS テスト4本・シミュレータ起動確認
- [ ] **8.3 Mobile セッション表示 + 前日リマインダー**（cat4 課題2・3。フェーズ7の最初の消費者）
  - [ ] ホームに次回セッションカード + セッション一覧画面
  - [ ] セッション前日リマインダー（pg_cron + ディスパッチャ、notification_logs で冪等化）

---

## フェーズ9: トレーナー介入機能

**目的**: 「データが見られる」から「見に行くきっかけがある」へ。トレーナー価値の核
**詳細設計**: カタログ cat1 1-A / 2-A / 規模: 合計 2〜3週
**前提**: フェーズ7（通知基盤）完了

### タスク

- [ ] **9.1 異常検知エンジン**（cat1 1-A: 日次バッチ + `alerts` テーブル）
  - [ ] 検知ルール: 体重急変・記録途絶・睡眠悪化・カロリー超過（閾値はトレーナー設定可能に）
  - [ ] HealthKit 同期ラグの誤検知対策: 途絶判定を「最終アプリ起動」と分離（横断レビュー1-7節）
  - [ ] トレーナーへの通知はディスパッチャ経由（実効経路が LINE/トレーナーモード導入前なら Web 内バッジ中心）
- [ ] **9.2 デイリートリアージ**（cat1 2-A: 優先度スコア付き「今日対応すべきクライアント」）
  - [ ] ダッシュボードに統合、alerts テーブルを消費
- [ ] **9.3 睡眠→指導動線**（cat1 6-A: 記録カード起点の「メッセージで指導」。S規模・先行実装可）

---

## フェーズ10: リテンション機能

**目的**: 顧客の記録習慣を作る（記録率はトレーナーの指導品質に直結）
**詳細設計**: カタログ cat2 1-A / 4-A / 2-A / 規模: 合計 2〜3週
**前提**: フェーズ7（通知基盤）完了

### タスク

- [ ] **10.1 ローカル記録リマインダー**（cat2 1-A: zonedSchedule。時間帯設定・記録済みならスキップ）
  - [ ] 汎用記録リマインダー（時刻・記録種類選択式。旧・夕食リマインダー〈2026-08-10 削除〉の再設計として実装）
- [ ] **10.2 記録タブからの直接記録（クイック記録）**（cat2 4-A）
  - [ ] ⚠️ 着手前に Outbox（cat7 7-A）との方式調停を確定させる（横断レビュー1-8節: 直接 INSERT を採るなら Outbox は messages と records の両対応が必要）
- [ ] **10.3 記録ストリーク表示**（cat2 2-A + マイルストーンバッジ 2-B）
- [ ] **10.4 Mobile オフライン Outbox**（cat7 7-A: 送信キュー + client_generated_id 重複防止。10.2 の決定に従い範囲確定）

---

## バックログ（フェーズ11以降の候補）

> 優先順位は横断レビュー4節の11位以下 + 各カテゴリの拡張案。詳細はすべてカタログ参照。

- **AI・Pro 価値**: AI返信候補（cat1 3-A、Pro の目玉としてフェーズ6直後への繰り上げ候補）/ AI相談（cat1 4-A）/ 週次自動サマリー（cat1 5-A）/ AIワークアウトプラン下書き（cat8 8-8-A）— いずれも着手前に `ai_usage_logs` 統一（統合判断6）と原価試算が必要
- **コミュニケーション**: LINE通知連携（cat6 1-A）/ トレーナーモード（cat6 1-C・中期本命）/ 一斉送信（cat6 2-A）/ テンプレート = `templates(kind)` 統一（cat6 3-A + cat1 3-B/7-A）/ 動画添付（cat6 4-A、egress コスト試算必須）/ 種目参考URL→種目ライブラリ（cat6 5-A→5-B、統合判断4）
- **記録・データ**: 活動量連携 + カロリー収支ダッシュボード（cat5 A-1/A-2）/ バーコード・食品DB（cat5 B-1/B-2）/ AI推定の修正差分ログ（cat5 C-1）/ 過去日付記録 + スクショ1日一括（cat5 D-1/D-2）/ 期間統計（cat5 E-1/E-2）/ 体組成・周囲径・水分（cat5 F-1〜F-3）/ 体重予測の Mobile 表示（cat2 7-A）
- **スケジュール**: 予約リクエスト承認制（cat4 課題1-A）/ オフ日・トレーナーステータス（cat4 課題4）/ カレンダーD&D・一括入力（cat4 課題5）/ ICSフィード→Google Calendar 連携（cat4 課題6）
- **収益・グロース**: Stripe Connect 決済代行（cat3 2-B）/ 紹介コード（cat3 5-A、統合判断5）/ 進捗写真（cat2 5-A、統合判断3）→ シェアカード（cat8 8-1-A）/ チャレンジ・リーダーボード（cat8 8-2-A、母数が立ってから）/ Android QA 基盤（cat8 8-6-A）
- **顧客体験**: 目標詳細画面・相談導線（cat2 6-A/6-B）/ 顧客向け週次サマリー配信（cat1 5-B）/ オンボーディング拡張（フェーズ3 + cat2 3-B）
- **横断基盤（未着手分）**: エラー監視（Sentry等）/ 監査ログ / バックアップ・PITR / プロダクト分析基盤（PostHog等）/ `messages.metadata` レジストリ文書 / トレーナー変更時のデータ引継ぎ方針 / 運営→ユーザーのお知らせチャネル
