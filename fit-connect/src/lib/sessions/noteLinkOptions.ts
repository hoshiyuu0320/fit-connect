/**
 * カルテ（client_notes）⇔ セッション（sessions）紐づけの純粋ロジック
 *
 * - Supabase クライアントに依存しない（vitest で単体テストするため）
 * - 対象範囲の判定 / 「対象セッション」セレクトの選択肢と選択状態の出どころを一元管理する
 *   （CreateNoteModal / EditNoteModal / SessionModal 起点のどこから使っても同じ挙動になること）
 */

import { format } from 'date-fns'

export type SessionStatus = 'scheduled' | 'confirmed' | 'completed' | 'cancelled'

/** sessions から引く素の行（このモジュールが必要とする最小の形） */
export type SessionRow = {
  id: string
  session_date: string
  session_type: string | null
  status: SessionStatus
}

/** カルテの「対象セッション」セレクト用のセッション情報 */
export type ClientSessionOption = SessionRow & {
  /** 既にカルテが紐づいているか（共有/非共有を問わない） */
  has_note: boolean
}

/**
 * カルテの対象にできるセッションか
 *
 * - `cancelled` は常に対象外（カルテを書く対象ではない）
 * - `completed` は日時を問わず対象（カルテは「やったことの記録」のため）
 * - それ以外（scheduled / confirmed）は過去日時のみ対象
 *   （完了にし忘れたまま過去になった予定も実務では対象になるため）
 */
export const isNoteLinkableSession = (session: SessionRow, now: Date = new Date()): boolean => {
  if (session.status === 'cancelled') return false
  if (session.status === 'completed') return true

  const at = new Date(session.session_date).getTime()
  if (Number.isNaN(at)) return false
  return at < now.getTime()
}

/** 新しい順（session_date 降順、同時刻は id 降順で安定させる） */
const compareNewestFirst = (a: SessionRow, b: SessionRow): number => {
  const diff = new Date(b.session_date).getTime() - new Date(a.session_date).getTime()
  if (diff !== 0) return diff
  return a.id < b.id ? 1 : a.id > b.id ? -1 : 0
}

/**
 * 対象セッションだけを残し、新しい順で返す
 *
 * 入力の並び順には依存しない。
 *
 * @param rows 対象クライアントのセッション行（順不同）
 * @param notedSessionIds 既にカルテが紐づいている session_id
 * @param now 「過去」の判定に使う基準時刻
 */
export const buildNoteLinkOptions = (
  rows: SessionRow[],
  notedSessionIds: Iterable<string> = [],
  now: Date = new Date(),
): ClientSessionOption[] => {
  const noted = new Set(notedSessionIds)

  return rows
    .filter((row) => isNoteLinkableSession(row, now))
    .sort(compareNewestFirst)
    .map((row) => ({
      ...row,
      has_note: noted.has(row.id),
    }))
}

/**
 * ワークアウト課題（workout_assignments）からカルテを書くときの対象セッションを決める
 *
 * - 課題に `session_id` があればそれ（スケジュールと同時作成された課題）
 * - 無ければ、選択肢のうち session_date のローカル日付が `assigned_date`（yyyy-MM-dd）と
 *   一致するセッションが **ちょうど1件** ならその id
 * - 一致が 0 件 / 2 件以上なら null（推測で紐づけず、トレーナーに選んでもらう）
 *
 * `session_id` が選択肢に無い場合の扱い（読み込み待ち／取得失敗）は呼び出し側の
 * CreateNoteModal の seed 規律に委ねる。
 */
export const pickSessionForAssignment = (
  options: readonly ClientSessionOption[],
  assignment: { session_id: string | null; assigned_date: string },
): string | null => {
  if (assignment.session_id) return assignment.session_id

  const sameDay = options.filter((option) => {
    const at = new Date(option.session_date)
    if (Number.isNaN(at.getTime())) return false
    return format(at, 'yyyy-MM-dd') === assignment.assigned_date
  })

  return sameDay.length === 1 ? sameDay[0].id : null
}

/** セレクトの表示ラベル（`yyyy/MM/dd HH:mm ・ 種別（カルテ作成済み）`） */
export const formatSessionOptionLabel = (option: ClientSessionOption): string => {
  const at = format(new Date(option.session_date), 'yyyy/MM/dd HH:mm')
  const type = option.session_type ? ` ・ ${option.session_type}` : ''
  const noted = option.has_note ? '（カルテ作成済み）' : ''
  return `${at}${type}${noted}`
}

// ================================================
// 「対象セッション」セレクトの状態
// ================================================

/**
 * 対象セッションセレクトの現在値の出どころ
 * - `empty`  : まだ選ばれていない（ユーザーも触っていない）
 * - `auto`   : モーダルを開いたときの初期選択で入った
 * - `manual` : ユーザーがこの画面で選び直した（「紐づけない」に戻した場合も含む）
 */
export type SessionSelectionSource = 'empty' | 'auto' | 'manual'

/** 対象セッションセレクトの状態（value は select の値。'' は「紐づけない」） */
export type SessionSelectionField = {
  value: string
  source: SessionSelectionSource
}

export const EMPTY_SESSION_SELECTION_FIELD: SessionSelectionField = { value: '', source: 'empty' }

const findOption = (
  options: readonly ClientSessionOption[],
  sessionId: string,
): ClientSessionOption | null =>
  sessionId ? options.find((option) => option.id === sessionId) ?? null : null

/** ユーザーが対象セッションを選び直したときの次の状態（「紐づけない」に戻した場合も `manual`） */
export const selectNoteLinkSession = (sessionId: string): SessionSelectionField => ({
  value: sessionId,
  source: 'manual',
})

/**
 * モーダルを開いたときの初期選択（C-1 の直近セッション / A-1 のそのセッション）を反映する
 *
 * トレーナーが既に対象セッションを触っていれば何もしない。
 * モーダルはアンマウントされないため、キャンセルして開き直したときに
 * 明示的な選択が既定値へ巻き戻らないようにする。
 */
export const seedNoteLinkSession = (
  state: SessionSelectionField,
  initialSessionId: string | null | undefined,
  options: readonly ClientSessionOption[],
): SessionSelectionField => {
  if (state.source === 'manual') return state

  const selected = findOption(options, initialSessionId ?? '')
  return selected ? { value: selected.id, source: 'auto' } : EMPTY_SESSION_SELECTION_FIELD
}

/** 既存カルテ（編集）の保存済み値から初期状態を作る */
export const initialNoteLinkSelection = (note: {
  session_id?: string | null
}): SessionSelectionField =>
  // 保存済みの紐づけはトレーナーが決めたものなので、初期選択で上書きさせない
  note.session_id ? { value: note.session_id, source: 'manual' } : EMPTY_SESSION_SELECTION_FIELD
