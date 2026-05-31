# FIT-CONNECT - 新機能タスク一覧

**作成日**: 2026年3月29日
**バージョン**: 1.8
**進捗状況**: 全体 ~42%（フェーズ1 完了 / フェーズ2 2.1〜2.4(a) 完了。2.4 任意項目・2.5 スクショ未着手）
**最終更新**: 2026年5月31日 - タスク2.4(a) 明示「AI推定」ボタン化 完了（任意項目はバックログ）

> **2026-04-26 モノレポ化完了**: 旧 `fit-connect-mobile` リポジトリを `git subtree` で取り込み、単一 git リポジトリで Web/Mobile 両方を管理する構成に移行。詳細は `docs/tasks/2026-04-26-monorepo-migration.md`。

---

## 目次

1. [フェーズ1: ヘルスケア連携（Mobile）](#フェーズ1-ヘルスケア連携mobile)
2. [フェーズ2: LLM（Claude）カロリー計算（Mobile + Supabase）](#フェーズ2-llmclaudeカロリー計算mobile--supabase)
3. [フェーズ3: オンボーディングフロー（Mobile）](#フェーズ3-オンボーディングフローmobile)
4. [フェーズ4: ランディングページ（Web）](#フェーズ4-ランディングページweb)

---

## 実装状況サマリー

| フェーズ | 機能 | 対象 | 進捗 | 状態 |
|---------|------|------|------|------|
| 1 | ヘルスケア連携（体重・睡眠） | Mobile + Web | 100% | 🟢 体重・睡眠連携・バックグラウンド同期・トレーナー可視化 完了 |
| 2 | LLM カロリー計算 | Mobile + Supabase | 70% | 🟡 2.1〜2.4(a) 完了（明示AI推定ボタン化）/ 2.4任意項目・2.5 スクショ未着手 |
| 3 | オンボーディングフロー | Mobile | 0% | 🔴 未着手 |
| 4 | ランディングページ | Web | 0% | 🔴 未着手 |

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

- [ ] **2.5 食事アプリスクショ画像分析**
  - [ ] 対象アプリ調査（あすけん／カロミル／MyFitnessPal 等）と画面レイアウトのサンプル収集
  - [ ] スクショ判定・抽出用プロンプト設計（料理写真ルート 2.3 とは別系統。アプリ種別の自動判定 or ユーザー選択）
  - [ ] Edge Function 拡張（2.1 を再利用、image_type=`screenshot` 分岐）
  - [ ] 抽出フィールド: 日付・食事区分（朝/昼/夕/間食）・カロリー・PFC・食品名リスト（アプリ差異を吸収）
  - [ ] 抽出結果の確認・修正フロー（2.2/2.3 と UI を共通化）
  - [ ] meal_records への保存統合（`source = 'screenshot:<app_name>'` を記録）
  - [ ] 失敗時のフォールバック（読み取り不可・低信頼度時はテキスト入力へ誘導）
  - 補足: 他アプリユーザーの流入導線として位置付け（`docs/tasks/2026-04-29-feature-backlog.md` 1. AI機能より昇格）

---

## フェーズ3: オンボーディングフロー（Mobile）

**目的**: 新規ユーザーがアプリの使い方を理解し、初期設定をスムーズに完了できるフローを実装する

**概要**: 要件は実装着手時に詳細化する

### タスク

- [ ] **3.1 オンボーディング画面設計**
  - [ ] ページ構成・コンテンツ設計（アプリ紹介・主要機能説明）
  - [ ] PageView ベースのスワイプ式UI作成
  - [ ] インジケーター・スキップ・次へボタン

- [ ] **3.2 初期設定フロー**
  - [ ] プロフィール入力（名前・身長・目標体重など）
  - [ ] ヘルスケア連携の権限リクエスト（フェーズ1と連動）
  - [ ] プッシュ通知の権限リクエスト
  - [ ] トレーナー招待コード入力（既存QRコードフローとの統合）

- [ ] **3.3 オンボーディング状態管理**
  - [ ] 初回起動判定ロジック（SharedPreferences or DB）
  - [ ] オンボーディング完了フラグ管理
  - [ ] 認証フローとの統合（サインアップ後 → オンボーディング → ホーム）

- [ ] **3.4 チュートリアル・ヒント**
  - [ ] 主要画面での初回表示ツールチップ（任意）
  - [ ] 「使い方」画面（設定から再アクセス可能）

---

## フェーズ4: ランディングページ（Web）

**目的**: FIT-CONNECT のサービス紹介ランディングページを作成する（fit-connect リポジトリ）

**概要**: 要件は実装着手時に詳細化する

### タスク

- [ ] **4.1 ページ構成・デザイン**
  - [ ] ワイヤーフレーム・セクション構成の策定
  - [ ] デザイントークン適用（Noto Sans JP、border-radius: 6px）
  - [ ] レスポンシブデザイン（モバイル/タブレット/デスクトップ）

- [ ] **4.2 ヒーローセクション**
  - [ ] キャッチコピー・CTA ボタン
  - [ ] アプリスクリーンショット or モックアップ表示

- [ ] **4.3 機能紹介セクション**
  - [ ] 主要機能の紹介（メッセージ・記録・ワークアウト等）
  - [ ] アイコン・イラスト付き説明カード

- [ ] **4.4 料金・CTA セクション**
  - [ ] 料金プラン表示（あれば）
  - [ ] サインアップ/問い合わせ CTA
  - [ ] フッター（利用規約・プライバシーポリシーリンク）

- [ ] **4.5 SEO・パフォーマンス**
  - [ ] メタタグ・OGP 設定
  - [ ] Lighthouse スコア最適化
  - [ ] アナリティクス導入
