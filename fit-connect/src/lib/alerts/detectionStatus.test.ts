import { describe, it, expect } from 'vitest'
import {
  detectionWarning,
  evaluateDetectionState,
  formatDetectionSummary,
  formatJstMonthDayTime,
  formatExclusionSummary,
  listExclusions,
  parseAlertDetectionStatus,
  DETECTION_DELAY_HOURS,
} from '@/lib/alerts/detectionStatus'
import type { AlertDetectionStatus } from '@/types/alert'

const HOUR_MS = 60 * 60 * 1000

// 9/13 06:00 JST = 9/12 21:00 UTC に成功した本実行
const LAST_RUN = '2026-09-12T21:00:00.000Z'

const baseStatus: AlertDetectionStatus = {
  enabled: true,
  last_succeeded_at: LAST_RUN,
  last_target_date: '2026-09-13',
  monitored_count: 1,
  excluded_no_account: 9,
  excluded_not_started: 3,
  excluded_inactive: 0,
}

const at = (iso: string) => new Date(iso)
const afterLastRun = (ms: number) => new Date(new Date(LAST_RUN).getTime() + ms)

describe('evaluateDetectionState', () => {
  it('有効で最後の成功が30時間以内なら最新（最終チェック時刻は JST）', () => {
    expect(evaluateDetectionState(baseStatus, at('2026-09-13T01:00:00Z'))).toEqual({
      kind: 'fresh',
      lastSucceededAt: LAST_RUN,
      lastCheckedLabel: '9/13 6:00',
    })
  })

  it('30時間ちょうどは最新、それを超えたら遅延', () => {
    expect(
      evaluateDetectionState(baseStatus, afterLastRun(DETECTION_DELAY_HOURS * HOUR_MS)).kind
    ).toBe('fresh')
    expect(
      evaluateDetectionState(baseStatus, afterLastRun(DETECTION_DELAY_HOURS * HOUR_MS + 1)).kind
    ).toBe('delayed')
  })

  it('翌朝の実行が抜けて昼を過ぎたら遅延（前日 6:00 の成功 → 翌日 12:01）', () => {
    expect(evaluateDetectionState(baseStatus, at('2026-09-14T03:01:00Z')).kind).toBe('delayed')
    expect(evaluateDetectionState(baseStatus, at('2026-09-14T02:59:00Z')).kind).toBe('fresh')
  })

  it('有効だが一度も成功していなければ未実行', () => {
    expect(
      evaluateDetectionState(
        { ...baseStatus, last_succeeded_at: null, last_target_date: null },
        at('2026-09-13T01:00:00Z')
      )
    ).toEqual({ kind: 'not_run', lastSucceededAt: null, lastCheckedLabel: null })
  })

  it('cron が inactive なら停止中（実行記録があれば最終チェック時刻も返す）', () => {
    expect(
      evaluateDetectionState({ ...baseStatus, enabled: false }, at('2026-09-13T01:00:00Z'))
    ).toEqual({ kind: 'paused', lastSucceededAt: LAST_RUN, lastCheckedLabel: '9/13 6:00' })
  })

  it('停止中は未実行・遅延より優先する', () => {
    expect(
      evaluateDetectionState(
        { ...baseStatus, enabled: false, last_succeeded_at: null },
        at('2026-09-13T01:00:00Z')
      ).kind
    ).toBe('paused')
    expect(
      evaluateDetectionState({ ...baseStatus, enabled: false }, at('2026-09-20T01:00:00Z')).kind
    ).toBe('paused')
  })

  it('解釈できない時刻は未実行と同じに扱う', () => {
    expect(
      evaluateDetectionState(
        { ...baseStatus, last_succeeded_at: 'not-a-date' },
        at('2026-09-13T01:00:00Z')
      )
    ).toEqual({ kind: 'not_run', lastSucceededAt: null, lastCheckedLabel: null })
  })

  it('端末の時計が遅れていて最後の成功が未来に見えても最新', () => {
    expect(evaluateDetectionState(baseStatus, at('2026-09-12T20:00:00Z')).kind).toBe('fresh')
  })
})

