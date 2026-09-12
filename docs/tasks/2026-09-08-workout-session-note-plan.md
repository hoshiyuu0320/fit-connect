# ワークアウト実施画面 → カルテ導線 / セッション完了の整合 — 実装計画

**作成**: 2026-09-08 / ブランチ: `feature/mobile-session-display`（PR #82 に含める）
**オーナー決定（2026-09-08）**: A + B / トレーナーノートをカルテ本文の初期値に流し込む

## 背景（実測）

- クライアント詳細の「セッション中」タブ（`SessionTab`）は **`workout_assignments` の実施画面**で、`sessions` とは別系統
- 「完了として保存」（`SessionSummaryModal`）は `workout_assignments` の status / trainer_note / client_feedback を更新するだけで、**`sessions` には触れない** → ワークアウトを終えてもスケジュール上は「予定」のまま
- `workout_assignments.session_id` はスケジュールからセッションとプランを同時作成したときだけ入る（本番: 38件中15件、完了9件中3件）
- セッション完了時のチケット消化は `SessionModal` の中にクライアント側で直書き（`updateTicket(remaining - 1)`）

## 決定事項

### B. セッション完了とチケット消化を1箇所に集約

- `src/lib/supabase/completeSession.ts` を新設: `completeSession(sessionId)`
  1. セッションを取得（status / ticket_id）。**既に completed なら何もしない**（二重消化防止）
  2. `status = 'completed'` に更新
  3. `ticket_id` があり `remaining_sessions > 0` なら 1 減らす
- チケットの「1回消化」は `consumeTicketSession(ticketId)` として切り出し、`SessionModal` の既存ブロックもこれを呼ぶ形に置き換える（減算ロジックの二重実装を残さない。SessionModal のフロー自体は変えない）
- 既存の RLS（トレーナーは自分の sessions / tickets のみ更新可）に委ねる。既存 `updateSession` / `updateTicket` と同じクライアント側 supabase の流儀

### A. 「完了として保存」→ カルテ作成

- `SessionTab.handleSaveSummary` の成功後:
  1. `summaryAssignment.session_id` があれば `completeSession()` を呼ぶ（失敗は console.error して続行。カルテ導線は止めない）
  2. カルテの対象セッションを決める:
     - `session_id` があればそれ
     - 無ければ **同日（`assigned_date`）のそのクライアントのセッションが1件だけならそれ**、それ以外は未選択
     - 判定は純粋関数 `pickSessionForAssignment(options, assignment)` として `noteLinkOptions.ts` に置き、テストする
  3. `CreateNoteModal` を開く: `initialSessionId` = 上記、**`initialContent` = サマリーで入力したトレーナーノート**
- 選択肢は `useClientSessionOptions(clientId)` を `SessionTab` で使い、完了更新のあとに `refetch()` してから開く（完了したばかりのセッションが選択肢に入るように）
- `CreateNoteModal` に `initialContent?: string` を追加。**本文が空のときだけ**流し込む（既に書きかけがあれば上書きしない。対象セッションの「触っていないときだけシード」と同じ規律）
- `SessionTimerBar` の完了バナー（「セッション完了 … 終了済み」）に副次アクション **「カルテを書く」** を追加。サマリーを閉じたあとでも同じモーダルを開ける（`onWriteNote` を props で受ける。未指定なら出さない）

### 触らないもの

- `workout_assignments.session_id` が無い課題からセッションを新規作成する導線（スコープ外）
- Mobile

## 変更対象（Web のみ）

- `src/lib/supabase/completeSession.ts`（新規）/ `consumeTicketSession.ts`（新規、または completeSession 内に同居）
- `src/components/schedule/SessionModal.tsx`（チケット消化を共通関数へ）
- `src/lib/sessions/noteLinkOptions.ts`（+test）: `pickSessionForAssignment`
- `src/components/notes/CreateNoteModal.tsx`: `initialContent`
- `src/app/(user_console)/clients/[client_id]/_components/SessionTab.tsx` / `SessionTimerBar.tsx`

## 検証

- tsc / vitest / lint / next build
