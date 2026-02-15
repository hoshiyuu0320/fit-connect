# FIT-CONNECT Mobile - 実装タスク一覧

**作成日**: 2025年12月30日
**バージョン**: 3.5
**進捗状況**: 全体 99% 完了
**最終更新**: 2026年2月15日 - カルテ（クライアントノート）閲覧機能実装完了

---

## 目次

1. [実装状況サマリー](#実装状況サマリー)
2. [最新の変更履歴](#最新の変更履歴)
3. [フェーズ別タスク一覧](#フェーズ別タスク一覧)
4. [データ層](#データ層)
5. [認証機能](#認証機能)
6. [メッセージ機能](#メッセージ機能)
7. [記録機能](#記録機能)
8. [目標管理](#目標管理)
9. [UI/UX](#uiux)
10. [インフラ・設定](#インフラ設定)
11. [テスト](#テスト)
12. [今後のタスク](#今後のタスク)

---

## 実装状況サマリー

### 完了率

| カテゴリ | 進捗 | 状態 |
|---------|------|------|
| **UI/画面レイアウト** | 100% | 🟢 完了 |
| **データモデル** | 100% | 🟢 完了 |
| **Repositoryレイヤー** | 100% | 🟢 完了 |
| **Riverpod Provider** | 100% | 🟢 完了 |
| **Supabase統合** | 100% | 🟢 完了 |
| **Supabase Storage** | 100% | 🟢 完了 |
| **リアルタイム機能** | 100% | 🟢 完了 |
| **Edge Functions** | 100% | 🟢 完了 |
| **UIプレビュー関数** | 95% | 🟡 進行中 |
| **日本語対応** | 100% | 🟢 完了 |
| **テスト** | 0% | 🔴 未着手 |

### 完了済み項目

- ✅ プロジェクト構造・アーキテクチャ設計
- ✅ Material 3 テーマシステム
- ✅ カラーパレット定義
- ✅ Supabase Service 初期化
- ✅ 基本的な画面レイアウト（ホーム、メッセージ、記録）
- ✅ ボトムナビゲーション
- ✅ ログイン画面UI（レスポンシブ対応済み）
- ✅ 認証ルーティング
- ✅ データベースマイグレーション（RLSポリシー追加）
- ✅ データモデル作成（8ファイル）
- ✅ Repositoryレイヤー実装（5ファイル）
- ✅ Riverpodプロバイダー作成（7ファイル）
- ✅ **フェーズ1: データ基盤構築 完了**
- ✅ 体重記録画面の実データ接続（Riverpod統合）
- ✅ 食事記録画面の実データ接続（Riverpod統合）
- ✅ 期間フィルタ機能（PeriodFilter enum）
- ✅ UIプレビュー関数作成（meal_card, meal_summary_card, meal_record_screen）
- ✅ 運動記録画面の実データ接続（Riverpod統合）
- ✅ UIプレビュー関数作成（exercise_record_screen）
- ✅ ホーム画面の実データ接続（Riverpod統合）
- ✅ GoalCard・DailySummaryCardの実データ対応
- ✅ UIプレビュー関数作成（home_screen, daily_summary_card）
- ✅ DailySummaryCardセクション別ナビゲーション（Meals→食事タブ, Activity→運動タブ, Weight→体重タブ）
- ✅ タップエフェクト実装（InkWell ripple）
- ✅ RecordsScreenの初期タブ指定対応（initialTabIndex）
- ✅ 食事記録の週カレンダー実装（MealWeekCalendar）
- ✅ 食事記録の月カレンダー実装（MealMonthCalendar - GitHub草スタイル）
- ✅ 運動記録の週カレンダー実装（ExerciseWeekCalendar - アイコン表示）
- ✅ UIプレビュー関数作成（meal_week_calendar, meal_month_calendar, exercise_week_calendar）
- ✅ 体重記録のグラフ実装（fl_chart - 折れ線グラフ、目標体重点線、ツールチップ）
- ✅ UIプレビュー関数作成（weight_record_screen）
- ✅ メッセージリアルタイム機能実装（Supabase Realtime Channel）
- ✅ メッセージ画面のRiverpod統合（paginatedMessagesProvider）
- ✅ メッセージページネーション実装（cursor-based + Realtime channel）
- ✅ 画像ギャラリー実装（フルスクリーンビューア、ピンチズーム、スワイプ送り）
- ✅ メッセージ送信機能実装（タグ自動解析付き）
- ✅ メッセージ自動スクロール機能（画面遷移時・新規メッセージ受信時）
- ✅ UIプレビュー関数作成（message_screen）
- ✅ Edge Functions実装（parse-message-tags - タグ解析・記録自動作成）
- ✅ Database Webhookトリガー設定（messages INSERT時にEdge Function起動）
- ✅ タグ候補UI実装（#入力時の候補表示、選択後のヒント表示）
- ✅ タグ入力バリデーション（タグのみ送信防止）
- ✅ 認証プロバイダーの無限ループバグ修正（tokenRefreshed対応）
- ✅ トレーナー名表示（RLSポリシー追加 - クライアントが自分のトレーナーのプロフィール取得可能）
- ✅ メッセージ画面のキーボード制御（入力欄以外タップで閉じる、タグ選択後フォーカス維持）
- ✅ リモートEdge Function URL修正（本番環境対応）
- ✅ **画像添付機能実装**
  - ✅ Supabase Storage バケット作成（message-photos）
  - ✅ StorageService実装（画像ピック・圧縮・アップロード）
  - ✅ ChatInputカメラボタン機能実装
  - ✅ 画像プレビューUI（削除ボタン付き）
  - ✅ アップロード中ローディング表示
  - ✅ iOSカメラ・フォトライブラリ権限設定
  - ✅ iOSローカライゼーション設定（日本語UI）
- ✅ **目標達成機能実装**
  - ✅ GoalAchievementProvider作成（達成状態監視）
  - ✅ GoalAchievementOverlay作成（Confettiアニメーション付きお祝いモーダル）
  - ✅ MainScreenに達成検知・お祝い表示ロジック追加
  - ✅ GoalCard達成時の特別表示（ゴールド背景、トロフィーアイコン）
  - ✅ UIプレビュー関数作成（GoalCard - In Progress / Achieved）
- ✅ **UI日本語対応（ローカライゼーション）**
  - ✅ GoalCard: 全ラベル日本語化（目標進捗、現在、目標、残り/達成/超過、達成率、期限）
  - ✅ WeightRecordScreen: 日本語化（現在、目標、残り/達成/超過、達成率、開始時比、体重推移、最近の記録）
  - ✅ DailySummaryCard: 日本語化（今日のまとめ、体重、食事、運動、今週、/7日、データなし）
  - ✅ 動的ラベル対応（残り/達成/超過 - 減量・増量両対応）
- ✅ **達成率ロジック修正**
  - ✅ GoalCard: 増量目標で逆方向（体重減少）の場合に正しく0%表示されるよう修正
  - ✅ 方向を考慮した進捗計算（減量: initial→target減少、増量: initial→target増加）
- ✅ **ログイン画面レスポンシブ対応**
  - ✅ iPhone 12 miniなど小さい端末でキーボード表示時のオーバーフロー修正
  - ✅ SingleChildScrollView + LayoutBuilder + ConstrainedBox対応
- ✅ **QRコード招待フロー実装**
  - ✅ オンボーディング画面作成（onboarding_screen.dart）
  - ✅ QRコードスキャン画面作成（qr_scan_screen.dart - mobile_scanner使用）
  - ✅ 招待コード手動入力画面作成（invite_code_screen.dart）
  - ✅ トレーナー確認画面作成（trainer_confirm_screen.dart）
  - ✅ 登録状態管理Provider作成（registration_provider.dart）
  - ✅ ログイン画面の登録フロー対応（isRegistrationパラメータ）
  - ✅ 登録完了画面作成（registration_complete_screen.dart - 紙吹雪アニメーション付き）
  - ✅ app.dartルーティング変更（未ログイン→オンボーディング、登録中→登録完了画面）
- ✅ **ウェルカム画面追加（2026/02/01）**
  - ✅ welcome_screen.dart 新規作成（新規登録/ログイン選択画面）
  - ✅ 既存ユーザー向けログインリンク追加
  - ✅ ログイン認証後のNavigator問題修正（popUntilで解決）
- ✅ **データベーススキーマ変更（2026/02/01）**
  - ✅ profilesテーブル → trainersテーブルに変更（トレーナー専用）
  - ✅ clientsテーブルにemailカラム追加
  - ✅ マイグレーションファイル作成（20260131000001_migrate_profiles_to_trainers.sql）
  - ✅ ロールバックスクリプト作成
  - ✅ Trainerモデル作成（trainer_model.dart）
  - ✅ Clientモデル更新（emailフィールド追加）
  - ✅ Providerの参照先更新（profiles→trainers）
  - ✅ 関連画面の修正（message_screen.dart等）
- ✅ **リプライ機能実装（2026/02/01）**
  - ✅ MessageRepositoryにgetMessageById追加
  - ✅ messageByIdProvider追加
  - ✅ ReplyPreview Widget作成（入力欄上部のプレビュー）
  - ✅ ReplyQuote Widget作成（バブル内の引用表示）
  - ✅ MessageBubble長押しメニュー追加（返信オプション）
  - ✅ ChatInput・MessageScreen統合
  - ✅ 送信時のreplyToMessageId保存
  - ✅ UIプレビュー関数追加
- ✅ **ログアウト機能実装（2026/02/01）**
  - ✅ SettingsScreen新規作成（ユーザー情報表示、ログアウトボタン）
  - ✅ MainScreenに設定タブ追加
  - ✅ ログアウト確認ダイアログ
  - ✅ UIプレビュー関数追加
- ✅ **メッセージ編集機能実装（2026/02/01）**
  - ✅ MessageBubbleに編集メニュー・編集済みバッジ追加
  - ✅ ChatInputに編集モード追加（EditPreview Widget）
  - ✅ MessageScreenで編集機能統合
  - ✅ 5分以内編集可能、期限切れエラー表示
  - ✅ UIプレビュー関数追加
- ✅ **プッシュ通知機能実装**
  - ✅ DBマイグレーション（fcm_tokenカラム追加）
  - ✅ NotificationService完全実装（FCMトークン管理・通知表示・タップハンドリング）
  - ✅ Firebase初期化（main.dart - iOS/Androidのみ）
  - ✅ 認証フローFCMトークン管理統合（ログイン時保存・ログアウト時削除）
  - ✅ Edge Function FCM HTTP v1 API通知送信（メッセージ通知・目標達成通知）
  - ✅ iOS entitlements・Android通知チャンネル設定
  - ✅ Webhookペイロードにsender_type/receiver_type追加
  - ✅ セットアップ手順ドキュメント作成

---

## 最新の変更履歴

### 2026年2月15日

#### 14. カルテ（クライアントノート）閲覧機能実装

**目的**: トレーナーがWeb側で作成・共有したカルテ（セッションノート）をクライアントのモバイルアプリで閲覧できるようにする

**新規作成ファイル**:
- `lib/features/client_notes/models/client_note_model.dart` — データモデル（@JsonSerializable）
- `lib/features/client_notes/models/client_note_model.g.dart` — 自動生成
- `lib/features/client_notes/data/client_note_repository.dart` — Supabaseクエリ（getSharedNotes, getSharedNotesCount）
- `lib/features/client_notes/providers/client_notes_provider.dart` — Riverpod Provider（sharedClientNotesProvider）
- `lib/features/client_notes/providers/client_notes_provider.g.dart` — 自動生成
- `lib/features/client_notes/presentation/screens/client_notes_screen.dart` — カルテ一覧画面（Notesタブ）
- `lib/features/client_notes/presentation/screens/client_note_detail_screen.dart` — カルテ詳細画面
- `lib/features/client_notes/presentation/widgets/note_card.dart` — カルテカードWidget
- `supabase/migrations/20260215115338_add_client_notes_select_policy.sql` — RLSポリシー

**改修ファイル**:
- `lib/features/home/presentation/screens/records_screen.dart` — TabController length: 3→4、Notesタブ追加

**実装内容**:

1. **RLSポリシー追加** — `clients_select_shared_notes`：`is_shared = true AND client_id = auth.uid()` で共有済み自分宛てのみ閲覧可能
2. **ClientNoteモデル** — id, clientId, trainerId, title, content, fileUrls(List<String>), isShared, sharedAt, sessionNumber, createdAt, updatedAt
3. **ClientNoteRepository** — `getSharedNotes()`（一覧取得、created_at降順）、`getSharedNotesCount()`（件数取得）
4. **sharedClientNotesProvider** — AsyncProviderでカルテ一覧をRiverpod管理
5. **NoteCard Widget** — セッション番号 + タイトル + 日付 + 本文プレビュー(2行) + ファイル数バッジ + 矢印。プレビュー関数3種
6. **ClientNotesScreen** — サマリーカード（件数表示）+ NoteCardリスト + 空状態表示 + エラーリトライ。プレビュー関数2種
7. **ClientNoteDetailScreen** — ヘッダー（セッション番号、タイトル、トレーナー名、日付）+ 内容（行間1.6）+ 添付ファイル表示（画像→FullScreenImageViewer / PDF→url_launcher）。プレビュー関数2種
8. **RecordsScreen** — 4タブ化（Meals | Weight | Exercise | Notes）

**画面遷移フロー**:
```
Records (TabBar)
  └── Notes (ClientNotesScreen)
        └── [カードタップ] → ClientNoteDetailScreen
              ├── [画像タップ] → FullScreenImageViewer（既存）
              └── [PDFタップ] → 外部ブラウザ
```

---

### 2026年2月10日

#### 13. 画像ギャラリー（フルスクリーンビューア）実装

**目的**: メッセージ画面・食事記録画面の画像タップ時にフルスクリーンで表示する

**新規作成ファイル**:
- `lib/shared/widgets/full_screen_image_viewer.dart` — 共通フルスクリーン画像ビューア

**改修ファイル**:
- `lib/features/messages/presentation/widgets/message_bubble.dart` — 画像タップで `FullScreenImageViewer.show()` 呼び出し
- `lib/features/meal_records/presentation/widgets/meal_card.dart` — 画像タップで `FullScreenImageViewer.show()` 呼び出し

**実装内容**:

1. **FullScreenImageViewer** — `FullScreenImageViewer.show(context, imageUrls, initialIndex)` でどこからでも呼び出し可能
2. **ピンチズーム** — `InteractiveViewer` で 0.5x〜4.0x ズーム
3. **複数画像スワイプ** — `PageView.builder` で横スワイプ送り
4. **ページインジケーター** — 複数画像時のみ「1 / 3」形式で下部に表示
5. **ローディング** — プログレス付きローディング表示
6. **エラーハンドリング** — 破損画像アイコン表示
7. **フェードアニメーション** — `PageRouteBuilder` で黒背景フェードイン遷移

---

#### 12. メッセージページネーション実装

**目的**: メッセージが大量になった場合のパフォーマンス対策。`.stream()` による全件取得を廃止し、cursor-basedページネーション + Realtimeチャンネルに切り替え。

**新規作成ファイル**:
- `lib/features/messages/providers/paginated_messages_state.dart` — ページネーション状態クラス（messages, hasMore, isLoadingMore）

**改修ファイル**:
- `lib/features/messages/data/message_repository.dart` — `fetchMessages()` 追加（cursor-based）、`subscribeToMessages()` 追加（Realtime INSERT/UPDATE購読）、`getMessagesStream()` 削除
- `lib/features/messages/providers/messages_provider.dart` — `PaginatedMessagesNotifier` 新規追加、`messagesStreamProvider`・`MessagesNotifier` 削除、`unreadMessageCountProvider` 依存変更
- `lib/features/messages/presentation/screens/message_screen.dart` — Provider参照切り替え（7箇所）、スクロール検知(`_onScroll`)追加、ローディングインジケータ追加

**実装内容**:

1. **PaginatedMessagesState** — `messages`（古→新）, `hasMore`, `isLoadingMore` を持つイミュータブル状態クラス
2. **fetchMessages()** — `created_at < before` のcursor-basedページネーション（30件ずつ）
3. **subscribeToMessages()** — Realtime channelでINSERT/UPDATEを購読、会話ペアフィルタ
4. **PaginatedMessagesNotifier** — 初回30件fetch + Realtime自動セットアップ、`loadMore()`でスクロール追加ロード、楽観的更新（送信即時表示）、ID重複排除
5. **スクロール検知** — `reverse: true` のListViewで上端接近時に`loadMore()`発火、1秒デバウンス付き
6. **ローディングUI** — 追加ロード中CircularProgressIndicator、全件表示時「これ以上メッセージはありません」

**バグ修正**:
- `before.toIso8601String()` がローカル時間（JST）をタイムゾーンなしで出力 → SupabaseがUTCと解釈 → 9時間先のカーソルで全メッセージ再取得される無限ループ
- **修正**: `before.toUtc().toIso8601String()` でUTC変換 + ID重複排除を安全策として追加

**動作フロー**:
```
初回ロード: 最新30件fetch + Realtime channel開始
  ↓ [上にスクロール]
loadMore(): created_at < oldest.createdAt で30件追加fetch
  ↓ [prepend + 重複排除]
hasMore判定（取得件数 >= 30 なら true）
  ↓ [新着メッセージ]
Realtime INSERT → 末尾に追加（IDで重複チェック）
Realtime UPDATE → 該当メッセージを置換（既読・編集反映）
```

---

### 2026年2月8日

#### 11. 既読機能実装

**目的**: メッセージの既読表示と未読バッジ機能を追加

**DBマイグレーション**:
- `mark_messages_as_read(p_other_user_id uuid)` SECURITY DEFINER関数作成（RLSバイパスで安全に既読更新）
- `idx_messages_unread` 部分インデックス作成（未読検索高速化）

**改修ファイル**:
- `lib/features/messages/data/message_repository.dart` — `markAsRead()` → `markConversationAsRead()` に変更（Supabase RPC呼び出し）
- `lib/features/messages/providers/messages_provider.dart` — `markAsRead()` → `markConversationAsRead()` に変更、`unreadMessageCountProvider` invalidate追加
- `lib/features/messages/presentation/widgets/message_bubble.dart` — `isRead`プロパティ追加、「既読」表示ロジック、プレビュー関数追加
- `lib/features/messages/presentation/screens/message_screen.dart` — `ref.listen`で自動既読処理、`isRead`をMessageBubbleに渡す
- `lib/features/home/presentation/screens/main_screen.dart` — Messageタブに未読数バッジ表示

**実装内容**:

1. **SECURITY DEFINER関数** — RLSをバイパスして受信者が既読更新可能
2. **会話単位の一括既読化** — 個別メッセージIDではなく相手ユーザーID指定でシンプル
3. **自動既読処理** — メッセージ画面表示時に`ref.listen`で未読を検知し自動既読化
4. **LINEスタイル既読表示** — 送信メッセージに「既読 ・ 12:34」表示
5. **未読バッジ** — BottomNavigationBarのMessageタブに赤い数字バッジ

**動作フロー**:
```
メッセージ画面表示
  ↓ [ref.listen で未読検知]
markConversationAsRead() → RPC mark_messages_as_read
  ↓ [DB更新]
unreadMessageCountProvider invalidate → バッジ更新
  ↓ [Realtime Stream]
MessageBubble に isRead=true 反映 → 「既読」表示
```

---

### 2026年2月7日

#### 10. プッシュ通知機能実装

**目的**: メッセージ受信時と目標達成時にプッシュ通知を送信する

**新規作成ファイル**:
- `ios/Runner/Runner.entitlements` — iOS APNs development設定
- `ios/Runner/RunnerRelease.entitlements` — iOS APNs production設定
- `docs/PUSH_NOTIFICATION_SETUP.md` — モバイル側セットアップ手順
- `docs/WEB_PUSH_NOTIFICATION_SETUP.md` — WEBアプリ側セットアップ手順

**改修ファイル**:
- `lib/services/notification_service.dart` — 大幅改修（FCMトークン管理・通知表示・タップハンドリング）
- `lib/main.dart` — Firebase初期化追加（iOS/Androidのみ）
- `lib/app.dart` — ログイン時FCMトークン保存・通知タップハンドリング
- `lib/features/auth/providers/auth_provider.dart` — ログアウト時FCMトークン削除
- `supabase/functions/parse-message-tags/index.ts` — FCM HTTP v1 API通知送信追加
- `android/app/src/main/AndroidManifest.xml` — 通知チャンネルメタデータ追加

**DBマイグレーション**:
- `clients` テーブルに `fcm_token` カラム追加
- `trainers` テーブルに `fcm_token` カラム追加
- Webhookペイロードに `sender_type`/`receiver_type` 追加

**実装内容**:

1. **NotificationService** — 権限リクエスト、FCMトークン取得・保存・削除、フォアグラウンド/バックグラウンド通知表示、通知タップハンドリング、トークンリフレッシュ対応
2. **Firebase初期化** — iOS/Androidのみ（macOS開発環境除外）、try-catchでエラー時もアプリ起動継続
3. **認証フロー統合** — ログイン検知時にFCMトークン自動保存、ログアウト時に自動削除
4. **Edge Function** — FCM HTTP v1 API（サービスアカウントJWT認証 → OAuth2トークン取得 → FCM送信）
5. **通知トリガー**:
   - メッセージINSERT時 → 受信者に「〇〇からのメッセージ」通知
   - 体重記録で目標達成時 → クライアントに「目標達成！」通知
6. **プラットフォーム設定** — iOS entitlements（APNs）、Android通知チャンネル

**手動セットアップ（未実施）**:
- APNsキー作成・Firebase登録（Apple Developer Program登録後）
- Firebaseサービスアカウントキー → Supabase Secrets登録（設定済み）
- Edge Functionデプロイ（デプロイ済み）

**動作確認状況**:
- Edge Function → FCM API送信直前まで正常動作確認済み
- 受信端末のFCMトークン保存後に通知受信可能

---

#### 9. 統計カード拡張

**目的**: 体重記録画面の統計カードに前回比・期間統計を追加

**改修ファイル**:
- `lib/features/weight_records/presentation/screens/weight_record_screen.dart`

**実装内容**:

1. **前回比表示追加**
   - 最新の体重記録と1つ前の記録の差分を表示
   - 「開始時比」ボックスの横に並列配置
   - 減量（マイナス）は緑、増量（プラス）は赤で表示
   - 記録が2件未満の場合は「--」表示

2. **期間統計セクション追加**
   - 既存の`weightStatsProvider`をUI統合（未使用だったProviderを活用）
   - 平均体重、最高体重、最低体重、変動幅を4カラムで表示
   - 期間フィルタ（今週/今月/3ヶ月/全期間）と連動
   - 記録が0件の場合は非表示

3. **プレビュー関数更新**
   - 前回比・期間統計のモックデータ表示を追加

---

### 2026年2月4日

#### 8. プロフィール画像機能実装

**目的**: 設定画面からプロフィール画像を設定・変更できるようにする

**新規作成ファイル**:
- `supabase/migrations/20260204100000_create_client_avatars_bucket.sql`

**改修ファイル**:
- `lib/services/storage_service.dart`
- `lib/features/auth/data/client_repository.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`

**実装内容**:

1. **Supabase Storageバケット作成**
   - バケット名: `client-avatars`
   - 公開: true
   - ファイルサイズ制限: 5MB
   - 許可MIME: image/jpeg, image/png, image/webp, image/heic
   - RLSポリシー: 自分のフォルダにのみアップロード可能

2. **StorageService拡張**
   - `uploadProfileImage(File file, String userId)`: プロフィール画像アップロード
   - `deleteProfileImage(String userId)`: プロフィール画像削除
   - キャッシュバスティング用タイムスタンプ付きURL

3. **ClientRepository拡張**
   - `updateProfileImageUrl(String clientId, String? imageUrl)`: DB更新

4. **SettingsScreen改修**
   - CircleAvatarにカメラアイコンオーバーレイ追加
   - タップで画像選択ダイアログ表示（カメラ/ギャラリー）
   - アップロード中ローディング表示
   - 成功/失敗時のSnackBar表示
   - Provider invalidateで画面更新

**動作フロー**:
```
プロフィール画像タップ → カメラ/ギャラリー選択
  ↓
画像選択 → ローディング表示
  ↓
Storage アップロード → DB更新 → Provider invalidate
  ↓
画面更新 → SnackBar表示
```

---

#### 7. プロフィール編集機能（SettingsScreen拡張）実装

**目的**: 登録後に設定画面からクライアント名を編集できるようにする

**新規作成ファイル**:
- `lib/features/auth/data/client_repository.dart`
- `lib/features/auth/data/client_repository.g.dart` (自動生成)

**改修ファイル**:
- `lib/features/settings/presentation/screens/settings_screen.dart`

**実装内容**:

1. **ClientRepository新規作成**
   - `fetchClient(String clientId)`: クライアント情報を取得
   - `updateClientName(String clientId, String name)`: 名前を更新（updated_atも更新）
   - `clientRepositoryProvider`: Riverpod Provider（@riverpod）

2. **SettingsScreen改修**
   - 名前の横に編集アイコン（LucideIcons.pencil）追加
   - タップで編集ダイアログ表示（AlertDialog）
   - バリデーション: 空チェック、50文字制限
   - 保存成功時: 緑色SnackBar「名前を更新しました」
   - 保存失敗時: 赤色SnackBarでエラー表示
   - `ref.invalidate(currentClientProvider)`で画面更新
   - UIプレビュー関数も編集アイコン付きに更新

**動作フロー**:
```
設定画面 → 名前横の鉛筆アイコンタップ
  ↓
編集ダイアログ表示（現在の名前が初期値）
  ↓
名前を入力して「保存」タップ
  ↓
ClientRepository.updateClientName() 実行
  ↓
成功: currentClientProvider invalidate → 画面更新 → SnackBar表示
失敗: エラーSnackBar表示
```

---

#### 6. 登録時の名前入力画面（ProfileSetupScreen）実装

**目的**: 新規登録フローで、クライアントが自分の名前を入力できるようにする

**新規作成ファイル**:
- `lib/features/auth/presentation/screens/profile_setup_screen.dart`

**改修ファイル**:
- `lib/features/auth/providers/registration_provider.dart`
- `lib/app.dart`

**実装内容**:

1. **ProfileSetupScreen新規作成**
   - 名前入力フォーム（TextFormField、Form）
   - バリデーション: 空チェック、50文字制限
   - ローディング状態の処理
   - エラーハンドリング（SnackBar表示）
   - UIプレビュー関数4種類（Empty, With Name, Loading, Validation Error）

2. **RegistrationState改修**
   - `clientName` フィールド追加
   - `setClientName()` メソッド追加
   - `copyWith()` 対応

3. **completeRegistration()改修**
   - `state.clientName` を使用してINSERT
   - 空の場合はデフォルト値「新規クライアント」を使用

4. **app.dart遷移修正**
   - `registrationState.hasTrainer == true` 時の遷移先を `ProfileSetupScreen` に変更

**動作フロー**:
```
LoginScreen (メール認証)
  ↓ [認証成功]
popUntil → app.dart StreamBuilder
  ↓ [registrationState.hasTrainer == true]
ProfileSetupScreen (名前入力)
  ↓ [登録完了ボタン]
setClientName() → completeRegistration() → invalidate(currentClientProvider)
  ↓
RegistrationCompleteScreen (紙吹雪アニメーション)
  ↓ [トレーニングを始める]
MainScreen
```

---

### 2026年2月1日

#### 5. メッセージ編集機能実装

**目的**: 送信後5分以内のメッセージを編集できるようにする

**改修ファイル**:
- `lib/features/messages/presentation/widgets/message_bubble.dart`
- `lib/features/messages/presentation/widgets/chat_input.dart`
- `lib/features/messages/presentation/screens/message_screen.dart`

**実装内容**:

1. **MessageBubble改修**
   - `onEdit` コールバック追加
   - `isEdited` プロパティ追加
   - 長押しメニューに「編集」オプション追加（自分のメッセージのみ）
   - 「編集済み ・ HH:mm」形式でタイムスタンプ表示
   - プレビュー関数追加（3種類）

2. **ChatInput改修**
   - `editingMessageId`, `editingMessageContent`, `onCancelEdit` プロパティ追加
   - `EditPreview` Widget追加（アンバー系カラーで返信と区別）
   - 編集モード時のテキスト初期値設定
   - 送信ボタンアイコン切り替え（send → check）
   - プレビュー関数追加（5種類）

3. **MessageScreen改修**
   - 編集状態管理（`_editingMessageId`, `_editingMessageContent`）
   - `_setEditTarget()`, `_clearEditTarget()` 関数追加
   - `_editMessage()` 関数追加（MessageRepository.editMessage呼び出し）
   - 返信と編集の排他制御
   - 編集期限切れ時のエラーSnackBar表示

**動作フロー**:
```
メッセージ長押し → 「編集」タップ
  ↓
ChatInputにEditPreview表示、テキスト初期値セット
  ↓
編集してチェックマークタップ
  ↓
can_edit_message() で5分以内か判定
  ↓
OK: messages UPDATE、edited_at/is_edited更新
NG: 「編集可能な時間（5分）を過ぎました」エラー表示
  ↓
MessageBubbleに「編集済み」バッジ表示
```

---

#### 4. ログアウト機能実装

**目的**: ユーザーがログアウトできるようにする

**新規作成ファイル**:
- `lib/features/settings/presentation/screens/settings_screen.dart`

**改修ファイル**:
- `lib/features/home/presentation/screens/main_screen.dart`

**実装内容**:
1. **SettingsScreen**
   - ユーザー情報表示（名前、メール、担当トレーナー）
   - プロフィール画像表示（存在する場合）
   - ログアウトボタン（赤色、警告色）
   - 確認ダイアログ（タイトル: "ログアウト"、メッセージ: "ログアウトしますか？"）
   - `ref.read(authNotifierProvider.notifier).signOut()` 呼び出し
   - エラーハンドリング（失敗時はSnackBar表示）
   - プレビュー関数（`@Preview`アノテーション）

2. **MainScreen更新**
   - BottomNavigationBarに4つ目のタブ「設定」追加
   - アイコン: `LucideIcons.settings`

**動作フロー**:
```
設定タブタップ → SettingsScreen表示
  ↓
ログアウトボタンタップ → 確認ダイアログ表示
  ↓
「ログアウト」タップ → signOut()呼び出し
  ↓
app.dart StreamBuilderが検知 → WelcomeScreenへ自動遷移
```

---

#### 1. ウェルカム画面の追加

**目的**: 既存ユーザーがログインできるようにする

**変更ファイル**:
- `lib/features/auth/presentation/screens/welcome_screen.dart` (新規)
- `lib/features/auth/presentation/screens/onboarding_screen.dart` (改修)
- `lib/features/auth/presentation/screens/login_screen.dart` (改修)
- `lib/app.dart` (改修)

**変更内容**:
- WelcomeScreen: 「新規登録」ボタンと「ログインはこちら」リンクを表示
- 新規登録 → OnboardingScreen（QRスキャンフロー）
- ログイン → LoginScreen（メール認証のみ）
- ログイン認証後にLoginScreenに留まるバグを修正（StreamSubscriptionで認証状態を監視し、popUntilで解決）

#### 2. データベーススキーマ変更（profiles → trainers）

**目的**: profilesテーブルをトレーナー専用のtrainersテーブルに変更

**変更ファイル**:
- `supabase/migrations/20260131000001_migrate_profiles_to_trainers.sql` (新規)
- `supabase/rollback_migrate_profiles_to_trainers.sql` (新規)
- `lib/features/auth/models/trainer_model.dart` (新規)
- `lib/features/auth/models/client_model.dart` (改修)
- `lib/features/auth/models/user_model.dart` (削除)
- `lib/features/auth/providers/auth_provider.dart` (改修)
- `lib/features/auth/providers/current_user_provider.dart` (改修)
- `lib/features/auth/providers/registration_provider.dart` (改修)
- `lib/features/messages/presentation/screens/message_screen.dart` (改修)

**マイグレーション内容**:
```sql
-- trainersテーブル作成
CREATE TABLE IF NOT EXISTS "public"."trainers" (
    "id" "uuid" NOT NULL,
    "name" "text" NOT NULL DEFAULT '',
    "email" "text",
    "profile_image_url" "text",
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    "updated_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT "trainers_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "trainers_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE
);

-- clientsテーブルにemailカラム追加
ALTER TABLE "public"."clients" ADD COLUMN IF NOT EXISTS "email" TEXT;

-- 外部キー制約をtrainersに変更
-- clients.trainer_id → trainers.id
-- sessions.trainer_id → trainers.id
```

**Trainerモデル**:
```dart
@JsonSerializable()
class Trainer {
  final String id;
  final String name;
  final String? email;
  @JsonKey(name: 'profile_image_url')
  final String? profileImageUrl;
  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
}
```

#### 3. リプライ機能実装

**目的**: メッセージに返信できる機能を追加

**新規作成ファイル**:
- `lib/features/messages/presentation/widgets/reply_preview.dart`
- `lib/features/messages/presentation/widgets/reply_quote.dart`

**改修ファイル**:
- `lib/features/messages/data/message_repository.dart`
- `lib/features/messages/providers/messages_provider.dart`
- `lib/features/messages/presentation/widgets/message_bubble.dart`
- `lib/features/messages/presentation/widgets/chat_input.dart`
- `lib/features/messages/presentation/screens/message_screen.dart`

**機能詳細**:

1. **ReplyPreview Widget** (`reply_preview.dart`)
   - ChatInput上部に表示される返信先プレビュー
   - プロパティ: `messageContent`, `onCancel`
   - キャンセルボタンで返信をクリア

2. **ReplyQuote Widget** (`reply_quote.dart`)
   - MessageBubble内に表示される引用ブロック
   - プロパティ: `senderName`, `messageContent`, `isUserMessage`
   - ユーザーメッセージとトレーナーメッセージでスタイル切り替え

3. **MessageBubble改修** (`message_bubble.dart`)
   - 新規プロパティ追加:
     - `messageId`: メッセージID
     - `replyToContent`: 返信先メッセージ内容
     - `replyToSenderName`: 返信先送信者名
     - `onReply`: 返信コールバック
   - 長押しで`showModalBottomSheet`メニュー表示
   - 「返信」オプション（LucideIcons.reply）
   - ReplyQuote統合（返信先がある場合にバブル内に表示）
   - プレビュー関数6種追加

4. **ChatInput改修** (`chat_input.dart`)
   - 新規プロパティ追加:
     - `replyToMessageId`: 返信先メッセージID
     - `replyToContent`: 返信先メッセージ内容
     - `onCancelReply`: 返信キャンセルコールバック
   - `onSend`の型変更: `(String, List<String>?, String?) → void`
   - ReplyPreview表示対応

5. **MessageScreen改修** (`message_screen.dart`)
   - 返信状態管理: `_replyToMessageId`, `_replyToContent`
   - `_setReplyTarget(Message)`: 返信先セット
   - `_clearReplyTarget()`: 返信先クリア
   - `findMessageById()`: メッセージリスト内検索
   - MessageBubbleへの返信情報渡し
   - ChatInputへの返信情報渡し

6. **MessageRepository改修** (`message_repository.dart`)
   ```dart
   Future<Message?> getMessageById(String messageId) async {
     try {
       final response = await _supabase
           .from('messages')
           .select()
           .eq('id', messageId)
           .maybeSingle();
       if (response == null) return null;
       return Message.fromJson(response);
     } catch (e) {
       return null;
     }
   }
   ```

7. **messages_provider改修** (`messages_provider.dart`)
   ```dart
   @riverpod
   Future<Message?> messageById(MessageByIdRef ref, String messageId) async {
     final repository = ref.watch(messageRepositoryProvider);
     return repository.getMessageById(messageId);
   }
   ```

**動作フロー**:
```
1. ユーザーがメッセージを長押し
   ↓
2. ModalBottomSheetで「返信」メニュー表示
   ↓
3. 「返信」タップ → _setReplyTarget() 呼び出し
   ↓
4. ChatInput上部にReplyPreview表示
   ↓
5. メッセージ入力して送信
   ↓
6. sendMessage(content, imageUrls, replyToMessageId)
   ↓
7. _clearReplyTarget() で返信状態クリア
   ↓
8. 送信されたメッセージにReplyQuote表示
```

---

## フェーズ別タスク一覧

### 📌 フェーズ1: データ基盤構築 ✅ 完了

**目的**: モックデータから実データへの移行基盤を整備

（省略 - 全タスク完了済み）

---

### 📌 フェーズ2: メッセージ機能（コア機能）

**目的**: アプリの最重要機能である「メッセージベースの記録作成」を実現

#### タスク

- [x] **2.1 基本メッセージ機能** ✅ 完了
- [x] **2.2 タグ機能実装** ✅ 完了
- [x] **2.3 Edge Functions作成** ✅ 基本実装完了

- [x] **2.4 リプライ機能** ✅ 完了（2026/02/01）
  - [x] メッセージ長押し → 返信メニュー表示（ModalBottomSheet）
  - [x] 引用表示付き入力欄（ReplyPreview Widget）
  - [x] `reply_to_message_id` の保存（sendMessage改修）
  - [x] リプライ表示UI（ReplyQuote Widget - バブル内引用）
  - [x] MessageBubbleプレビュー関数追加（6種類）

- [x] **2.5 メッセージ編集** ✅ 完了（2026/02/01）
  - [x] 5分以内の編集可能判定（Database Function: `can_edit_message` - 既存）
  - [x] 編集UI（メッセージ長押し → 編集メニュー追加）
  - [x] 編集入力モード（ChatInput EditPreview追加）
  - [x] `edited_at` タイムスタンプ記録（MessageRepository.editMessage）
  - [x] 「編集済み」バッジ表示（MessageBubble）
  - [x] プレビュー関数追加（MessageBubble、ChatInput）
  - [ ] タグ変更時の記録更新ロジック（将来実装）

- [x] **2.6 既読機能** ✅ 完了（2026/02/08）
  - [x] `read_at` タイムスタンプ更新（SECURITY DEFINER関数経由）
  - [x] 既読表示UI（LINEスタイル「既読」表示）
  - [x] 自動既読処理（画面表示時に`ref.listen`で検知）
  - [x] 未読バッジ（MainScreen BottomNavigationBar）

- [x] **2.7 ページネーション** ✅ 完了（2026/02/10）
  - [x] cursor-basedページネーション（30件ずつ）
  - [x] 無限スクロール実装（スクロール検知 + デバウンス）
  - [x] Realtime channel切り替え（.stream()廃止）
  - [x] 楽観的更新 + ID重複排除

**期待される成果**: メッセージ送信 → 自動的に体重/食事/運動記録が作成される ✅ 達成

---

### 📌 フェーズ3: 記録機能の強化 ✅ ほぼ完了

（省略 - 主要タスク完了済み）

---

### 📌 フェーズ4: 目標管理機能 ✅ ほぼ完了

（省略 - 主要タスク完了済み）

---

### 📌 フェーズ5: 認証フロー強化 ✅ ほぼ完了

**目的**: QRコード招待とマジックリンクによる初回登録フローを完成

#### タスク

- [x] **5.1 QRコード招待フロー** ✅ 完了
- [x] **5.2 マジックリンク認証** ✅ 既存実装あり
- [x] **5.3 初回登録時のデータ作成** ✅ 完了
- [x] **5.4 ウェルカム画面** ✅ 完了（2026/02/01）
  - [x] 新規登録/ログイン選択画面
  - [x] ログイン認証後のNavigator問題修正

- [x] **5.5 セッション管理** ✅ 完了（2026/02/01）
  - [x] 自動トークンリフレッシュ確認
  - [x] **ログアウト機能実装**
    - [x] 設定画面（SettingsScreen）新規作成
    - [x] MainScreenに設定タブ追加
    - [x] ログアウト確認ダイアログ
    - [x] signOut() 呼び出し
    - [x] WelcomeScreenへ自動遷移（app.dart StreamBuilder）

**期待される成果**: トレーナーがQRコードを表示 → クライアントがスキャン → メール認証 → 登録完了の全フローが動作 ✅

---

### 📌 フェーズ6: プッシュ通知 ✅ 実装完了

**目的**: メッセージ受信時や目標達成時にリアルタイム通知

#### タスク

- [x] **6.1 Firebase設定**
  - [x] iOS: `ios/Runner/GoogleService-Info.plist` 確認
  - [x] Android: `android/app/google-services.json` 確認
  - [x] Firebase初期化（main.dart - iOS/Androidのみ）
  - [x] iOS entitlements作成（development/production）
  - [x] Android通知チャンネルメタデータ追加

- [x] **6.2 NotificationService 実装**
  - [x] 権限リクエスト・FCMトークン取得
  - [x] フォアグラウンド通知表示（flutter_local_notifications）
  - [x] バックグラウンド通知ハンドリング
  - [x] 通知タップハンドリング（onMessageOpenedApp / getInitialMessage）
  - [x] FCMトークンSupabase保存（saveTokenToSupabase）
  - [x] FCMトークン削除（clearTokenFromSupabase）
  - [x] トークンリフレッシュリスナー

- [x] **6.3 認証フロー統合**
  - [x] ログイン時FCMトークン自動保存（app.dart）
  - [x] ログアウト時FCMトークン自動削除（auth_provider.dart）

- [x] **6.4 Edge Function連携**
  - [x] FCM HTTP v1 API送信機能（サービスアカウントJWT認証）
  - [x] メッセージINSERT時の通知送信
  - [x] 目標達成時の通知送信
  - [x] Webhookペイロードにsender_type/receiver_type追加

- [ ] **6.5 手動セットアップ（残タスク）**
  - [x] Firebaseサービスアカウントキー → Supabase Secrets登録
  - [x] Edge Functionデプロイ
  - [ ] APNs認証キー作成・Firebase登録（Apple Developer Program登録後）

**期待される成果**: メッセージ受信時・目標達成時にプッシュ通知が届く ✅ 実装完了（APNs設定後にiOS実機で動作）

---

### 📌 フェーズ7: ユーザープロフィール機能

**目的**: クライアントが自分の名前を登録・編集できるようにする

#### 設計方針

- **目標設定（initial_weight, target_weight, target_date）**: トレーナー側で設定（トレーナー用管理画面/アプリで実装）
- **クライアント名**: クライアント自身が登録時・登録後に設定可能

#### タスク

- [x] **7.1 登録時の名前入力画面** ✅ 完了（2026/02/04）
  - [x] `ProfileSetupScreen` 新規作成（`lib/features/auth/presentation/screens/`）
  - [x] 名前入力フォーム（TextFormField、バリデーション：空チェック、50文字制限）
  - [x] 登録フローへの組み込み（LoginScreen → ProfileSetupScreen → RegistrationCompleteScreen）
  - [x] `completeRegistration()` 修正（`RegistrationState.clientName`から取得）
  - [x] **`completeRegistration()` でemailカラムにも保存**（`currentUser?.email`を使用）- 既存実装済み
  - [x] UIプレビュー関数作成（4種類：Empty, With Name, Loading, Validation Error）

- [x] **7.2 プロフィール編集機能（設定画面拡張）** ✅ 完了（2026/02/04）
  - [x] `SettingsScreen` にプロフィール編集セクション追加
  - [x] 名前編集機能（タップで編集ダイアログ表示）
  - [x] ClientRepository 新規作成（`fetchClient()`, `updateClientName()`）
  - [x] clients テーブルの UPDATE RLSポリシー確認（`clients_update_own` 既存）
  - [x] 保存成功時のフィードバック（緑色SnackBar）
  - [x] `ref.invalidate(currentClientProvider)` で画面リフレッシュ
  - [x] UIプレビュー関数更新（編集アイコン付き）

- [x] **7.3 プロフィール画像機能** ✅ 完了（2026/02/04）
  - [x] Supabase Storage バケット作成（`client-avatars`）
  - [x] StorageService拡張（`uploadProfileImage()`, `deleteProfileImage()`）
  - [x] ClientRepository拡張（`updateProfileImageUrl()`）
  - [x] 画像選択・アップロード機能（カメラ/ギャラリー）
  - [x] 画像圧縮（既存のImagePicker設定で対応）
  - [x] SettingsScreenでの表示・変更機能
  - [x] カメラアイコンオーバーレイ
  - [x] ローディング表示・SnackBarフィードバック

#### 実装優先度

1. **7.1 登録時の名前入力** - 最優先（新規登録UXに直接影響）
2. **7.2 プロフィール編集** - 高優先（登録後の変更手段）
3. **7.3 プロフィール画像** - 中優先（あると良い機能）

**期待される成果**: 新規登録時にクライアント名を設定でき、登録後も設定画面から名前・プロフィール画像を変更可能 ✅ 達成

---

## 既知の問題・要調査

### ✅ 新規登録後の不具合（2026/02/01 報告 → 2026/02/04 修正完了）

新規登録を行った直後に以下の問題が発生していた（**修正済み**）：

| # | 症状 | 原因 | 修正内容 |
|---|------|------|----------|
| 1 | 「ユーザー情報を読み込めませんでした」 | `completeRegistration`後にProvider invalidateがなかった | `ref.invalidate(currentClientProvider)`追加 |
| 2 | ログアウトできない | `pushAndRemoveUntil`がStreamBuilderと切断 | `popUntil`に変更しルートに戻る |
| 3 | トレーナー名が表示されない | 不具合1と同じ依存チェーン | 不具合1の修正で解決 |

**修正ファイル:**
- `lib/features/auth/providers/registration_provider.dart` - INSERT後に`ref.invalidate(currentClientProvider)`追加
- `lib/features/auth/presentation/screens/registration_complete_screen.dart` - `pushAndRemoveUntil` → `popUntil((route) => route.isFirst)`に変更

---

## 今後のタスク

### 🔴 最優先（次に取り組むべき）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| ~~0~~ | ~~**新規登録後の不具合調査・修正**~~ | ✅ 完了（2026/02/04） | - |
| ~~1~~ | ~~**登録時の名前入力画面**~~ | ✅ 完了（2026/02/04） | - |
| ~~2~~ | ~~**プロフィール編集機能**~~ | ✅ 完了（2026/02/04） | - |
| ~~3~~ | ~~**統計カード拡張**~~ | ✅ 完了（2026/02/07） | - |

### 🟡 高優先（MVP後すぐ）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| ~~4~~ | ~~**プッシュ通知**~~ | ✅ 完了（2026/02/07） | - |
| ~~5~~ | ~~**既読機能**~~ | ✅ 完了（2026/02/08） | - |
| ~~6~~ | ~~**ページネーション**~~ | ✅ 完了（2026/02/10） | - |
| ~~7~~ | ~~**画像ギャラリー**~~ | ✅ 完了（2026/02/10） | - |
| ~~8~~ | ~~**プロフィール画像**~~ | ✅ 完了（2026/02/04） | - |

### 🟢 中優先（アップデート）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 9 | **ダークモード** | テーマ切り替え、ダークカラーパレット | 中 |
| 10 | **画像最適化** | cached_network_image、プレースホルダー | 小 |
| 11 | **アニメーション強化** | ページ遷移、リスト項目フェードイン | 中 |
| 12 | **エラーハンドリング強化** | スケルトンローダー、リトライボタン | 中 |

### ⚪ 低優先（将来実装）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 13 | **LINE連携** | LINE Login SDK、OAuth統合 | 大 |
| 14 | **カロリー自動算出** | AI画像認識連携 | 大 |
| 15 | **オフライン対応** | ローカルキャッシュ、同期機能 | 大 |
| 16 | **メッセージ検索** | キーワード検索、タグフィルタ | 中 |
| 17 | **データエクスポート** | CSV/PDF出力 | 中 |
| 18 | **テスト実装** | ユニット、ウィジェット、統合テスト | 大 |

---

## 技術的負債・改善項目

### コード品質

- [ ] 非推奨メソッドの更新（`withOpacity` → `withValues`）
- [ ] Riverpod Ref型の更新（deprecated警告対応）
- [ ] 共通コンポーネント整理（PeriodFilterButtons, RecordCard, StatCard等）

### テスト

- [ ] ユニットテスト作成
- [ ] ウィジェットテスト作成
- [ ] 統合テスト作成
- [ ] Edge Functionsテスト作成

### ドキュメント

- [ ] API仕様書作成
- [ ] コンポーネントカタログ作成
- [ ] デプロイ手順書作成

---

## ファイル構成（主要変更）

### 2026/02/01 変更ファイル一覧

```
lib/
├── app.dart                                          # ルーティング変更
├── features/
│   ├── auth/
│   │   ├── models/
│   │   │   ├── client_model.dart                     # email追加
│   │   │   ├── trainer_model.dart                    # 新規作成
│   │   │   └── user_model.dart                       # 削除
│   │   ├── presentation/screens/
│   │   │   ├── welcome_screen.dart                   # 新規作成
│   │   │   ├── login_screen.dart                     # 認証状態監視追加
│   │   │   └── onboarding_screen.dart                # 簡略化
│   │   └── providers/
│   │       ├── auth_provider.dart                    # Supabase User直接返却
│   │       ├── current_user_provider.dart            # trainers参照
│   │       └── registration_provider.dart            # trainers参照
│   ├── home/
│   │   └── presentation/screens/
│   │       └── main_screen.dart                      # 設定タブ追加
│   ├── settings/                                     # 新規ディレクトリ
│   │   └── presentation/screens/
│   │       └── settings_screen.dart                  # 新規作成（ログアウト機能）
│   └── messages/
│       ├── data/
│       │   └── message_repository.dart               # getMessageById追加
│       ├── presentation/
│       │   ├── screens/
│       │   │   └── message_screen.dart               # リプライ統合
│       │   └── widgets/
│       │       ├── chat_input.dart                   # ReplyPreview対応
│       │       ├── message_bubble.dart               # 長押しメニュー、ReplyQuote
│       │       ├── reply_preview.dart                # 新規作成
│       │       └── reply_quote.dart                  # 新規作成
│       └── providers/
│           └── messages_provider.dart                # messageByIdProvider追加
supabase/
├── migrations/
│   └── 20260131000001_migrate_profiles_to_trainers.sql  # 新規
└── rollback_migrate_profiles_to_trainers.sql            # 新規
```

---

## 参考リンク

- [Supabase公式ドキュメント](https://supabase.com/docs)
- [Flutter公式ドキュメント](https://flutter.dev/docs)
- [Riverpod公式ドキュメント](https://riverpod.dev/)
- [fl_chart公式ドキュメント](https://pub.dev/packages/fl_chart)
- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)

---

**最終更新**: 2026年2月10日 - 画像ギャラリー実装完了（v3.4）
