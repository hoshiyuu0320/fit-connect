# セッション⇔ノート紐づけ — 実装計画（確定版）

**作成**: 2026-09-06 / ブランチ: `feature/mobile-session-display`（PR #82 に含める。SessionsScreen に依存するため）
**要望**: 過去のセッションをタップしたら、紐づくトレーナーの共有ノートへ遷移。ノートの有無をセルで判別できるようにする

## 実測した前提

- `client_notes` に `session_id` は**無い**。あるのは `session_number`（トレーナーが手入力する整数、nullable）
- 本番データ: ノート1件 / `session_number` 入力済み **0件** / 完了セッション 0件 → 既存データからの推測紐づけは不可能
- `client_notes` の顧客向け RLS は `clients_select_shared_notes`: `(is_shared = true) AND (client_id = auth.uid())`
  → **顧客のクエリには共有ノートしか返らない**（未共有ノートの存在も漏れない）
- Mobile には `ClientNoteDetailScreen(note:, trainerName:)` が既存。遷移先は流用できる
- Web の `getSessions(startDate, endDate)` は期間指定でクライアント別ではない → ノート編集用に新クエリが要る

## 設計判断

1. **`client_notes.session_id` を新設**（`REFERENCES sessions(id) ON DELETE SET NULL`）。`session_number` は表示用の通し番号として現状維持（撤去はしない）
2. **別クライアント/別トレーナーのセッションに紐づけられないようトリガーで整合性を担保**。
   複合 FK も CHECK も使えないため（サブクエリ不可）、`BEFORE INSERT OR UPDATE` トリガーで
   `sessions.client_id = NEW.client_id AND sessions.trainer_id = NEW.trainer_id` を検証する。
   API 層の所有検証（`guards.ts`）と二重で守る
3. **ノートの有無は「共有済みノートがあるか」で判定**する。RLS により顧客のクエリは自動的にそうなるが、
   実装でも明示する。「未共有ノートの存在を顧客に匂わせない」ことが要件
4. **UI（Mobile 一覧の行）**: 既存 `SessionMetaChip` の流儀で `📄 ノート` チップ + 右端に `chevronRight`。
   ノートが無い行は**タップ不可のまま**（空振りタップを作らない）
5. 紐づけは「今後」タブにも効かせる（事前の注意事項をノートで共有するケースがあるため）。要望の主眼は過去だが、
   出し分けを増やす理由がない

## タスク分割

### レーンA: Supabase
1. `supabase/migrations/20260906000100_add_session_id_to_client_notes.sql`
   - `ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES public.sessions(id) ON DELETE SET NULL`
   - `CREATE INDEX IF NOT EXISTS idx_client_notes_session_id ON public.client_notes(session_id)`
   - 整合性トリガー（上記 判断2）。`session_id IS NULL` なら素通り
   - `COMMENT ON COLUMN` で `session_number`（手入力の通し番号）との役割の違いを明記
   - RLS は不変（既存 `clients_select_shared_notes` がそのまま効く）
2. `supabase/tests/client_notes_session_link_test.sql`
   - (a) 自分の担当クライアントのセッションには紐づけられる
   - (b) 他人のクライアントのセッションを指定すると**トリガーで拒否**される
   - (c) client_id と session.client_id が食い違う場合も拒否
   - (d) 顧客からは共有ノートのみ、かつ session_id 付きで読める
   - (e) セッション削除で `session_id` が NULL になる（ノート自体は残る）

### レーンB: Web（fit-connect）
1. `src/types/client.ts`: `ClientNote.session_id`、`Create/UpdateClientNoteParams.sessionId`
2. `src/lib/supabase/getClientSessions.ts` 新設: 指定クライアントのセッション一覧（新しい順、表示用に日時と種別）
3. `CreateNoteModal` / `EditNoteModal` に「対象セッション」セレクト（**任意・未選択可**）。既存の入力欄の流儀に合わせる
4. API Routes（`/api/client-notes` POST・`/api/client-notes/[id]` PUT）で `sessionId` を受け取り、
   **`guards.ts` の所有検証**を通してから保存（未検証の値を信じない。フェーズ5.5 の方針を踏襲）
5. `NotesTab`: 紐づくセッションがあればその日時を表示

### レーンC: Mobile
1. `ClientNote` モデルに `sessionId` 追加
2. セッション一覧の取得時に**共有ノートを併せて取得**（PostgREST の embed で `client_notes` を引く。
   RLS により共有ノートのみ返る）。`SessionModel` に紐づくノートを持たせるか、画面側で Map を作るかは実装判断
3. 一覧の行: `📄 ノート` チップ + `chevronRight`、タップで `ClientNoteDetailScreen` へ。ノート無しの行はタップ不可
4. `@Preview` を「ノートあり / なし」で更新
5. ウィジェットテスト: ノート有無での表示差、タップ遷移、未共有ノートが出ないこと

## 検証

1. Mobile: `build_runner` → `flutter analyze`（エラー0）→ `flutter test`
2. Web: `tsc --noEmit` / `vitest run` / `lint` / `next build`
3. `supabase db reset` + RLS/トリガーテスト（既存6本の回帰含む）
4. リモート適用（`supabase db push`）はマネージャーが実施
