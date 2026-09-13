/**
 * アラート API（PATCH /api/alerts/[id]）の入力検証（純関数）。
 * API Route から分離してユニットテスト可能にしている。
 */

import type { AlertPatchAction } from '@/types/alert'

export const ALERT_PATCH_ACTIONS = ['acknowledge', 'reopen'] as const satisfies readonly AlertPatchAction[]

export type AlertPatchParseResult =
  | { ok: true; value: { action: AlertPatchAction } }
  | { ok: false; error: 'INVALID_BODY' | 'INVALID_ACTION' }

export function isAlertPatchAction(value: unknown): value is AlertPatchAction {
  return (
    typeof value === 'string' &&
    (ALERT_PATCH_ACTIONS as readonly string[]).includes(value)
  )
}

/**
 * PATCH /api/alerts/[id] のリクエストボディを検証・正規化する。
 * - acknowledge: open → acknowledged（「対応済み」）
 * - reopen: acknowledged → open（トーストの「元に戻す」）
 * 失敗時は { ok: false, error: 'CODE' }（API はそのまま 400 で返す）。
 */
export function parseAlertPatchBody(body: unknown): AlertPatchParseResult {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return { ok: false, error: 'INVALID_BODY' }
  }
  const action = (body as Record<string, unknown>).action
  if (!isAlertPatchAction(action)) {
    return { ok: false, error: 'INVALID_ACTION' }
  }
  return { ok: true, value: { action } }
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * alerts.id（uuid）の形か。
 * 形の違う id を DB に渡すと型エラー（22P02）で 500 になるので、存在しない id と同じ 404 に寄せるために使う。
 */
export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value)
}
