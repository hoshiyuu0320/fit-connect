/**
 * 「今日の対応」の理由に付ける「今朝」の目印の判定（設計書 docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md §7.5）。
 * 朝のまとめ通知の対象（surfaced_on = JST の今日）と同じ定義。
 * 依存の無い小さなモジュールにする（date-fns などを import しない。lessons「全ページの layout から読まれる純関数に、重い依存を足さない」）
 */

const JST_OFFSET_MS = 9 * 60 * 60 * 1000
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

/** now の JST の暦日（'YYYY-MM-DD'）。now が不正な日時なら null */
function jstDateString(now: Date): string | null {
  const time = now.getTime()
  if (Number.isNaN(time)) return null
  // JST は夏時間が無いので、UTC に +9 時間した時刻の UTC の暦日が JST の暦日
  return new Date(time + JST_OFFSET_MS).toISOString().slice(0, 10)
}

/**
 * surfacedOn（'YYYY-MM-DD'）が now の JST の暦日と同じなら true。
 * 読めない値（null・形式違い）は false。now は呼び出し側が渡す（「今日の対応」を取り直した時点）
 */
export function isSurfacedToday(surfacedOn: string | null | undefined, now: Date): boolean {
  if (typeof surfacedOn !== 'string' || !ISO_DATE.test(surfacedOn)) return false
  const today = jstDateString(now)
  return today !== null && surfacedOn === today
}
