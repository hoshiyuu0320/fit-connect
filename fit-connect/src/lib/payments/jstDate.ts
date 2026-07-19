/**
 * JST（UTC+9、DSTなし）基準の日付ユーティリティ（純関数）。
 * 支払記録の「今月」判定・支払期日（due_date）の算出に使用する。
 */

const JST_OFFSET_MS = 9 * 60 * 60 * 1000

/**
 * 指定時刻が属する JST 暦月の範囲 [開始, 終了) を UTC の ISO 文字列で返す。
 * 例: now = 2026-07-12T10:00:00Z（JST 19:00）
 *     → start 2026-06-30T15:00:00.000Z（JST 7/1 00:00）
 *     → end   2026-07-31T15:00:00.000Z（JST 8/1 00:00）
 */
export function getJstMonthRange(now: Date): { startIso: string; endIso: string } {
  const jst = new Date(now.getTime() + JST_OFFSET_MS)
  const year = jst.getUTCFullYear()
  const month = jst.getUTCMonth()
  const startMs = Date.UTC(year, month, 1) - JST_OFFSET_MS
  const endMs = Date.UTC(year, month + 1, 1) - JST_OFFSET_MS
  return {
    startIso: new Date(startMs).toISOString(),
    endIso: new Date(endMs).toISOString(),
  }
}

/** JST での日付部分（YYYY-MM-DD）を返す */
export function toJstDateString(date: Date): string {
  return new Date(date.getTime() + JST_OFFSET_MS).toISOString().slice(0, 10)
}

/**
 * 日時文字列から日付部分（YYYY-MM-DD）を取り出す。
 * - 'YYYY-MM-DD...' 形式は先頭10文字をそのまま採用
 * - それ以外は Date として解釈し JST の日付に変換
 * - 解釈不能なら null
 */
export function extractDateOnly(value: string): string | null {
  if (/^\d{4}-\d{2}-\d{2}/.test(value)) {
    return value.slice(0, 10)
  }
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) {
    return null
  }
  return toJstDateString(parsed)
}
