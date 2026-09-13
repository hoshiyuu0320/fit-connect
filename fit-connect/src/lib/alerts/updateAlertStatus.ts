/**
 * PATCH /api/alerts/[id] を呼ぶだけの関数（フック・状態は持たない）。
 * 楽観的更新と巻き戻しは呼び出し側（triageListState の reducer）が行う。
 */

import type { AlertPatchAction, AlertPatchResponse, AlertStatus } from '@/types/alert'

/** API の失敗（非 2xx・想定外のレスポンス）。status は HTTP ステータス（通信エラーは fetch の例外のまま） */
export class AlertUpdateError extends Error {
  readonly status: number

  constructor(status: number) {
    super(`アラートの更新に失敗しました（HTTP ${status}）`)
    this.name = 'AlertUpdateError'
    this.status = status
  }
}

/**
 * アラートを「対応済み」にする（acknowledge）/ 元に戻す（reopen）。
 * 条件に合わず更新されなかったときも、サーバーの今の status が返る（冪等）。
 */
export async function updateAlertStatus(
  alertId: string,
  action: AlertPatchAction
): Promise<{ id: string; status: AlertStatus }> {
  const res = await fetch(`/api/alerts/${encodeURIComponent(alertId)}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action }),
  })

  if (!res.ok) {
    throw new AlertUpdateError(res.status)
  }

  const json = (await res.json()) as Partial<AlertPatchResponse>
  if (!json.alert || typeof json.alert.id !== 'string' || typeof json.alert.status !== 'string') {
    throw new AlertUpdateError(res.status)
  }
  return { id: json.alert.id, status: json.alert.status }
}
