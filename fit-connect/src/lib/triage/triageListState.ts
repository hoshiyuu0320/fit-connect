/**
 * 「今日の対応」の一覧の状態遷移（reducer。純関数）。
 *
 * コンポーネントのテスト基盤が無いので、画面の状態遷移をここに切り出して vitest で固定する。
 * - 対応済み: 押したら先に行から外す（楽観的更新）→ API が失敗したら戻す
 * - 元に戻す（トースト）: 先に行へ戻す → API が失敗したら再び外す
 * - 取り直し（loaded）: サーバーの open の一覧に置き換える。応答待ちの操作は上書きしない
 * - 展開: 行の disclosure と「すべて表示（N件）」
 *
 * 呼び出し側（TriageSection）の約束:
 * - 同じアラートへの API は、前の呼び出しが終わってから送る
 *   （「元に戻す」の reopen が acknowledge より先に届くと、サーバーは acknowledged のまま残る）
 * - 取り直しの結果は、後から始めた取得の分だけを loaded で渡す（古い応答で新しい状態を戻さない）
 *
 * サーバーからも import されうるので、React や 'use client' に依存させない。
 */

import {
  buildTriageRows,
  type TriageRowModel,
  type TriageUnrepliedInput,
} from '@/lib/triage/buildTriageRows'
import type { ClientAlert } from '@/types/alert'

/** 最初に出す行数（残りは「すべて表示（N件）」でその場に展開する） */
export const TRIAGE_INITIAL_LIMIT = 5

/** 対応済みにして一覧から外しているアラート */
export type HiddenAlert = {
  alert: ClientAlert
  /** pending: acknowledge の API 応答待ち / done: 成功済み（「元に戻す」で出し直せるようデータを持っておく） */
  phase: 'pending' | 'done'
}

export type TriageListState = {
  /** 取得した open のアラート（元に戻している途中のものを含む） */
  alerts: ClientAlert[]
  /** 対応済みにして外しているもの（alert id → 状態） */
  hidden: Record<string, HiddenAlert>
  /** 元に戻している途中（reopen の API 応答待ち）のもの（alert id → アラート） */
  restoring: Record<string, ClientAlert>
  /** 詳細を開いている行（顧客 ID） */
  expandedClientIds: string[]
  /** 「すべて表示」を押したか */
  showAll: boolean
}

export type TriageListAction =
  /** 取得（取り直し）の結果 */
  | { type: 'loaded'; alerts: ClientAlert[] }
  /** 「対応済み」を押した（API を呼ぶ前に dispatch する） */
  | { type: 'acknowledge'; alertId: string }
  | { type: 'acknowledgeSucceeded'; alertId: string }
  | { type: 'acknowledgeFailed'; alertId: string }
  /** トーストの「元に戻す」を押した（API を呼ぶ前に dispatch する） */
  | { type: 'undo'; alertId: string }
  | { type: 'undoSucceeded'; alertId: string }
  | { type: 'undoFailed'; alertId: string }
  | { type: 'toggleExpanded'; clientId: string }
  | { type: 'toggleShowAll' }

export function createTriageListState(alerts: ClientAlert[] = []): TriageListState {
  return { alerts, hidden: {}, restoring: {}, expandedClientIds: [], showAll: false }
}

function has(record: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(record, key)
}

function without<T>(record: Record<string, T>, key: string): Record<string, T> {
  if (!has(record, key)) return record
  const next = { ...record }
  delete next[key]
  return next
}

