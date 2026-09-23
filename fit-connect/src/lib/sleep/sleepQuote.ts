import { format, parseISO } from 'date-fns'
import { ja } from 'date-fns/locale'
import type { SleepRecord } from '@/types/client'
import { WAKEUP_RATING_OPTIONS } from '@/types/client'
import { summarizeRecentSleep } from '@/lib/sleep/sleepSummary'
import type { RecordQuoteRef } from '@/lib/message/recordQuoteRef'

// メッセージ画面の「記録の引用」。送信時に本文の先頭へ平文で付く（Mobile でも崩れない）。
// 将来 metadata.record_ref を添えるときも text はそのまま旧アプリ向けのフォールバックになる。

export interface RecordQuote {
  /** チップの見出し（例 '睡眠 9/22(火)'） */
  label: string
  /** 本文の先頭に付ける1行（例 '【睡眠 9/22(火)】4時間12分・目覚め: だるい'） */
  text: string
}

/** 分 → 'H時間M分'（ゼロ埋めなし。分が 0 なら 'H時間'、60分未満は 'M分'） */
export function formatSleepMinutes(totalMinutes: number): string {
  const minutes = Math.max(0, Math.round(totalMinutes))
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return `${m}分`
  return m === 0 ? `${h}時間` : `${h}時間${m}分`
}

/** 'yyyy-MM-dd' → 'M/d(曜)'（曜日は日本語1文字） */
function formatSleepDate(recordedDate: string): string {
  return format(parseISO(recordedDate), 'M/d(E)', { locale: ja })
}

function quote(label: string, parts: string[]): RecordQuote {
  return { label, text: `【${label}】${parts.join('・')}` }
}

/** 1晩の引用。時間と目覚め評価の両方が無ければ null */
export function buildSleepNightQuote(record: SleepRecord): RecordQuote | null {
  const parts: string[] = []
  if (record.total_sleep_minutes !== null) parts.push(formatSleepMinutes(record.total_sleep_minutes))
  if (record.wakeup_rating !== null) parts.push(`目覚め: ${WAKEUP_RATING_OPTIONS[record.wakeup_rating]}`)
  if (parts.length === 0) return null
  return quote(`睡眠 ${formatSleepDate(record.recorded_date)}`, parts)
}

/** 直近7日の引用（SummaryTab の睡眠カードと同じ数字）。記録が無ければ null */
export function buildSleepWeekQuote(records: readonly SleepRecord[], now: Date = new Date()): RecordQuote | null {
  const s = summarizeRecentSleep(records, now)
  if (s.recentCount === 0) return null
  const parts: string[] = []
  if (s.avgMinutes !== null) parts.push(`平均 ${formatSleepMinutes(s.avgMinutes)}`)
  if (s.avgWakeupRating !== null) parts.push(`目覚め評価 ${s.avgWakeupRating.toFixed(1)}/3`)
  parts.push(`記録 ${s.recentCount}日`)
  return quote('睡眠 直近7日', parts)
}

/** record クエリの参照と取得済みの記録から引用を作る */
export function buildSleepQuote(
  ref: RecordQuoteRef,
  records: readonly SleepRecord[],
  now: Date = new Date()
): RecordQuote | null {
  if (ref.kind === 'sleep_week') return buildSleepWeekQuote(records, now)
  if (ref.kind === 'sleep_night') {
    const record = records.find((r) => r.recorded_date === ref.date)
    return record ? buildSleepNightQuote(record) : null
  }
  return null
}