describe('detectionWarning', () => {
  const now = at('2026-09-13T01:00:00Z')

  it('最新なら警告なし', () => {
    expect(detectionWarning(evaluateDetectionState(baseStatus, now))).toBeNull()
  })

  it('未実行', () => {
    const state = evaluateDetectionState({ ...baseStatus, last_succeeded_at: null }, now)
    expect(detectionWarning(state)).toBe(
      '自動チェックはまだ実行されていません。毎朝 6:00 に実行されます。'
    )
  })

  it('遅延は、いつのチェック結果かを添える', () => {
    const state = evaluateDetectionState(baseStatus, at('2026-09-14T04:00:00Z'))
    expect(detectionWarning(state)).toBe(
      '自動チェックが遅れています。表示しているのは 9/13 6:00 のチェック結果です。'
    )
  })

  it('停止中は、実行記録の有無で文言を分ける', () => {
    expect(detectionWarning(evaluateDetectionState({ ...baseStatus, enabled: false }, now))).toBe(
      '自動チェックは停止中です。表示しているのは 9/13 6:00 のチェック結果です。'
    )
    expect(
      detectionWarning(
        evaluateDetectionState({ ...baseStatus, enabled: false, last_succeeded_at: null }, now)
      )
    ).toBe('自動チェックは停止中です。まだ一度も実行されていません。')
  })
})

describe('formatDetectionSummary', () => {
  const now = at('2026-09-13T01:00:00Z')

  it('最終チェック時刻（JST）と対象人数', () => {
    const status = { ...baseStatus, monitored_count: 12 }
    expect(formatDetectionSummary(status, evaluateDetectionState(status, now))).toBe(
      '最終チェック 9/13 6:00・自動チェックの対象 12人'
    )
  })

  it('未実行なら対象人数だけ（0人でも出す）', () => {
    const status = { ...baseStatus, last_succeeded_at: null, monitored_count: 0 }
    expect(formatDetectionSummary(status, evaluateDetectionState(status, now))).toBe(
      '自動チェックの対象 0人'
    )
  })
})

describe('formatJstMonthDayTime', () => {
  it('JST の日付と時刻（UTC の日付だと前日になる時刻）', () => {
    // UTC 9/12 15:30 = JST 9/13 0:30
    expect(formatJstMonthDayTime('2026-09-12T15:30:00Z')).toBe('9/13 0:30')
    expect(formatJstMonthDayTime('2026-09-12T21:05:09.123+00:00')).toBe('9/13 6:05')
    expect(formatJstMonthDayTime('2026-12-31T15:00:00Z')).toBe('1/1 0:00')
  })

  it('解釈できなければ null', () => {
    expect(formatJstMonthDayTime('')).toBeNull()
    expect(formatJstMonthDayTime('yesterday')).toBeNull()
  })
})

describe('対象外の人数', () => {
  it('理由別の人数を表示の順で並べ、0人の理由は出さない', () => {
    expect(listExclusions(baseStatus)).toEqual([
      { reason: 'no_account', label: 'アプリ未登録', count: 9 },
      { reason: 'not_started', label: '記録開始前', count: 3 },
    ])
    expect(formatExclusionSummary(baseStatus)).toBe(
      '自動チェックの対象外: アプリ未登録 9人・記録開始前 3人'
    )
  })

  it('2週間以上データなしも出す', () => {
    expect(
      formatExclusionSummary({
        ...baseStatus,
        excluded_no_account: 0,
        excluded_not_started: 0,
        excluded_inactive: 2,
      })
    ).toBe('自動チェックの対象外: 2週間以上データなし 2人')
  })

  it('対象外がいなければ null', () => {
    expect(
      formatExclusionSummary({
        ...baseStatus,
        excluded_no_account: 0,
        excluded_not_started: 0,
        excluded_inactive: 0,
      })
    ).toBeNull()
  })
})

describe('parseAlertDetectionStatus', () => {
  it('RPC の配列の先頭行を型に揃える（bigint が文字列で届いても数える）', () => {
    expect(
      parseAlertDetectionStatus([
        {
          enabled: true,
          last_succeeded_at: LAST_RUN,
          last_target_date: '2026-09-13',
          monitored_count: '1',
          excluded_no_account: 9,
          excluded_not_started: '3',
          excluded_inactive: 0,
        },
      ])
    ).toEqual(baseStatus)
  })

  it('0行（トレーナーでない）・行でない値は null', () => {
    expect(parseAlertDetectionStatus([])).toBeNull()
    expect(parseAlertDetectionStatus(null)).toBeNull()
    expect(parseAlertDetectionStatus('x')).toBeNull()
  })

  it('欠けた列は安全側（無効・未実行・0人）に倒す', () => {
    expect(parseAlertDetectionStatus({ enabled: null })).toEqual({
      enabled: false,
      last_succeeded_at: null,
      last_target_date: null,
      monitored_count: 0,
      excluded_no_account: 0,
      excluded_not_started: 0,
      excluded_inactive: 0,
    })
  })

  it('負数・非数の人数は 0', () => {
    const parsed = parseAlertDetectionStatus({ ...baseStatus, monitored_count: -1, excluded_inactive: 'x' })
    expect(parsed?.monitored_count).toBe(0)
    expect(parsed?.excluded_inactive).toBe(0)
  })
})