export function triageListReducer(
  state: TriageListState,
  action: TriageListAction
): TriageListState {
  switch (action.type) {
    case 'loaded': {
      const ids = new Set(action.alerts.map((alert) => alert.id))
      let hidden = state.hidden
      for (const [id, entry] of Object.entries(state.hidden)) {
        // 成功済みなのに open の一覧に居る = サーバーで open に戻った（翌朝の昇格による再浮上など）。
        // 隠し続けると見落とすので出す。応答待ち（pending）はサーバーへの反映前の一覧かもしれないので外したまま
        if (entry.phase === 'done' && ids.has(id)) {
          hidden = without(hidden, id)
        }
      }
      // 元に戻している途中のものは、reopen の反映前の一覧に居なくても出し続ける
      const stillRestoring = Object.values(state.restoring).filter((alert) => !ids.has(alert.id))
      return { ...state, alerts: [...action.alerts, ...stillRestoring], hidden }
    }

    case 'acknowledge': {
      const alert = state.alerts.find((a) => a.id === action.alertId)
      if (!alert || has(state.hidden, action.alertId)) return state
      return {
        ...state,
        hidden: { ...state.hidden, [action.alertId]: { alert, phase: 'pending' } },
        restoring: without(state.restoring, action.alertId),
      }
    }

    case 'acknowledgeSucceeded': {
      const entry = state.hidden[action.alertId]
      // 応答待ちの間に「元に戻す」が押されていたら外し直さない（このあと reopen が送られる）
      if (!has(state.hidden, action.alertId) || entry.phase !== 'pending') return state
      return {
        ...state,
        hidden: { ...state.hidden, [action.alertId]: { ...entry, phase: 'done' } },
      }
    }

    case 'acknowledgeFailed': {
      // 巻き戻し: 行に戻す
      if (!has(state.hidden, action.alertId) || state.hidden[action.alertId].phase !== 'pending') {
        return state
      }
      return { ...state, hidden: without(state.hidden, action.alertId) }
    }

    case 'undo': {
      if (!has(state.hidden, action.alertId)) return state
      const { alert } = state.hidden[action.alertId]
      // 取り直しで一覧から消えていても（サーバーでは acknowledged）、持っておいたデータで行に戻す
      const inList = state.alerts.some((a) => a.id === action.alertId)
      return {
        ...state,
        alerts: inList ? state.alerts : [...state.alerts, alert],
        hidden: without(state.hidden, action.alertId),
        restoring: { ...state.restoring, [action.alertId]: alert },
      }
    }

    case 'undoSucceeded': {
      if (!has(state.restoring, action.alertId)) return state
      return { ...state, restoring: without(state.restoring, action.alertId) }
    }

    case 'undoFailed': {
      if (!has(state.restoring, action.alertId)) return state
      // サーバーは acknowledged のまま → 再び外す。
      // 実はサーバーで open だった場合も、次の取り直しで一覧に居れば loaded が出し直す
      const alert = state.restoring[action.alertId]
      return {
        ...state,
        hidden: { ...state.hidden, [action.alertId]: { alert, phase: 'done' } },
        restoring: without(state.restoring, action.alertId),
      }
    }

    case 'toggleExpanded': {
      const expanded = state.expandedClientIds.includes(action.clientId)
      return {
        ...state,
        expandedClientIds: expanded
          ? state.expandedClientIds.filter((id) => id !== action.clientId)
          : [...state.expandedClientIds, action.clientId],
      }
    }

    case 'toggleShowAll':
      return { ...state, showAll: !state.showAll }

    default:
      return state
  }
}

// ---------------------------------------------------------------------------
// セレクタ
// ---------------------------------------------------------------------------

/** 一覧に出すアラート（対応済みにして外しているものを除く） */
export function selectVisibleAlerts(state: TriageListState): ClientAlert[] {
  return state.alerts.filter((alert) => !has(state.hidden, alert.id))
}

export type TriageListView = {
  /** 並び順どおりのすべての行 */
  rows: TriageRowModel[]
  /** いま出す行（「すべて表示」前は上位 limit 件） */
  displayedRows: TriageRowModel[]
  /** 行（顧客）の数。見出しの件数と「すべて表示（N件）」の N */
  totalCount: number
  /** 「すべて表示」ボタンを出すか */
  hasMore: boolean
  /** サイドバーのバッジに出す数（見出しの件数と同じ定義） */
  badgeCount: number
}

/**
 * 一覧の表示内容。
 * unreplied（未返信の顧客と表示時点）を渡すと、未返信の顧客を合流させてスコア順に並べる。
 * 未返信は操作（対応済み・元に戻す）の対象にしないので reducer の状態には持たず、取得したものをここで渡す
 * （オーナー決定4: 未返信の消し込みは作らない）
 */
export function selectTriageListView(
  state: TriageListState,
  limit: number = TRIAGE_INITIAL_LIMIT,
  unreplied?: TriageUnrepliedInput
): TriageListView {
  const { rows, badgeClientIds } = buildTriageRows(selectVisibleAlerts(state), unreplied)
  return {
    rows,
    displayedRows: state.showAll ? rows : rows.slice(0, limit),
    totalCount: rows.length,
    hasMore: rows.length > limit,
    badgeCount: badgeClientIds.size,
  }
}

export function isClientExpanded(state: TriageListState, clientId: string): boolean {
  return state.expandedClientIds.includes(clientId)
}
