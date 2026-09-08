# フェーズ8.3前半 セッション表示（Mobile）— 実装計画（確定版）

**作成**: 2026-09-06 / ブランチ: `feature/mobile-session-display`
**出典**: `2026-07-08-solution-catalog.md` cat4 課題2
**スコープ判断（2026-09-06 オーナー決定）**: 8.3 のうち **①セッション表示のみ先行**。②前日リマインダーは Vault シークレット（`project_url` / `service_role_key`）が未登録で本番発火しないため別 PR に分離。

## 実測で確定した前提（リモートDB / コードベース）

- `sessions` は初期スキーマ定義済み。`status` は CHECK 4値 `scheduled` / `confirmed` / `completed` / `cancelled`、`session_type` は CHECK なしのフリーテキスト（nullable）、`session_date timestamptz NOT NULL`、`duration_minutes integer NOT NULL DEFAULT 60`、`ticket_id` / `recurrence_group_id` は nullable
- **`sessions` に顧客用 RLS が無い**（トレーナー用4本のみ `auth.uid() = trainer_id`）。現状 Mobile から SELECT すると 0 行
- **カタログ L813 のポリシー案は誤り**（`SELECT id FROM clients` — `clients` に `id` カラムは無い）。正準は `clients.client_id = auth.uid()` で、`sessions.client_id` は `clients.client_id` への FK。よって **`USING (client_id = auth.uid())` が正解**（`weight_records` / `sleep_records` の顧客用ポリシーと同形）
- PERMISSIVE ポリシーは同一コマンドで OR 結合されるため、SELECT を1本足してもトレーナー側の可視範囲は不変
- `sessions` への GRANT は remote_schema で `authenticated` に付与済み（追加不要）
- Mobile に `features/sessions/` は未存在。`features/schedules/` は**トレーナー稼働時間**専用で別物（provider は現在 UI 未使用の死にコード）
- ステータスの日本語ラベル定数は Web にも無い（`SessionModal.tsx` に直書き 予定/確定/完了/キャンセル）
- リモートの未来セッションは **0件**（実機 QA にはオーナーが Web から登録する必要あり）。ローカル `Seed.sql` には5件あり（`client_id = 2222…2222` / sato@test.com）

## デザイン方針

`ui-ux-pro-max` の `--design-system` 出力（オレンジ/Barlow/LP構成）は**ランディングページ向けで既存アプリと不整合のため不採用**。既存の `AppColors` + Material 3 を維持し、適用可能な UX ルールのみ採用する:

- タッチターゲット **44x44 以上**、要素間 **8px 以上**
- 空状態は「メッセージ + アクション」（真っ白禁止）
- ローディング/エラーは既存流儀（lessons.md「エラー状態のUX原則」）: **カードのヘッダー構造を保持**し、**必ずリトライ導線**（`ref.invalidate`）
- アニメーションは 150–300ms
- リスト項目に `ValueKey`

カード様式は既存踏襲: `Container` + `colors.surface` + `BorderRadius.circular(16)`（リスト系）/ `24`（ホーム系）+ 薄い `boxShadow`、`padding: EdgeInsets.all(16)`。アイコンは `LucideIcons`。

## タスク分割

### レーンA: Supabase（RLS）

1. `supabase/migrations/20260906000000_sessions_client_select.sql`
   - 直近 migration（20260829000000 / 20260830000000）の書式踏襲: 79桁罫線ヘッダ + 日本語で背景/方針/出典 + `DROP POLICY IF EXISTS` → `CREATE POLICY` で冪等化
   - `CREATE POLICY "sessions_client_select" ON public.sessions FOR SELECT TO authenticated USING (client_id = auth.uid());`
   - 既存トレーナー用4本には**触れない**
2. `supabase/tests/sessions_rls_test.sql`（`payments_rls_test.sql` 雛形）
   - (a) 本人クライアントは自分のセッションのみ見える (b) 他人のクライアントには見えない (c) 担当トレーナーは従来どおり見える（回帰） (d) anon は 0 行 (e) 顧客は INSERT/UPDATE/DELETE できない

### レーンB: Mobile モデル・データ層

`lib/features/sessions/` を新設（雛形は `client_notes`）:

1. `models/session_model.dart` — `@JsonSerializable()` + `@JsonKey(name: 'snake_case')` + `@DateTimeConverter()` / `@NullableDateTimeConverter()`。`part 'session_model.g.dart'`
   - フィールド: id / trainerId / clientId / sessionDate / durationMinutes / status / sessionType / memo / ticketId / recurrenceGroupId / createdAt / updatedAt
   - `SessionStatus` の日本語ラベル + 表示色のマッピングを同ファイル内に定義（予定 / 確定 / 完了 / キャンセル）。**未知の値でも落ちない**フォールバック必須（CHECK 外の値が将来増えても表示が壊れないこと）
   - 派生ゲッター: `endTime`（sessionDate + durationMinutes）、`isUpcoming`、`isToday`
