# FIT-CONNECT Web - 実装タスク一覧

**作成日**: 2026年2月1日
**バージョン**: 2.2
**進捗状況**: 全体 100% 完了
**最終更新**: 2026年2月23日 - プッシュ通知機能の実装（フェーズ7完了）

---

## 目次

1. [実装状況サマリー](#実装状況サマリー)
2. [最新の変更履歴](#最新の変更履歴)
3. [フェーズ別タスク一覧](#フェーズ別タスク一覧)
4. [メッセージ機能](#メッセージ機能)
5. [クライアント管理](#クライアント管理)
6. [スケジュール管理](#スケジュール管理)
7. [レポート・分析](#レポート分析)
8. [設定機能](#設定機能)
9. [インフラ・設定](#インフラ設定)
10. [今後のタスク](#今後のタスク)

---

## 実装状況サマリー

### 完了率

| カテゴリ | 進捗 | 状態 |
|---------|------|------|
| **認証（ログイン/サインアップ）** | 100% | 🟢 完了 |
| **ダッシュボード** | 100% | 🟢 完了 |
| **クライアント一覧・検索** | 100% | 🟢 完了 |
| **クライアント詳細表示** | 100% | 🟢 完了 |
| **メッセージ基本機能** | 100% | 🟢 完了 |
| **スケジュール管理** | 100% | 🟢 完了 |
| **レポート機能** | 100% | 🟢 完了 |
| **ワークアウトプラン** | 100% | 🟢 完了 |
| **設定画面** | 100% | 🟢 完了 |
| **クライアント招待（QR）** | 100% | 🟢 完了 |
| **チケット管理** | 100% | 🟢 完了 |

### 完了済み項目

- ✅ プロジェクト構造・アーキテクチャ設計
- ✅ Next.js 15 App Router セットアップ
- ✅ Supabase連携（Browser/Admin デュアルクライアント）
- ✅ Tailwind CSS + Radix UIコンポーネント
- ✅ Zustand状態管理（localStorage永続化）
- ✅ 認証フロー（ログイン/サインアップ）
- ✅ ダッシュボード（KPI、アラート、メッセージプレビュー、本日の予定）
- ✅ クライアント一覧・検索・フィルター
- ✅ クライアント詳細（基本情報、体重・食事・運動記録、チケット）
- ✅ メッセージ基本機能（送受信、リアルタイム更新）
- ✅ メッセージ画像添付・表示
- ✅ メッセージ編集（5分以内）
- ✅ メッセージ返信（リプライ）
- ✅ スケジュール管理（カレンダービュー、セッションCRUD）
- ✅ サイドバーレイアウト（ホバー展開）
- ✅ データベース操作関数（24ファイル）
- ✅ 体重グラフ表示（recharts折れ線グラフ）
- ✅ 顧客詳細タブUI（サマリー/食事/体重/運動/カルテ）
- ✅ カルテ（トレーナーノート）機能（CRUD、ファイルアップロード、共有管理）
- ✅ クライアント編集機能（基本情報・目標設定の編集モーダル）
- ✅ クライアントQRコード招待（QR表示、招待コードコピー、画像ダウンロード）
- ✅ チケット管理（テンプレート・発行・月契約、独立ページ `/tickets`、pg_cron自動発行）
- ✅ レポート・分析機能（統計グラフ、食事・運動統計、CSV/PDFエクスポート）
- ✅ 設定画面（プロフィール編集、パスワード変更、通知設定、ログアウト）
- ✅ トレーナー週間スケジュール設定（曜日別の対応可能時間帯管理）
- ✅ ワークアウトプラン管理（テンプレートCRUD、D&Dカレンダー、セッション実行記録、ステータスバッジ）

- ✅ プッシュ通知（Web Push VAPID方式、Service Worker、設定画面から許可/解除）

---

## 最新の変更履歴

### 2026年2月23日

- プッシュ通知機能を実装（フェーズ7完了）
  - **DBマイグレーション**: `push_subscriptions` テーブル新規作成（RLS、trainer_idインデックス）
  - **Service Worker**: `public/sw.js` 新規作成（push受信→通知表示、notificationclick→メッセージ画面遷移）
  - **Supabaseクエリ関数**: `savePushSubscription.ts`（upsert）、`deletePushSubscription.ts`（削除）
  - **API Routes**: `POST/DELETE /api/push-subscriptions`（購読登録・解除）、`POST /api/push-notify`（web-pushライブラリで通知送信）
  - **NotificationSection全面書き換え**: ブラウザ対応確認、通知許可フロー（requestPermission→SW登録→pushManager.subscribe→API保存）、解除フロー、denied時のガイダンス表示
  - **設定ページ更新**: `settings/page.tsx` から `trainerId` propを渡すよう変更
  - **Edge Function拡張**: `parse-message-tags/index.ts` に `sendWebPushToTrainer()` 関数追加。INSERT時にトレーナー受信者へWeb Push送信（`/api/push-notify` API Route経由）
  - **パッケージ追加**: `web-push`, `@types/web-push`
  - **必要な環境変数**: `NEXT_PUBLIC_VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`（Next.js）、`APP_URL`, `PUSH_API_KEY`（Edge Function Secrets）

### 2026年2月22日

- ワークアウト機能強化を実装（フェーズ5.6完了）
  - **チケット連携**: セッション種別ワークアウトをカレンダーにD&Dした際、チケット選択モーダル（`TicketSelectModal.tsx`）を表示。チケット消費 + セッション自動作成 + スケジュール画面に反映
  - **DBマイグレーション**: `workout_assignments` テーブルに `session_id` カラム追加（`sessions` テーブルへの外部キー）
  - **API Route拡張**: `POST /api/workout-assignments` に `ticketId`, `sessionTime`, `createSession` パラメータ追加。セッション作成 + チケット消費をアトミックに処理
  - **TicketSelectModal新規作成**: Radix UI Dialog、有効チケット一覧表示、時刻指定入力、「チケットを使用しない」オプション
  - **workoutplan/page.tsx拡張**: `pendingDrop` ステート追加、session/self_guided の分岐処理
- バグ修正
  - **チケット期限表示修正**: `SummaryTab.tsx` で `isAfter`/`isBefore` のタイムゾーン問題を文字列比較に修正（UTC midnight → JST 9AM の誤判定防止）
  - **Edge Function `parse-message-tags` バグ修正**: `notes.includes('ラン')` が `ワークアウトプラン` にマッチする問題を正規表現（否定先読み/後読み）に修正。`#運動:完了` タグ時のデフォルトを `strength_training` に変更
  - **exercise_records データ修正**: 誤って `running` になっていた4件を `strength_training` に更新
- 運動タブ強化
  - **ExerciseTab拡張**: `workoutAssignments` プロパティ追加。`workout_assignments` の種目・セット詳細（重量×回数×完了チェック）を表示
  - **統合一覧化**: ワークアウト実績とその他の運動を日付ごとの統合一覧に変更（`MergedExerciseItem` ユニオン型で統一的に処理）
  - **page.tsx拡張**: `getClientAssignments` を追加取得し、ExerciseTab に渡すよう変更
- セッションタブ整理
  - **SessionTab**: `plan_type === 'session'` のみ表示するようフィルタ追加（宿題は運動タブで確認）
- 設計書作成
  - **`docs/DESIGN_EXERCISE_TAB_ENHANCEMENT.md`**: Web側 運動タブ強化 + Edge Functionバグ修正 + モバイル改善案の設計書
  - **モバイル側設計書**: `DESIGN_WORKOUT_COMPLETION_FIX.md`（完了メッセージのタグ除去 + client_feedback フィードバック機能）

### 2026年2月21日

- セッション機能強化を実装（フェーズ5.5完了）
  - **DBマイグレーション**: `workout_assignments` テーブルに `trainer_note`, `client_feedback`, `started_at`, `finished_at` カラム追加
  - **型定義拡張**: `WorkoutAssignment` に4フィールド追加、`UpdateAssignmentParams` にオプショナルフィールド追加
  - **GET APIバグ修正**: `workout_assignments` GET に `exercises:workout_assignment_exercises(*)` JOIN追加（種目が表示されないバグ修正）
  - **GET API拡張**: `includeHistory=true` パラメータで過去30日分のデータ取得に対応（前回データ参照用）
  - **PATCH API拡張**: `trainerNote`, `clientFeedback`, `startedAt`, `finishedAt` の更新に対応
  - **SessionTimerBar新規作成**: セッション開始/経過時間カウンター/終了の3状態表示、リロード後も `started_at` から復元
  - **SessionSummaryModal新規作成**: Radix UI Dialog、種目実績一覧、所要時間、トレーナーノート/クライアントフィードバック入力
  - **SessionTab全機能統合**:
    - SessionTimerBar / SessionSummaryModal を組み込み
    - 前回データ取得ロジック（同 `plan_id` の直前 `completed` アサインメントから `actual_sets` を参照）
    - `SetInputRow` に `previousSet` を接続（「前回: Xkg × Y」表示）
    - 種目ごとのメモ入力欄（textarea、onBlurで自動保存）
    - タイマー開始/終了ハンドラ（PATCH APIで `started_at`/`finished_at` を保存）
    - セッション終了時にサマリーモーダル自動表示

- ワークアウトプラン管理機能を実装（フェーズ5完了）
  - **DBマイグレーション**: `workout_assignments`, `workout_assignment_exercises` テーブル新規作成、`client_workout_plans` テーブル削除、`workout_plans` に `estimated_minutes` カラム追加、RLS設定
  - **型定義**: `src/types/workout.ts` 新規作成（WorkoutPlan, WorkoutExercise, WorkoutAssignment, WorkoutAssignmentExercise, ActualSet 等）
  - **Supabase クエリ関数**: `getWorkoutPlans.ts`, `getWorkoutExercises.ts`, `getWeeklyAssignments.ts`, `getClientAssignments.ts`, `getUndonePlanCount.ts`, `getClientWorkoutStatuses.ts`
  - **API Routes**: `workout-plans/route.ts` (GET/POST), `workout-plans/[id]/route.ts` (PUT/DELETE), `workout-assignments/route.ts` (GET/POST), `workout-assignments/[id]/route.ts` (PATCH/DELETE), `workout-assignment-exercises/[id]/route.ts` (PATCH)
  - **ワークアウトプランページ**: `/workoutplan` プレースホルダーを全面書き換え
    - @dnd-kit によるドラッグ＆ドロップ対応2ペインレイアウト
    - 左ペイン: テンプレート一覧（作成/編集/削除/検索/種目プレビュー）
    - 右ペイン: 週間カレンダー（週ナビゲーション、ステータスバッジ）
    - テンプレート→日付にD&Dでアサイン、日付間移動対応
    - クライアント選択（Radix UI Select）
  - **コンポーネント**: `ClientSelector.tsx`, `PlanFormModal.tsx`, `ExerciseListModal.tsx`, `TemplatePanel.tsx`, `WeeklyCalendar.tsx`, `CalendarDayCell.tsx`
  - **セッション実行タブ**: 顧客詳細に「セッション」タブ追加（7タブ構成）
    - `SessionTab.tsx` - 日付選択、種目一覧、セット入力
    - `SetInputRow.tsx` - タップ領域広い +/- ボタンで重量・回数入力、前回データ表示
    - `SupersetBadge.tsx` - スーパーセット連結表示
  - **ステータスバッジ**: ダッシュボードに今週未実施プランアラート追加、顧客一覧にワークアウトステータスバッジ追加
  - **サイドバー**: ワークアウトプランメニュー追加（クリップボード+ダンベルアイコン）
  - **パッケージ追加**: `@dnd-kit/core`, `@dnd-kit/sortable`, `@dnd-kit/utilities`

### 2026年2月19日

- トレーナー週間スケジュール設定機能を実装
  - **配置場所**: `/settings` ページ内の「対応スケジュール」セクション
  - **機能**: 曜日別（月〜日）の対応可能/休みトグル、開始・終了時刻設定（1時間刻み、24時間対応）
  - **保存方式**: 7曜日分を一括UPSERT（`trainer_schedules` テーブル、既存）
  - **バリデーション**: 開始時刻 < 終了時刻チェック
  - **新規ファイル**: `types/schedule.ts`, `getTrainerSchedules.ts`, `upsertTrainerSchedules.ts`, `api/trainer-schedules/route.ts`, `ScheduleSection.tsx`
  - **変更ファイル**: `settings/page.tsx`（ScheduleSection組み込み）

### 2026年2月16日

- 設定画面を実装（フェーズ6完了）
  - **設定ページ**: `/settings` プレースホルダーを全面書き換え
  - **プロフィール編集**: 名前、メールアドレス、プロフィール画像の変更（React Hook Form + Zod）
  - **パスワード変更**: Supabase Auth連携、確認入力バリデーション
  - **通知設定**: メール通知トグル（開発中プレースホルダー）
  - **ログアウト**: AlertDialog確認ダイアログ付き、Zustand Store クリア
  - **新規ファイル**: `types/trainer.ts`, `getTrainerDetail.ts`, `updateTrainer.ts`, `uploadProfileImage.ts`, `api/trainers/[id]/route.ts`, `ProfileSection.tsx`, `PasswordSection.tsx`, `NotificationSection.tsx`, `AccountSection.tsx`
  - **変更ファイル**: `userStore.ts`（clearUserアクション追加）
- レポート・分析機能を実装（フェーズ4完了）
  - **レポートページ**: `/report` プレースホルダーを全面書き換え
  - **クライアント選択**: Radix UI Selectでクライアント一覧から選択
  - **期間選択**: 開始日・終了日のdate入力（デフォルト: 過去3ヶ月）
  - **統計カード**: 体重変動、食事記録回数、運動記録回数の3カード表示
  - **体重推移グラフ**: 既存WeightChartコンポーネント流用
  - **食事統計**: 記録頻度、食事区分別カウント、平均カロリー
  - **運動統計**: 記録頻度、種目別カウント（上位5件）、合計時間、平均カロリー消費
  - **CSVエクスポート**: 日別集計データをUTF-8 BOM付きCSVでダウンロード
  - **PDFエクスポート**: html2canvas + jsPDFでレポート画面をキャプチャしてPDF化
  - **新規ファイル**: `StatCards.tsx`, `MealStatistics.tsx`, `ExerciseStatistics.tsx`, `exportCSV.ts`, `exportPDF.ts`

### 2026年2月15日

- チケット管理機能を大幅リニューアル（フェーズ3.4完了）
  - **アーキテクチャ変更**: 顧客詳細内タブ → サイドバー独立ページ `/tickets` に移動
  - **テンプレート機能**: テンプレート作成・編集・削除（`ticket_templates`テーブル）
  - **チケット発行**: テンプレートから顧客を選んで発行、全顧客チケット一覧
  - **月契約**: 月契約作成・ステータス管理（active/paused/cancelled）
  - **自動発行**: pg_cron で毎日00:00 UTC に `issue_recurring_tickets()` 実行
  - **DB**: `ticket_templates`, `ticket_subscriptions` テーブル + RLS + indexes
  - **API Routes**: 6新規（templates CRUD, issue, all, subscriptions CRUD）
  - **UI**: 10コンポーネント（3タブ構成: テンプレート/チケット発行/月契約）
  - **顧客詳細**: TicketsTab は読み取り専用に変更（`/tickets`へのリンク付き）
  - `CreateTicketParams`, `UpdateTicketParams` 型、`TICKET_TYPE_OPTIONS` 定数追加
- クライアント編集機能を実装（フェーズ3.2完了）
  - `Client`型に`goal_deadline`フィールド追加
  - `updateClient.ts` - クライアント更新関数
  - `PUT /api/clients/[client_id]` - クライアント更新API
  - `EditClientModal.tsx` - 編集モーダル（React Hook Form + Zod）
  - `ClientHeader.tsx`に編集ボタン追加
  - 編集可能項目: 年齢、性別、職業、身長、目標体重、目的、目標説明、目標期日
- クライアントQRコード招待機能を実装（フェーズ3.3完了）
  - `qrcode.react` ライブラリ導入
  - `ClientInviteModal.tsx` - 招待モーダル（QRコード表示、招待コードコピー、画像ダウンロード）
  - `clients/page.tsx` にヘッダー招待ボタン追加
  - QRコード値: trainer_id（UUID生データ）

### 2026年2月14日

- カルテ（トレーナーノート）機能を実装（フェーズ3.5完了）
  - `client_notes` テーブル作成（RLS付き）
  - `client-notes` Storageバケット作成（PDF/画像対応、最大10MB）
  - `ClientNote`, `CreateClientNoteParams`, `UpdateClientNoteParams` 型定義追加
  - `getClientNotes.ts` - カルテ一覧取得関数
  - `uploadNoteFile.ts` - ファイルアップロード関数（JPEG, PNG, WebP, PDF対応）
  - `deleteNoteFile.ts` - ファイル削除関数
  - `POST /api/client-notes` - カルテ作成API
  - `PUT /api/client-notes/[id]` - カルテ更新API
  - `DELETE /api/client-notes/[id]` - カルテ削除API（Storage連携削除）
  - `NotesTab.tsx` - カルテ一覧タブ（カード形式表示）
  - `CreateNoteModal.tsx` - カルテ作成モーダル（タイトル、セッション番号、内容、ファイル添付、共有チェック）
  - `EditNoteModal.tsx` - カルテ編集モーダル（既存ファイル管理、新規ファイル追加）
  - `DeleteNoteDialog.tsx` - 削除確認ダイアログ
  - 顧客詳細ページに「カルテ」タブ追加（5タブ構成）

### 2026年2月13日

- 顧客詳細画面の大幅UI改修（タブベースレイアウト化）
  - Radix UI Tabs導入（サマリー/食事/体重/運動の4タブ）
  - page.tsx を741行→113行にリファクタリング
  - `_components/ClientHeader.tsx` - プロフィール情報ヘッダー
  - `_components/SummaryTab.tsx` - 統計サマリー、体重グラフ、最近の食事、チケット
  - `_components/MealTab.tsx` - 食事記録（期間フィルター、週/月カレンダー、日付グループ一覧）
  - `_components/WeightTab.tsx` - 体重推移グラフ＋記録一覧
  - `_components/ExerciseTab.tsx` - 運動記録（月カレンダー＋選択日詳細）
  - データ取得数を10→100に拡大

### 2026年2月11日

- 体重グラフ表示機能を実装（フェーズ3.1完了）
  - `WeightChart.tsx` - recharts折れ線グラフコンポーネント
  - 期間フィルター（今週/今月/3ヶ月/全期間）
  - 目標体重の水平点線表示
  - データポイントホバーでツールチップ（日付・体重）
  - クライアント詳細ページに統合
- メッセージ返信（リプライ）機能を実装（フェーズ2.3完了）
  - メッセージホバー時に返信ボタン表示（全メッセージ対象）
  - `ReplyPreview.tsx` - 入力欄上部の返信プレビュー表示
  - `ReplyQuote.tsx` - メッセージバブル内の引用表示
  - `getMessageById.ts` - 返信先メッセージ取得関数
  - `POST /api/messages/send` にreply_to_message_id対応追加
  - Realtime INSERT購読で返信情報取得対応
  - `Message`型に`reply_to_message_id`, `reply_to_message`を追加
- メッセージ編集機能を実装（フェーズ2.2完了）
  - ホバー時にペンアイコン表示（トレーナーの自分のメッセージのみ）
  - `canEditMessage()` - 送信後5分以内のみ編集可能
  - インライン編集UI（Enter保存 / Escキャンセル）
  - `PUT /api/messages/edit` API Route作成（サーバー側5分チェック付き）
  - 「編集済み」バッジ表示（ホバーで編集日時ツールチップ）
  - Realtime UPDATE購読で編集がリアルタイム反映
  - `Message`型に`id`, `created_at`, `is_edited`, `edited_at`を追加
  - send APIがメッセージIDを返すよう改善
- メッセージ画像添付・表示機能を実装（フェーズ2.1完了）
  - `ImageUploader.tsx` - ドラッグ&ドロップ対応の画像添付コンポーネント
  - `ImageModal.tsx` - 画像拡大表示モーダル
  - `uploadMessageImage.ts` - Supabase Storageアップロード関数
  - API Route更新（`image_urls`対応）
  - メッセージページUI更新（添付・表示・Realtime対応）
  - `Message`型を`src/types/client.ts`に追加
- メッセージ入力UX改善
  - IME変換中のEnter送信防止（`isComposing`チェック）
  - Shift+Enterで改行対応（`input`→`textarea`化、自動高さ調整）
  - 送信後のメッセージに改行を維持（`whitespace-pre-wrap`）
  - 送信後のテキストエリア高さリセット
- メッセージ表示をスタック形式に変更（`flex-col-reverse`）
  - 画面を開いた時に最新メッセージが下部に表示
  - 上にスクロールで過去メッセージを閲覧

### 2026年2月1日

- 初版作成
- 要件定義書（REQUIREMENTS.md）作成
- 実装タスク一覧（本ファイル）作成

---

## フェーズ別タスク一覧

### 📌 フェーズ1: 基盤構築 ✅ 完了

**目的**: プロジェクトの基盤を整備

| タスク | 状態 | 詳細 |
|--------|------|------|
| Next.js 15セットアップ | ✅ | App Router、TypeScript |
| Supabase連携 | ✅ | Browser/Adminクライアント |
| 認証フロー | ✅ | ログイン/サインアップ |
| レイアウト構築 | ✅ | サイドバー、ルートグループ |
| UIコンポーネント | ✅ | Radix UI、Tailwind CSS |

---

### 📌 フェーズ2: メッセージ機能強化 ✅ 完了

**目的**: クライアントアプリと同等のメッセージ機能を実現

#### 2.1 画像添付・表示機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 2.1.1 | 画像アップロードコンポーネント作成 | ✅ | `ImageUploader.tsx` - ドラッグ&ドロップ対応 |
| 2.1.2 | Supabase Storageバケット確認 | ✅ | `message-photos`バケット、RLSポリシー |
| 2.1.3 | 画像アップロード関数作成 | ✅ | `src/lib/supabase/uploadMessageImage.ts` |
| 2.1.4 | メッセージ入力欄に添付ボタン追加 | ✅ | 最大3枚まで、プレビュー表示 |
| 2.1.5 | メッセージバブルに画像表示 | ✅ | サムネイル、クリックで拡大モーダル |
| 2.1.6 | API Route更新 | ✅ | `/api/messages/send` - `image_urls`対応 |

**実装詳細**:

```typescript
// src/lib/supabase/uploadMessageImage.ts
export async function uploadMessageImage(
  file: File,
  trainerId: string,
  messageId: string
): Promise<string> {
  const path = `${trainerId}/${messageId}/${file.name}`;
  const { data, error } = await supabaseAdmin.storage
    .from('message-photos')
    .upload(path, file);

  if (error) throw error;

  const { data: { publicUrl } } = supabaseAdmin.storage
    .from('message-photos')
    .getPublicUrl(path);

  return publicUrl;
}
```

```typescript
// ImageUploader.tsx の仕様
interface ImageUploaderProps {
  images: File[];
  onImagesChange: (images: File[]) => void;
  maxImages?: number; // デフォルト: 3
  disabled?: boolean;
}
```

#### 2.2 メッセージ編集機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 2.2.1 | 編集ボタンUI追加 | ✅ | メッセージホバー時にペンアイコン表示（自分のメッセージのみ） |
| 2.2.2 | 編集可能判定関数作成 | ✅ | `canEditMessage()` - 5分以内チェック |
| 2.2.3 | インライン編集UI | ✅ | テキストエリア、キャンセル/保存ボタン、Enter/Escキー対応 |
| 2.2.4 | 編集API作成 | ✅ | `PUT /api/messages/edit` - サーバー側5分チェック付き |
| 2.2.5 | 編集済みバッジ表示 | ✅ | 「編集済み」ラベル、編集日時ツールチップ |
| 2.2.6 | Realtime対応 | ✅ | UPDATE イベント購読 |

**実装詳細**:

```typescript
// src/lib/supabase/editMessage.ts
export async function editMessage(
  messageId: string,
  newContent: string
): Promise<void> {
  const now = new Date();

  // 5分以内チェック
  const { data: message } = await supabase
    .from('messages')
    .select('created_at')
    .eq('id', messageId)
    .single();

  const createdAt = new Date(message.created_at);
  const diffMinutes = (now.getTime() - createdAt.getTime()) / 1000 / 60;

  if (diffMinutes > 5) {
    throw new Error('編集可能な時間（5分）を過ぎました');
  }

  await supabase
    .from('messages')
    .update({
      content: newContent,
      edited_at: now.toISOString(),
      is_edited: true,
      updated_at: now.toISOString(),
    })
    .eq('id', messageId);
}
```

#### 2.3 メッセージ返信（リプライ）機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 2.3.1 | 返信ボタンUI追加 | ✅ | メッセージホバー時に表示 |
| 2.3.2 | 返信プレビューコンポーネント | ✅ | `ReplyPreview.tsx` - 入力欄上部に表示 |
| 2.3.3 | 返信引用コンポーネント | ✅ | `ReplyQuote.tsx` - バブル内に表示 |
| 2.3.4 | 返信先メッセージ取得 | ✅ | `getMessageById()` 関数 |
| 2.3.5 | 送信時にreply_to_message_id保存 | ✅ | API Route更新 |
| 2.3.6 | メッセージ一覧で返信情報表示 | ✅ | `reply_to_message_id`がある場合に引用表示 |

**実装詳細**:

```typescript
// ReplyPreview.tsx
interface ReplyPreviewProps {
  replyToContent: string;
  replyToSenderName: string;
  onCancel: () => void;
}

// ReplyQuote.tsx
interface ReplyQuoteProps {
  senderName: string;
  content: string;
  isTrainerMessage: boolean;
}
```

```
表示イメージ:
┌─────────────────────────────────────┐
│ [クライアントメッセージ]             │
│ #食事:昼食 サラダチキン食べました     │
│ 12:30                               │
│                                     │
│ ┌─────────────────────────────────┐ │ ← リプライ
│ │ トレーナー                       │ │
│ │ ┌─ 返信元 ─────────────────────┐│ │
│ │ │ サラダチキン食べました         ││ │
│ │ └───────────────────────────────┘│ │
│ │ タンパク質しっかり取れてますね！ │ │
│ │ 13:15                           │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

---

### 📌 フェーズ3: クライアント管理強化 ✅ 完了

**目的**: クライアント情報の編集・可視化機能を追加

#### 3.1 体重グラフ表示 ✅ 完了

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.1.1 | グラフライブラリ選定・導入 | ✅ | recharts導入 |
| 3.1.2 | WeightChart コンポーネント作成 | ✅ | 折れ線グラフ、目標体重点線 |
| 3.1.3 | 期間フィルター追加 | ✅ | 今週/今月/3ヶ月/全期間 |
| 3.1.4 | データポイントホバー詳細 | ✅ | ツールチップで日付・体重表示 |
| 3.1.5 | クライアント詳細ページに統合 | ✅ | `/clients/[client_id]` |

**実装詳細**:

```typescript
// src/components/clients/WeightChart.tsx
interface WeightChartProps {
  weightRecords: WeightRecord[];
  targetWeight: number;
  initialWeight?: number;
  period: 'week' | 'month' | '3months' | 'all';
}
```

#### 3.1.5 顧客詳細タブUI ✅ 完了

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.1.5.1 | Radix UI Tabs導入 | ✅ | shadcn tabs コンポーネント |
| 3.1.5.2 | ClientHeader 抽出 | ✅ | プロフィール＋ナビ |
| 3.1.5.3 | SummaryTab 作成 | ✅ | 統計カード、グラフ、最近の食事、チケット |
| 3.1.5.4 | MealTab 抽出 | ✅ | 期間フィルター、カレンダー、日付グループ |
| 3.1.5.5 | WeightTab 抽出 | ✅ | グラフ+記録一覧 |
| 3.1.5.6 | ExerciseTab 新規作成 | ✅ | 月カレンダー+選択日運動記録 |
| 3.1.5.7 | page.tsx 統合 | ✅ | 741行→113行にリファクタリング |

#### 3.5 カルテ（トレーナーノート）機能 ✅ 完了

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.5.1 | DBテーブル・Storage基盤 | ✅ | `client_notes`テーブル、RLS、`client-notes`バケット |
| 3.5.2 | 型定義追加 | ✅ | `ClientNote`, `CreateClientNoteParams`, `UpdateClientNoteParams` |
| 3.5.3 | Query関数作成 | ✅ | `getClientNotes.ts`, `uploadNoteFile.ts`, `deleteNoteFile.ts` |
| 3.5.4 | API Route作成 | ✅ | `POST /api/client-notes`, `PUT/DELETE /api/client-notes/[id]` |
| 3.5.5 | NotesTab コンポーネント | ✅ | カルテ一覧（カード形式）、追加/編集/削除ボタン |
| 3.5.6 | CreateNoteModal コンポーネント | ✅ | 作成モーダル（タイトル、セッション番号、内容、ファイル、共有） |
| 3.5.7 | EditNoteModal コンポーネント | ✅ | 編集モーダル（既存ファイル管理、新規ファイル追加） |
| 3.5.8 | DeleteNoteDialog コンポーネント | ✅ | 削除確認ダイアログ（Storage連携削除） |
| 3.5.9 | 顧客詳細ページ統合 | ✅ | 5タブ構成（サマリー/食事/体重/運動/カルテ） |

#### 3.2 クライアント編集機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.2.1 | 編集モーダルコンポーネント作成 | ✅ | `EditClientModal.tsx` |
| 3.2.2 | フォームバリデーション | ✅ | React Hook Form + Zod |
| 3.2.3 | 更新API作成 | ✅ | `src/lib/supabase/updateClient.ts` + `PUT /api/clients/[client_id]` |
| 3.2.4 | 目標設定フォーム | ✅ | 目標体重、期日、説明 |
| 3.2.5 | プロフィール画像アップロード | ⏭️ | モバイルアプリ側で対応 |

**編集可能項目**:
- 名前
- 年齢
- 性別
- 身長
- 目標体重
- 開始時体重
- 目的
- 目標説明
- 目標期日
- プロフィール画像

#### 3.3 クライアントQRコード招待 ✅ 完了

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.3.1 | QRコード生成ライブラリ導入 | ✅ | qrcode.react |
| 3.3.2 | 招待モーダル作成 | ✅ | `ClientInviteModal.tsx` |
| 3.3.3 | 招待URL生成ロジック | ⏭️ | trainer_id生データ方式に変更（URLスキームはFlutter側で対応） |
| 3.3.4 | QRコード表示コンポーネント | ✅ | ダウンロード機能付き |
| 3.3.5 | 招待リンクコピー機能 | ✅ | クリップボードにコピー |

**実装詳細**:

```typescript
// 招待URLフォーマット
const inviteUrl = `fitconnect://invite?trainer_id=${trainerId}`;

// QRコード生成
import QRCode from 'qrcode.react';

<QRCode
  value={inviteUrl}
  size={256}
  level="H"
/>
```

#### 3.4 チケット管理画面 ✅ 完了

**設計方針**: サイドバー独立ページ `/tickets` に移動。テンプレートから発行する運用フロー。月契約は pg_cron で自動発行。

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.4.1 | DBマイグレーション | ✅ | `ticket_templates`, `ticket_subscriptions` テーブル + RLS + indexes + pg_cron |
| 3.4.2 | テンプレートCRUD | ✅ | `GET/POST /api/ticket-templates`, `PUT/DELETE /api/ticket-templates/[id]` |
| 3.4.3 | チケット発行API | ✅ | `POST /api/tickets/issue`（テンプレートから発行）, `GET /api/tickets/all`（全顧客チケット） |
| 3.4.4 | 月契約API | ✅ | `GET/POST /api/ticket-subscriptions`, `PUT/DELETE /api/ticket-subscriptions/[id]` |
| 3.4.5 | テンプレートタブUI | ✅ | `TemplateList`, `TemplateFormModal`, `DeleteTemplateDialog` |
| 3.4.6 | チケット発行タブUI | ✅ | `IssueTicketSection`, `IssuedTicketList`, `EditIssuedTicketModal`, `DeleteIssuedTicketDialog` |
| 3.4.7 | 月契約タブUI | ✅ | `SubscriptionList`, `CreateSubscriptionModal`, `SubscriptionStatusDialog` |
| 3.4.8 | メインページ統合 | ✅ | `/tickets/page.tsx` - 3タブ構成（テンプレート/チケット発行/月契約） |
| 3.4.9 | 顧客詳細リファクタリング | ✅ | `TicketsTab` 読み取り専用化、旧モーダル3ファイル削除 |
| 3.4.10 | セッション紐付けUI | ✅ | SessionModal.tsxで実装済み（チケット選択・消化ロジック） |
| 3.4.11 | 自動発行（pg_cron） | ✅ | `issue_recurring_tickets()` - 毎日00:00 UTC、active月契約のチケットを自動発行 |

---

### 📌 フェーズ4: レポート・分析機能 ✅ 完了

**目的**: クライアントの進捗を可視化・レポート化

#### 4.1 レポート画面基盤

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 4.1.1 | レポート画面レイアウト作成 | ✅ | `/report` プレースホルダー置き換え |
| 4.1.2 | クライアント選択UI | ✅ | ドロップダウンまたはサイドバー |
| 4.1.3 | 期間選択UI | ✅ | 日付範囲ピッカー |

#### 4.2 統計・グラフ

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 4.2.1 | 体重推移グラフ（再利用） | ✅ | WeightChartコンポーネント流用 |
| 4.2.2 | 食事記録統計 | ✅ | 記録頻度、食事区分別カウント |
| 4.2.3 | 運動記録統計 | ✅ | 種目別カウント、総時間 |
| 4.2.4 | 目標達成率推移 | ✅ | 週次/月次の達成率グラフ（GoalAchievementChart） |

#### 4.3 エクスポート機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 4.3.1 | CSVエクスポート | ✅ | 体重/食事/運動記録 |
| 4.3.2 | PDFレポート生成 | ✅ | サマリーレポート |

---

### 📌 フェーズ5: ワークアウトプラン ✅ 完了

**目的**: トレーニングメニューの作成・管理・セッション記録

#### 5.1 DB基盤・バックエンド

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 5.1.1 | DBマイグレーション | ✅ | `workout_assignments`, `workout_assignment_exercises` テーブル作成、RLS設定 |
| 5.1.2 | 型定義 | ✅ | `src/types/workout.ts` 新規作成 |
| 5.1.3 | Supabaseクエリ関数 | ✅ | 6ファイル（テンプレート、アサインメント、ステータス取得） |
| 5.1.4 | API Routes | ✅ | 5ルート（プランCRUD、アサインメントCRUD、種目更新） |

#### 5.2 D&Dカレンダーページ

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 5.2.1 | テンプレートCRUDモーダル | ✅ | `PlanFormModal.tsx` - React Hook Form + Zod |
| 5.2.2 | テンプレート一覧パネル | ✅ | `TemplatePanel.tsx` - D&D対応カード |
| 5.2.3 | 週間カレンダー | ✅ | `WeeklyCalendar.tsx` - 週ナビゲーション |
| 5.2.4 | 日付セル（ドロップゾーン） | ✅ | `CalendarDayCell.tsx` - @dnd-kit/core |
| 5.2.5 | ワークアウトプランページ | ✅ | `/workoutplan` - DndContext統合 |
| 5.2.6 | サイドバーメニュー追加 | ✅ | `layout.tsx` にアイコン付きメニュー追加 |

#### 5.3 セッション実行タブ

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 5.3.1 | セット入力コンポーネント | ✅ | `SetInputRow.tsx` - +/- ボタン、前回データ表示 |
| 5.3.2 | スーパーセット連結UI | ✅ | `SupersetBadge.tsx` |
| 5.3.3 | セッション実行タブ | ✅ | `SessionTab.tsx` - 日付選択、種目入力 |
| 5.3.4 | 顧客詳細タブ追加 | ✅ | 7タブ構成（+セッション） |

#### 5.4 ステータスバッジ

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 5.4.1 | ダッシュボードアラート | ✅ | 今週未実施プランアラート |
| 5.4.2 | 顧客一覧バッジ | ✅ | 完了/一部完了/未実施 |

#### 5.5 セッション機能強化 ✅ 完了

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 5.5.1 | SessionTimerBar | ✅ | セッション開始/経過カウンター/終了の3状態表示 |
| 5.5.2 | SessionSummaryModal | ✅ | 種目実績一覧、所要時間、トレーナーノート/フィードバック |
| 5.5.3 | 前回データ参照 | ✅ | 同plan_idの直前completedアサインメントからactual_sets参照 |
| 5.5.4 | 種目メモ入力 | ✅ | textarea、onBlurで自動保存 |

#### 5.6 チケット連携・運動タブ統合 ✅ 完了

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 5.6.1 | TicketSelectModal新規作成 | ✅ | セッション種別D&D時のチケット選択・時刻指定モーダル |
| 5.6.2 | API Route拡張（セッション＋チケット消費） | ✅ | `POST /api/workout-assignments` でアトミック処理 |
| 5.6.3 | session_id DBマイグレーション | ✅ | `workout_assignments` に `session_id` カラム追加 |
| 5.6.4 | Edge Function バグ修正 | ✅ | `parse-message-tags` の `ラン` 部分一致修正（正規表現化） |
| 5.6.5 | 運動タブ統合表示 | ✅ | `workout_assignments` + `exercise_records` の日付統合一覧 |
| 5.6.6 | セッションタブ plan_type フィルタ | ✅ | `session` タイプのみ表示 |
| 5.6.7 | チケット期限表示バグ修正 | ✅ | SummaryTab のタイムゾーン問題修正 |

---

### 📌 フェーズ6: 設定機能 ✅ 完了

**目的**: トレーナーのプロフィール・アプリ設定

#### 6.1 設定画面

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 6.1.1 | 設定画面レイアウト作成 | ✅ | `/settings` プレースホルダー置き換え |
| 6.1.2 | プロフィール編集 | ✅ | 名前、メール、プロフィール画像（`ProfileSection.tsx`） |
| 6.1.3 | パスワード変更 | ✅ | Supabase Auth連携（`PasswordSection.tsx`） |
| 6.1.4 | 通知設定 | ✅ | メール通知トグル（開発中表示、`NotificationSection.tsx`） |
| 6.1.5 | ログアウト機能 | ✅ | AlertDialog確認ダイアログ付き（`AccountSection.tsx`） |

---

### 📌 フェーズ7: プッシュ通知 ✅ 完了

**目的**: クライアントからのメッセージ通知

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 7.1.1 | push_subscriptions DBテーブル作成 | ✅ | RLS + trainer_idインデックス |
| 7.1.2 | Service Worker作成 | ✅ | `public/sw.js` - push受信・通知表示 |
| 7.1.3 | Push Subscription保存関数 | ✅ | `savePushSubscription.ts` - upsert on conflict endpoint |
| 7.1.4 | Push Subscription削除関数 | ✅ | `deletePushSubscription.ts` |
| 7.1.5 | Push Subscription API Route | ✅ | `POST/DELETE /api/push-subscriptions` |
| 7.1.6 | Push通知送信API Route | ✅ | `POST /api/push-notify` - web-pushライブラリ使用 |
| 7.2.1 | 通知許可UI（NotificationSection） | ✅ | 許可/解除/denied状態の3パターン分岐 |
| 7.3.1 | Edge Function Web Push連携 | ✅ | `sendWebPushToTrainer()` - API Route経由で通知送信 |
| 7.4.1 | 通知クリック時のナビゲーション | ✅ | `/message?clientId=XXX` に遷移 |

---

## 優先度別タスク一覧

### 🔴 最優先（次に取り組むべき）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 1 | ~~**メッセージ画像表示**~~ | ✅ 完了 | - |
| 2 | ~~**メッセージ画像添付**~~ | ✅ 完了 | - |
| 3 | ~~**メッセージ編集**~~ | ✅ 完了 | - |
| 4 | ~~**メッセージ返信**~~ | ✅ 完了 | - |

### 🟡 高優先（MVP後すぐ）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 5 | ~~**体重グラフ表示**~~ | ✅ 完了 | - |
| 6 | ~~**クライアント編集**~~ | ✅ 完了 | - |
| 7 | ~~**クライアントQRコード招待**~~ | ✅ 完了 | - |
| 8 | ~~**チケット管理**~~ | ✅ 完了 | - |

### 🟢 中優先（アップデート）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 9 | ~~**設定画面**~~ | ✅ 完了 | - |
| 10 | ~~**レポート基盤**~~ | ✅ 完了 | - |
| 11 | ~~**エクスポート機能**~~ | ✅ 完了 | - |

### ⚪ 低優先（将来実装）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 12 | **ワークアウトプラン** | プラン作成・割り当て | 大 |
| 13 | **プッシュ通知** | Web Push実装 | 大 |
| 14 | **ダークモード** | テーマ切り替え | 中 |

---

## 技術的負債・改善項目

### コード品質

- [ ] TypeScript strict mode 有効化
- [ ] ESLint ルール強化
- [ ] コンポーネントの共通化整理

### パフォーマンス

- [ ] `messages`テーブルのインデックス追加
- [ ] 画像の遅延読み込み
- [ ] バンドルサイズ最適化

### テスト

- [ ] ユニットテスト作成
- [ ] E2Eテスト作成（Playwright）
- [ ] APIテスト作成

### ドキュメント

- [ ] API仕様書作成
- [ ] コンポーネントカタログ作成（Storybook検討）
- [ ] デプロイ手順書作成

---

## ファイル構成（計画）

### 追加予定ファイル

```
src/
├── app/
│   ├── api/
│   │   ├── messages/
│   │   │   └── edit/
│   │   │       └── route.ts          # メッセージ編集API ✅
│   │   └── client-notes/
│   │       ├── route.ts              # カルテ作成API ✅
│   │       └── [id]/
│   │           └── route.ts          # カルテ更新・削除API ✅
│   └── (user_console)/
│       ├── clients/
│       │   └── [client_id]/
│       │       └── tickets/
│       │           └── page.tsx      # チケット管理画面
│       ├── report/
│       │   └── page.tsx              # レポート画面（本実装）
│       ├── workoutplan/
│       │   └── page.tsx              # ワークアウト画面（本実装）
│       └── settings/
│           └── page.tsx              # 設定画面（本実装）
├── components/
│   ├── clients/
│   │   ├── ClientEditModal.tsx       # クライアント編集モーダル ✅
│   │   ├── ClientInviteModal.tsx     # QRコード招待モーダル ✅
│   │   ├── WeightChart.tsx           # 体重グラフ ✅
│   │   └── TicketCreateModal.tsx     # チケット作成モーダル
│   ├── messages/
│   │   ├── ImageUploader.tsx         # 画像アップローダー ✅
│   │   ├── ReplyPreview.tsx          # 返信プレビュー ✅
│   │   ├── ReplyQuote.tsx            # 返信引用 ✅
│   │   └── ImageGallery.tsx          # 画像ギャラリー
│   └── settings/
│       └── ProfileEditForm.tsx       # プロフィール編集フォーム
├── lib/
│   └── supabase/
│       ├── uploadMessageImage.ts     # 画像アップロード ✅
│       ├── editMessage.ts            # メッセージ編集 ✅
│       ├── getMessageById.ts         # メッセージ取得 ✅
│       ├── getClientNotes.ts         # カルテ一覧取得 ✅
│       ├── uploadNoteFile.ts         # カルテファイルアップロード ✅
│       ├── deleteNoteFile.ts         # カルテファイル削除 ✅
│       ├── updateClient.ts           # クライアント更新
│       └── createTicket.ts           # チケット作成
└── types/
    └── client.ts                     # 型定義更新
```

---

## 参考リンク

- [Next.js公式ドキュメント](https://nextjs.org/docs)
- [Supabase公式ドキュメント](https://supabase.com/docs)
- [Radix UI公式ドキュメント](https://www.radix-ui.com/docs)
- [Tailwind CSS公式ドキュメント](https://tailwindcss.com/docs)
- [recharts公式ドキュメント](https://recharts.org/)
- [React Hook Form公式ドキュメント](https://react-hook-form.com/)

---

## 関連ドキュメント

- [REQUIREMENTS.md](../REQUIREMENTS.md) - 要件定義書
- [CLAUDE.md](../CLAUDE.md) - 開発ガイドライン
- [ROADMAP.md](../ROADMAP.md) - 開発ロードマップ

---

**最終更新**: 2026年2月22日 - ワークアウト機能強化（v2.2）
