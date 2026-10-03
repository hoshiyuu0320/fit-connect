import type { SleepRecord } from '@/types/client'

// 顧客詳細「睡眠（直近7日）」カードと、メッセージ画面の睡眠引用（sleep:7d）が
// 同じ数字を出すための純関数。SummaryTab の useMemo から移した（挙動は同じ）。
// 入力配列は変更しない。

export interface RecentSleepSummary {
  /** 平均睡眠時間（分）。total_sleep_minutes が非 null の記録だけの平均。無ければ null */
  readonly avgMinutes: number | null
  /** 平均睡眠時間（時間）。total_sleep_minutes が非 null の記録だけの平均。無ければ null */
  readonly avgHours: number | null
  /** 平均目覚め評価（1〜3）。wakeup_rating が非 null の記録だけの平均。無ければ null */
  readonly avgWakeupRating: number | null
  /** 平均6時間未満 or 平均評価1.5以下 */
  readonly hasWarning: boolean
  /** 直近 days 日の記録日数 */
  readonly recentCount: number
}

const DAY_MS = 24 * 60 * 60 * 1000

const EMPTY_SUMMARY: RecentSleepSummary = Object.freeze({
  avgMinutes: null,
  avgHours: null,
  avgWakeupRating: null,
  hasWarning: false,
  recentCount: 0,
})

/**
 * 直近 days 日（now を基準）の睡眠サマリー。
 * recorded_date（'yyyy-MM-dd'）は new Date() で UTC 0:00 として解釈し、now - days 日 以降を対象にする
 * （SummaryTab の従来の判定と同じ）。
 */
export function summarizeRecentSleep(
  records: readonly SleepRecord[],
  now: Date = new Date(),
  days = 7
): RecentSleepSummary {
  if (records.length === 0) return EMPTY_SUMMARY
  const since = new Date(now.getTime() - days * DAY_MS)
  const recent = records.filter((r) => new Date(r.recorded_date) >= since)
  if (recent.length === 0) return EMPTY_SUMMARY

  const withMinutes = recent.filter((r) => r.total_sleep_minutes !== null)
  const avgMinutes =
    withMinutes.length > 0
      ? withMinutes.reduce((sum, r) => sum + (r.total_sleep_minutes ?? 0), 0) / withMinutes.length
      : null
  const avgHours = avgMinutes !== null ? avgMinutes / 60 : null

  const withRating = recent.filter((r) => r.wakeup_rating !== null)
  const avgWakeupRating =
    withRating.length > 0
      ? withRating.reduce((sum, r) => sum + (r.wakeup_rating ?? 0), 0) / withRating.length
      : null

  // 6時間未満 or 平均評価1.5以下なら注意喚起
  const hasWarning =
    (avgHours !== null && avgHours < 6) || (avgWakeupRating !== null && avgWakeupRating <= 1.5)

  return Object.freeze({ avgMinutes, avgHours, avgWakeupRating, hasWarning, recentCount: recent.length })
}