2. `data/session_repository.dart` — プレーン class + `final _supabase = SupabaseService.client;`
   - `getUpcomingSessions({required String clientId})`: `session_date >= now` かつ `status in ('scheduled','confirmed')`、`order('session_date')` 昇順
   - `getPastSessions({required String clientId})`: 上記の補集合（過去日時 or completed/cancelled）、`session_date` 降順、`limit(50)`
3. `providers/sessions_provider.dart` — `@riverpod` 関数型（`XxxRef` 引数型を使う既存流儀）
   - `sessionRepository` / `upcomingSessions` / `pastSessions` / `nextSession`（`upcomingSessions` の先頭を返す。null 可）
   - いずれも `currentClientIdProvider` を watch し、null なら空/None を返す

### レーンC: Mobile UI

1. `presentation/widgets/next_session_card.dart`
   - **データあり**: 日付「9月10日(水) 18:00」+ 残り日数バッジ（`今日` / `明日` / `あと3日`）+ 所要時間 + `session_type`（あれば）+ ステータスバッジ。**当日は強調表示**（primary 系のボーダー/背景）。タップで一覧画面へ
   - **予定なし**: 「予定されているセッションはありません」+ CTA「トレーナーに相談」（メッセージ画面へ定型文なしで遷移）。※カタログの「予約をリクエスト」CTA は課題1（予約リクエスト機能）が未実装のため、当面はメッセージ導線に読み替える
   - **ローディング**: カード構造を保持したプレースホルダ（`GoalCard(isLoading:true)` の流儀）
   - **エラー**: ヘッダー保持 + リトライボタン（`ref.invalidate(nextSessionProvider)`）
   - `@Preview` を4状態分（あり/当日/なし/エラー）。Riverpod 非依存の `_PreviewXxx` ヘルパー Widget パターン
2. `presentation/screens/sessions_screen.dart`
   - セグメント切替「今後 / 過去」（既存 `PeriodFilterChips` の流儀を踏襲）
   - 各行: 日時・所要時間・種別・ステータスバッジ・「変更を相談」ボタン（44x44 以上）。`ValueKey(session.id)`
   - 空 / ローディング / エラー（リトライ）は `client_notes_screen.dart` を踏襲
   - `@Preview` 2種以上（データあり / 空）
3. ホームへの挿入: `home_screen.dart` の **TrainerStatusCard 直後・DailySummaryCard の前**（L75–L81 の間）に `SizedBox(height: 16)` + `NextSessionCard`。ホームは既存どおりコールバックを子へ渡す方式

### レーンD: メッセージ画面への定型文遷移

「変更を相談」→ メッセージ画面に定型文を入れた状態で遷移する導線。**既存の `editingMessageContent` の注入パターンをそのまま踏襲**する:

1. `chat_input.dart`: `initialDraft`（String?）+ `onDraftConsumed`（VoidCallback?）を追加。`initState` / `didUpdateWidget` で `editingMessageContent` と同じ形で `_controller.text` にセットし、カーソルを末尾へ。セット後に `onDraftConsumed` を呼ぶ
2. `message_screen.dart`: `initialDraft` / `onDraftConsumed` を受け取り ChatInput へ透過
3. `main_screen.dart`: `String? _messageDraft` を持ち、`_navigateToMessagesWithDraft(String draft)`（= `_navigateToRecordsTab` と同じ流儀で `setState` により `_currentIndex = 1` と draft を同時セット）。消費後は `onDraftConsumed` で null に戻す（**再ビルドのたびに再注入されないこと**が要件）
4. `home_screen.dart`: `onConsultAboutSession(String draft)` コールバックを受け取り、`NextSessionCard` / `SessionsScreen` へ渡す。`SessionsScreen` は full-screen push されているため、**`Navigator.pop()` してからコールバックを呼ぶ**
5. 定型文の文面例: `「9月10日(水) 18:00 のセッションについて相談です。」`（日付は対象セッションから生成）

## 検証

1. `dart run build_runner build --delete-conflicting-outputs` → `flutter analyze`（lib/test エラー0）→ `flutter test`
2. `supabase db reset`（ローカル）→ `sessions_rls_test.sql` + 既存 RLS テスト5本の回帰
3. `supabase db push`（リモート適用）
4. `ios-simulator-qa`: ローカル Seed の sato@test.com でセッション5件が見えること／ホームカード・一覧・セグメント切替・「変更を相談」の定型文が入ること
5. `docs/tasks/IMPLEMENTATION_TASKS.md` 8.3 更新

## 既知のリスク

- **リモートに未来のセッションが0件**。実機 QA の前にオーナーが Web の /schedule から数件登録する必要がある
- Web 側は変更なし（トレーナーの見え方は不変）。RLS は SELECT を1本足すだけで、トレーナー用ポリシーの OR 結合により回帰の余地は小さいが、RLS テストの (c) で明示的に確認する
- `features/schedules/`（トレーナー稼働時間）と `features/sessions/`（予約）は名前が紛らわしい。**責務をコメントで明示**し、今回 schedules には触れない
