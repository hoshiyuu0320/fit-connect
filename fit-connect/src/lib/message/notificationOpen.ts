// メッセージ通知（顧客 → トレーナーの Web Push）のクリックで、メッセージ画面がどの顧客の会話を開くかを決める（純関数）。
// 設計書: docs/superpowers/specs/2026-10-12-message-notification-open-chat-design.md §5
// 通知の data.url は /message?clientId=<顧客の client_id>。public/sw.js は /message のタブがあれば移動させず、
// 前面に出して notification-clicked（url 付き）を送るだけなので、そのタブがここで決めた顧客を選び直す。
// 書きかけがあるときは消さないよう切り替えず、案内（NotificationHoldNotice）を出す。
// import は依存の無い isUuid だけにする。

import { isUuid } from '@/lib/alerts/validation'

/** 相対パスを解析するときの基準。解析した結果の origin がこれと違う（絶対 URL・//host）なら受けない */
const RELATIVE_BASE = 'https://fit-connect.invalid'

const MESSAGE_PATHNAME = '/message'

/**
 * 通知のクリック先（自分のオリジンの相対パス）から、開く顧客の client_id を取り出す。
 * パス名が厳密に /message で clientId クエリが UUID の形のときだけ、小文字にそろえて返す（他のクエリは無視する）。
 * 絶対 URL・//host・別のパス・clientId が無い / UUID でない・空文字・null・解析できない値は null
 */
export function clientIdFromNotificationUrl(url: string | null): string | null {
  if (!url) return null
  let parsed: URL
  try {
    parsed = new URL(url, RELATIVE_BASE)
  } catch {
    return null
  }
  if (parsed.origin !== RELATIVE_BASE || parsed.pathname !== MESSAGE_PATHNAME) return null
  const clientId = parsed.searchParams.get('clientId')
  return isUuid(clientId) ? clientId.toLowerCase() : null
}

/** 入力欄まわりの状態（書きかけの判定に使う） */
export type MessageDraftState = {
  /** 入力欄の文字 */
  input: string
  /** 添付する画像の枚数 */
  imageCount: number
  /** 返信先を選んでいる */
  hasReply: boolean
  /** 記録の引用チップがある */
  hasRecordQuote: boolean
  /** 送信済みのメッセージを編集中 */
  isEditing: boolean
  /** 送信中 */
  isSending: boolean
}

/**
 * 書きかけがあるか（あれば通知のクリックで会話を切り替えない）。
 * 空白だけの入力は書きかけにしない（送信でも空白だけの入力は送らない）
 */
export function hasMessageDraft(state: MessageDraftState): boolean {
  return (
    state.input.trim() !== '' ||
    state.imageCount > 0 ||
    state.hasReply ||
    state.hasRecordQuote ||
    state.isEditing ||
    state.isSending
  )
}

export type NotificationOpenDecision =
  | { action: 'none'; reason: 'no_target' | 'already_selected' | 'unknown_client' }
  /** その顧客に切り替える（サイドバーのクリックと同じ） */
  | { action: 'select'; clientId: string }
  /** 書きかけがあるので切り替えず、案内を出す */
  | { action: 'hold'; clientId: string }

/**
 * 通知のクリックでどうするか。判定の順:
 * 1. 開く顧客が無い（url が /message?clientId=<uuid> でない） → none / no_target
 * 2. その顧客を表示中 → none / already_selected（書きかけがあっても何もしない）
 * 3. 顧客一覧に無い → none / unknown_client（書きかけがあっても何もしない）
 * 4. 書きかけがある → hold
 * 5. それ以外 → select
 */
export function decideNotificationOpen(args: {
  targetClientId: string | null
  selectedClientId: string | null
  isKnownClient: boolean
  hasDraft: boolean
}): NotificationOpenDecision {
  const { targetClientId, selectedClientId, isKnownClient, hasDraft } = args
  if (targetClientId === null) return { action: 'none', reason: 'no_target' }
  if (targetClientId === selectedClientId) return { action: 'none', reason: 'already_selected' }
  if (!isKnownClient) return { action: 'none', reason: 'unknown_client' }
  if (hasDraft) return { action: 'hold', clientId: targetClientId }
  return { action: 'select', clientId: targetClientId }
}
