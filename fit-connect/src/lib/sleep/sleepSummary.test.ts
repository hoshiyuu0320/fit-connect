import { describe, it, expect } from 'vitest'
import type { SleepRecord } from '@/types/client'
import { summarizeRecentSleep } from '@/lib/sleep/sleepSummary'

function sleep(
  recorded_date: string,
  total_sleep_minutes: number | null,
  wakeup_rating: 1 | 2 | 3 | null = null
): SleepRecord {
  return {
    id: `s-${recorded_date}`, client_id: 'c1', recorded_date,
    bed_time: null, wake_time: null, total_sleep_minutes,
    deep_minutes: null, light_minutes: null, rem_minutes: null, awake_minutes: null,
    wakeup_rating, source: 'healthkit',
    created_at: '2026-09-01T00:00:00Z', updated_at: '2026-09-01T00:00:00Z',
  }
}

// 2026-09-23 12:00 JST。7日前の境界は 2026-09-16T03:00:00Z
const NOW = new Date('2026-09-23T03:00:00Z')

describe('summarizeRecentSleep', () => {
  it('空配列は記録なし', () => {
    expect(summarizeRecentSleep([], NOW)).toEqual({
      avgMinutes: null, avgHours: null, avgWakeupRating: null, hasWarning: false, recentCount: 0,
    })
  })

  it('7日より前の記録は数えない（recorded_date は UTC 0:00 として比較）', () => {
    const out = summarizeRecentSleep(
      [sleep('2026-09-16', 480), sleep('2026-09-17', 480)],
      NOW
    )
    expect(out.recentCount).toBe(1)
  })

  it('直近7日に記録が無ければ記録なし', () => {
    const out = summarizeRecentSleep([sleep('2026-09-01', 480, 3)], NOW)
    expect(out).toEqual({ avgMinutes: null, avgHours: null, avgWakeupRating: null, hasWarning: false, recentCount: 0 })
  })

  it('平均は null の項目を除いて計算する', () => {
    const out = summarizeRecentSleep(
      [sleep('2026-09-22', 480, 3), sleep('2026-09-21', 360, null), sleep('2026-09-20', null, 1)],
      NOW
    )
    expect(out.avgHours).toBe(7)          // (480 + 360) / 2 / 60
    expect(out.avgWakeupRating).toBe(2)   // (3 + 1) / 2
    expect(out.recentCount).toBe(3)
    expect(out.hasWarning).toBe(false)
  })

  it('平均6時間未満なら警告', () => {
    const out = summarizeRecentSleep([sleep('2026-09-22', 330, 3)], NOW)
    expect(out.avgHours).toBe(5.5)
    expect(out.hasWarning).toBe(true)
  })

  it('平均目覚め評価1.5以下なら警告（1.5 ちょうどを含む）', () => {
    expect(summarizeRecentSleep([sleep('2026-09-22', 480, 1), sleep('2026-09-21', 480, 2)], NOW).hasWarning).toBe(true)
    expect(summarizeRecentSleep([sleep('2026-09-22', 480, 2), sleep('2026-09-21', 480, 2)], NOW).hasWarning).toBe(false)
  })

  it('値がすべて null の記録だけなら平均も警告も無いが日数は数える', () => {
    const out = summarizeRecentSleep([sleep('2026-09-22', null, null)], NOW)
    expect(out).toEqual({ avgMinutes: null, avgHours: null, avgWakeupRating: null, hasWarning: false, recentCount: 1 })
  })

  it('入力配列を変更しない', () => {
    const records = [sleep('2026-09-22', 480, 3), sleep('2026-09-21', 360, 2)]
    const copy = [...records]
    summarizeRecentSleep(records, NOW)
    expect(records).toEqual(copy)
  })

  it('平均を分でも返す（avgMinutes）', () => {
    const out = summarizeRecentSleep([sleep('2026-09-22', 60, 2), sleep('2026-09-21', 63, 2)], NOW)
    expect(out.avgMinutes).toBe(61.5)
    expect(out.avgHours).toBeCloseTo(61.5 / 60, 10)
  })

  it('境界: recorded_date が「now - 7日」と同時刻なら含む（>=）', () => {
    const midnight = new Date('2026-09-23T00:00:00Z') // since = 2026-09-16T00:00:00Z
    expect(summarizeRecentSleep([sleep('2026-09-16', 480)], midnight).recentCount).toBe(1)
    expect(summarizeRecentSleep([sleep('2026-09-15', 480)], midnight).recentCount).toBe(0)
  })

  it('days 引数で窓を変えられる', () => {
    const records = [sleep('2026-09-22', 480), sleep('2026-09-10', 480)]
    expect(summarizeRecentSleep(records, NOW, 14).recentCount).toBe(2)
    expect(summarizeRecentSleep(records, NOW, 7).recentCount).toBe(1)
  })

  it('返り値は凍結されている（共有の空サマリーを書き換えられない）', () => {
    const out = summarizeRecentSleep([], NOW)
    expect(Object.isFrozen(out)).toBe(true)
    expect(Object.isFrozen(summarizeRecentSleep([sleep('2026-09-22', 480)], NOW))).toBe(true)
  })
})
