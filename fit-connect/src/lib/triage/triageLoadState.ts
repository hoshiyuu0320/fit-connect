/**
 * 「今日の対応」の取得の状態（純関数）。
 *
 * アラート（9.1）と未返信（9.2）は別々に取り、どちらかが失敗しても取れた分は出す（計画書 Web UI > PR2）。
 * 部分ごとの状態と、セクション全体の表示（スケルトン / 全体のエラー / 一覧）をここで決める。
 * コンポーネントのテスト基盤が無いので、分岐を切り出して vitest で固定する。
 *
 * - 一度表示できた部分は、取り直し（タブ復帰・操作の後）の一時的な失敗で failed にしない
 *   （前のデータを出し続ける。PR1 のアラートの扱いと同じ）
 * - 両方とも失敗したときだけ、セクション全体を「読み込めませんでした」にする
 * - サーバーからも import されうるので、React や 'use client' に依存させない
 */

/** loading: まだ一度も結果が無い / ready: 表示できるデータがある / failed: 取得に失敗し、出せるデータが無い */
export type TriagePartStatus = 'loading' | 'ready' | 'failed'

/** loading: スケルトン / error: 全体のエラーと再読み込み / ready: 一覧（失敗した部分はセクション内でエラーを出す） */
export type TriageSectionPhase = 'loading' | 'error' | 'ready'

/** 取得1回の結果を反映した、部分の状態 */
export function nextPartStatus(prev: TriagePartStatus, succeeded: boolean): TriagePartStatus {
  if (succeeded) return 'ready'
  return prev === 'ready' ? 'ready' : 'failed'
}

/** セクション全体の表示 */
export function triageSectionPhase(
  alerts: TriagePartStatus,
  unreplied: TriagePartStatus
): TriageSectionPhase {
  if (alerts === 'loading' || unreplied === 'loading') return 'loading'
  if (alerts === 'failed' && unreplied === 'failed') return 'error'
  return 'ready'
}

/** 一覧が一部だけか（どちらかの部分を出せていない）。0件の文言を言い切らないために使う */
export function isTriageIncomplete(alerts: TriagePartStatus, unreplied: TriagePartStatus): boolean {
  return alerts === 'failed' || unreplied === 'failed'
}

// ---------------------------------------------------------------------------
// サイドバー「ダッシュボード」のバッジ（triageBadgeStore）
// ---------------------------------------------------------------------------

/** バッジの数え直し1回の結果（getTriageBadgeCount） */
export type TriageBadgeCountResult = {
  /** 取れた分（open のアラートがある顧客と未返信の顧客の和集合）の人数 */
  count: number
  /** アラートと未返信の両方を取れたか。false なら count は実際の人数の下限（取れた片方だけの人数） */
  complete: boolean
}

/** バッジに出している値 */
export type TriageBadgeCountState = {
  count: number
  /** 両方を取れた数え直しに基づく値か（表示直後・ログアウト後は false） */
  complete: boolean
}

/**
 * 数え直しの結果を反映したバッジの値。
 * - 両方を取れた: その人数
 * - 一部だけ取れて、前に両方を取れた値がある: 前の値を残す（一時的な失敗で数を揺らさない）。
 *   ただし取れた分の人数は実際の人数の下限なので、それより少なくは出さない
 * - 一部だけ取れて、前に両方を取れた値が無い（表示直後・ログイン直後）: 取れた分の人数を出す。
 *   0 のまま残すと、open のアラートがある顧客までバッジから消えてしまうため（見出しは取れた分の人数を出す）
 * - 両方とも失敗したときは呼ばない（getTriageBadgeCount が throw し、ストアは前の値のまま残す）
 */
export function nextTriageBadgeCount(
  prev: TriageBadgeCountState,
  result: TriageBadgeCountResult
): TriageBadgeCountState {
  if (result.complete) return { count: result.count, complete: true }
  if (prev.complete) return { count: Math.max(prev.count, result.count), complete: true }
  return { count: result.count, complete: false }
}
