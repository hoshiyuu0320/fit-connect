import { describe, it, expect } from 'vitest'
import type { SleepRecord } from '@/types/client'
import {
  formatSleepMinutes,
  buildSleepNightQuote,
  buildSleepWeekQuote,
  buildSleepQuote,
} from '@/lib/sleep/sleepQuote'

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

// 2026-09-23 12:00 JST
const NOW = new Date('2026-09-23T03:00:00Z')

describe('formatSleepMinutes', () => {
  it('H時間M分（ゼロ埋めなし）', () => {
    expect(formatSleepMinutes(252)).toBe('4時間12分')
    expect(formatSleepMinutes(425)).toBe('7時間5分')
  })
  it('分が0なら時間だけ、60分未満は分だけ、0分は0分', () => {
    expect(formatSleepMinutes(420)).toBe('7時間')
    expect(formatSleepMinutes(45)).toBe('45分')
    expect(formatSleepMinutes(0)).toBe('0分')
  })
  it('小数は分に丸める', () => {
    expect(formatSleepMinutes(330.4)).toBe('5時間30分')
    expect(formatSleepMinutes(329.6)).toBe('5時間30分')
  })
  it('負の値は0分', () => {
    expect(formatSleepMinutes(-5)).toBe('0分')
  })
})

describe('buildSleepNightQuote', () => {
  it('時間と目覚め評価の両方', () => {
    // 2026-09-22 は火曜
    expect(buildSleepNightQuote(sleep('2026-09-22', 252, 1))).toEqual({
      label: '睡眠 9/22(火)',
      text: '【睡眠 9/22(火)】4時間12分・目覚め: だるい',
    })
  })
  it('時間だけ / 評価だけ', () => {
    expect(buildSleepNightQuote(sleep('2026-09-22', 420, null))?.text).toBe('【睡眠 9/22(火)】7時間')
    expect(buildSleepNightQuote(sleep('2026-09-22', null, 3))?.text).toBe('【睡眠 9/22(火)】目覚め: すっきり')
  })
  it('両方 null なら引用しない', () => {
    expect(buildSleepNightQuote(sleep('2026-09-22', null, null))).toBeNull()
  })
  it('曜日は日本語の1文字', () => {
    expect(buildSleepNightQuote(sleep('2026-09-27', 480, 2))?.label).toBe('睡眠 9/27(日)')
    expect(buildSleepNightQuote(sleep('2026-10-05', 480, 2))?.label).toBe('睡眠 10/5(月)')
  })
})

describe('buildSleepWeekQuote', () => {
  it('平均時間・平均評価・記録日数', () => {
    const records = [sleep('2026-09-22', 330, 1), sleep('2026-09-21', 330, 2), sleep('2026-09-20', 330, 1)]
    expect(buildSleepWeekQuote(records, NOW)).toEqual({
      label: '睡眠 直近7日',
      text: '【睡眠 直近7日】平均 5時間30分・目覚め評価 1.3/3・記録 3日',
    })
  })
  it('平均時間が無ければ項を省く / 評価が無ければ項を省く', () => {
    expect(buildSleepWeekQuote([sleep('2026-09-22', null, 3)], NOW)?.text)
      .toBe('【睡眠 直近7日】目覚め評価 3.0/3・記録 1日')
    expect(buildSleepWeekQuote([sleep('2026-09-22', 480, null)], NOW)?.text)
      .toBe('【睡眠 直近7日】平均 8時間・記録 1日')
  })
  it('平均は分に丸めてから書式化する', () => {
    // (480 + 481) / 2 = 480.5 分 → 481 分 → 8時間1分
    expect(buildSleepWeekQuote([sleep('2026-09-22', 480), sleep('2026-09-21', 481)], NOW)?.text)
      .toBe('【睡眠 直近7日】平均 8時間1分・記録 2日')
  })
  it('直近7日に記録が無ければ null', () => {
    expect(buildSleepWeekQuote([sleep('2026-09-01', 480, 3)], NOW)).toBeNull()
    expect(buildSleepWeekQuote([], NOW)).toBeNull()
  })
  it('平均は分の値を直接丸める（時間に直してから戻さない）', () => {
    // (60 + 63) / 2 = 61.5 分 → 62 分 → 1時間2分（時間経由だと 61.4999… → 61 分になる）
    expect(buildSleepWeekQuote([sleep('2026-09-22', 60), sleep('2026-09-21', 63)], NOW)?.text)
      .toBe('【睡眠 直近7日】平均 1時間2分・記録 2日')
  })
})

describe('buildSleepQuote', () => {
  it('sleep_night は日付が一致する記録から作る', () => {
    const records = [sleep('2026-09-22', 252, 1), sleep('2026-09-21', 480, 3)]
    expect(buildSleepQuote({ kind: 'sleep_night', date: '2026-09-21' }, records, NOW)?.text)
      .toBe('【睡眠 9/21(月)】8時間・目覚め: すっきり')
  })
  it('sleep_night で日付が無ければ null', () => {
    expect(buildSleepQuote({ kind: 'sleep_night', date: '2026-09-19' }, [sleep('2026-09-22', 252, 1)], NOW)).toBeNull()
  })
  it('sleep_week は buildSleepWeekQuote と同じ', () => {
    const records = [sleep('2026-09-22', 480, 3)]
    expect(buildSleepQuote({ kind: 'sleep_week' }, records, NOW)).toEqual(buildSleepWeekQuote(records, NOW))
  })
})
