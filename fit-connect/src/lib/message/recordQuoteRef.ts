import { format, isValid, parseISO, subDays } from 'date-fns'
import { SLEEP_WEEK_PARAM, type RecordQuoteRef } from '@/lib/message/recordQuoteLink'

// /message?clientId=…&record=<ref> の <ref> の文法。
//   sleep:YYYY-MM-DD … その日付（sleep_records.recorded_date）の1晩
//   sleep:7d         … 直近7日のサマリー（SummaryTab の睡眠カードと同じ計算）
// それ以外は受け付けない（拡張で weight: 等を足すときはここと recordQuoteLink.ts に追加する）。
// URL に載せるのは日付だけで、睡眠時間などの値は載せない。
// 型とリンクの組み立ては依存の無い recordQuoteLink.ts に置き、既存の import 先を変えないよう再 export する。

export { formatRecordQuoteRef, recordQuoteHref, type RecordQuoteRef } from '@/lib/message/recordQuoteLink'

const SLEEP_NIGHT_RE = /^sleep:(\d{4}-\d{2}-\d{2})$/

/** 'yyyy-MM-dd' が実在する暦日か（parseISO の検証 + 往復で桁ずれを弾く） */
function isCalendarDate(date: string): boolean {
  const parsed = parseISO(date)
  return isValid(parsed) && format(parsed, 'yyyy-MM-dd') === date
}

export function parseRecordQuoteRef(param: string | null | undefined): RecordQuoteRef | null {
  if (!param) return null
  if (param === SLEEP_WEEK_PARAM) return { kind: 'sleep_week' }
  const m = SLEEP_NIGHT_RE.exec(param)
  if (!m) return null
  const date = m[1]
  return isCalendarDate(date) ? { kind: 'sleep_night', date } : null
}

/**
 * 引用の対象を取るための recorded_date の範囲（両端含む、'yyyy-MM-dd'、ローカル日付）。
 * 7日は summarizeRecentSleep が「now - 7日 以降」を UTC 0:00 基準で判定するので、
 * 取りこぼさないよう 8 日前から今日まで取り、絞り込みは summarizeRecentSleep に任せる。
 */
export function recordQuoteDateRange(ref: RecordQuoteRef, now: Date = new Date()): { from: string; to: string } {
  if (ref.kind === 'sleep_night') return { from: ref.date, to: ref.date }
  return { from: format(subDays(now, 8), 'yyyy-MM-dd'), to: format(now, 'yyyy-MM-dd') }
}
