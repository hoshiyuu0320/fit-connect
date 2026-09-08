# ノート⇔セッション紐づけ導線の改善 — 実装計画

**作成**: 2026-09-06 / ブランチ: `feature/mobile-session-display`（PR #82 に含める）
**背景**: `client_notes.session_id` と「対象セッション」セレクトは実装済みだが、
トレーナー側の導線が「カルテタブ → 新規作成モーダル」の1経路しかなく、業務フロー
（セッションを完了にする → その場でカルテを書く）に沿っていないため紐づけ忘れが起きやすい。

**オーナー決定（2026-09-06）**: A-1 + B-2 + C-1 / 選択範囲は「完了・過去のみ」

## 決定事項

| 項目 | 決定 |
| --- | --- |
| A-1 | `SessionModal`（スケジュールのセッション詳細）に「カルテを書く」を追加し、対象セッション選択済みでノート作成モーダルを開く |
| B-2 | `session_number` は残すが、対象セッションを選んだら**自動で埋める**（手修正は可能なまま） |
| C-1 | カルテタブ起点では**直近の完了セッションを初期選択** |
| 選択範囲 | 完了・過去のセッションのみ（カルテは「やったことの記録」のため） |

## 仕様

### 選択肢の対象範囲（`getClientSessions`）

- `status = 'completed'`、**または** 過去日時（`session_date < now()`）かつ `status <> 'cancelled'`
  - 「完了にし忘れたまま過去になった予定」も実務では対象になるため含める
  - キャンセルは常に除外（カルテを書く対象ではない）
- 新しい順。表示ラベルは `yyyy/MM/dd HH:mm ・ 種別`

### session_number の自動補完（B-2）

- 「何回目か」= そのクライアントの**上記対象セッションを古い順に数えた順番**
- 対象セッションを選択したときに `session_number` へ自動で入れる
- **トレーナーが手で書き換えたあとは上書きしない**（自動補完は「ユーザーが触っていない」場合のみ）
- 「紐づけない」に戻した場合は自動補完した値をクリアする（手入力値は残す）

### 重複紐づけの可視化

- 既に共有/非共有を問わずノートが紐づいているセッションは、選択肢のラベルに `（カルテ作成済み）`を付ける
- 選択自体は禁止しない（DB 上も複数可）。判断はトレーナーに委ねる

### A-1 の導線

- `SessionModal` に「カルテを書く」ボタンを追加
  - **表示条件**: 既存セッションの編集時（新規作成中は出さない）かつ、上記「対象範囲」に合致するセッションのみ
  - 押下で `SessionModal` を閉じ、`CalendarView`（親）が `CreateNoteModal` を
    **そのセッションを選択済み**の状態で開く。カレンダーから離れない
  - 保存後はカレンダーに戻るだけでよい（カルテ一覧は同画面に無いため再取得不要）
- `CreateNoteModal` に `initialSessionId` を追加（カルテタブ起点では C-1 の既定値、SessionModal 起点では該当セッション）

## 変更対象

- `src/lib/supabase/getClientSessions.ts` — 対象範囲の絞り込み + 紐づき済みノート有無 + 回数（古い順の連番）
- `src/app/(user_console)/clients/[client_id]/_components/CreateNoteModal.tsx` — `initialSessionId`、session_number 自動補完、ラベルの `（カルテ作成済み）`
- `src/app/(user_console)/clients/[client_id]/_components/EditNoteModal.tsx` — 同じ自動補完・ラベル規則を踏襲（既存の紐づけを壊さない）
- `src/app/(user_console)/clients/[client_id]/_components/NotesTab.tsx` — C-1 の初期選択を渡す
- `src/components/schedule/SessionModal.tsx` — 「カルテを書く」ボタン
- `src/components/schedule/CalendarView.tsx` — `CreateNoteModal` の配線

Mobile は変更なし。

## 検証

- `npx tsc --noEmit` / `vitest run` / `lint` / `next build`
- 純粋ロジック（対象範囲の判定・回数の算出・自動補完の上書き規則）は vitest でテストする
