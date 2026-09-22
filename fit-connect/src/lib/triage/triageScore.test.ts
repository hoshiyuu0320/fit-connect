import { describe, it, expect } from 'vitest'
import {
  TRIAGE_SCORE_WEIGHTS,
  alertScore,
  compareTriagePriority,
  triageScore,
  unrepliedElapsedHours,
  unrepliedScore,
  type TriageScoreAlert,
  type TriageSortKey,
} from '@/lib/triage/triageScore'

/** 途絶 gap_from〜gap_to（両端を含む）の record_gap の payload */
function gapPayload(gapFrom: string, gapTo: string) {
  return {
    v: 1,
    variant: 'no_data',
    gap_from: gapFrom,
    gap_to: gapTo,
    last_activity_on: '2026-08-01',
    last_record_on: '2026-08-01',
    threshold_days: 3,
  }
}

function alert(overrides: Partial<TriageScoreAlert> = {}): TriageScoreAlert {
  return {
    alert_type: 'weight_change',
    severity: 'high',
    status: 'open',
    payload: {},
    ...overrides,
  }
}

/** 4日の途絶（9/9〜9/12） */
const GAP_4_DAYS = gapPayload('2026-09-09', '2026-09-12')

describe('TRIAGE_SCORE_WEIGHTS', () => {
  it('重みは計画書の式のまま（変えるときはこのテストと計画書を一緒に直す）', () => {
    expect(TRIAGE_SCORE_WEIGHTS).toEqual({
      unrepliedPointsPerHour: 2,
      unrepliedMaxHours: 72,
      alertSeverityPoints: { high: 30, medium: 10, low: 0 },
      recordGapPointsPerDay: 5,
      recordGapMaxDays: 14,
    })
  })
})

describe('unrepliedElapsedHours', () => {
  const now = new Date('2026-09-13T09:00:00Z')

  it('時間単位で切り捨てる（18時間59分 → 18）', () => {
    expect(unrepliedElapsedHours('2026-09-12T14:01:00Z', now)).toBe(18)
    expect(unrepliedElapsedHours('2026-09-12T15:00:00Z', now)).toBe(18)
  })

  it('1時間未満は 0、未来（端末の時計の遅れ）も 0、読めない時刻も 0', () => {
    expect(unrepliedElapsedHours('2026-09-13T08:30:00Z', now)).toBe(0)
    expect(unrepliedElapsedHours('2026-09-13T12:00:00Z', now)).toBe(0)
    expect(unrepliedElapsedHours('not-a-date', now)).toBe(0)
    expect(unrepliedElapsedHours('2026-09-12T14:00:00Z', new Date('invalid'))).toBe(0)
  })

  it('オフセット付きの時刻も時刻として数える（+09:00 の 9:00 = UTC 0:00）', () => {
    expect(unrepliedElapsedHours('2026-09-13T09:00:00+09:00', now)).toBe(9)
  })
})

describe('unrepliedScore', () => {
  it('1時間 2点、72時間で頭打ち', () => {
    expect(unrepliedScore(0)).toBe(0)
    expect(unrepliedScore(18)).toBe(36)
    expect(unrepliedScore(71)).toBe(142)
    expect(unrepliedScore(72)).toBe(144)
    expect(unrepliedScore(73)).toBe(144)
    expect(unrepliedScore(24 * 7)).toBe(144)
  })
})

describe('alertScore', () => {
  it('open のアラートは high 30 / medium 10', () => {
    expect(alertScore(alert({ severity: 'high' }))).toBe(30)
    expect(alertScore(alert({ severity: 'medium' }))).toBe(10)
  })

  it('acknowledged / resolved は点に入れない', () => {
    expect(alertScore(alert({ status: 'acknowledged' }))).toBe(0)
    expect(alertScore(alert({ status: 'resolved' }))).toBe(0)
    expect(
      alertScore(alert({ alert_type: 'record_gap', status: 'acknowledged', payload: GAP_4_DAYS }))
    ).toBe(0)
  })

  it('record_gap は重要度の点に、途絶の日数 × 5 を足す', () => {
    // medium 10 + 4日 × 5
    expect(alertScore(alert({ alert_type: 'record_gap', severity: 'medium', payload: GAP_4_DAYS }))).toBe(30)
  })

  it('途絶の日数は14日で頭打ち', () => {
    const days = (to: string) =>
      alertScore(alert({ alert_type: 'record_gap', severity: 'high', payload: gapPayload('2026-09-01', to) }))
    expect(days('2026-09-13')).toBe(30 + 13 * 5) // 13日
    expect(days('2026-09-14')).toBe(30 + 14 * 5) // 14日
    expect(days('2026-09-15')).toBe(30 + 14 * 5) // 15日でも14日分
    expect(days('2026-09-30')).toBe(30 + 14 * 5)
  })

  it('日数は record_gap だけに足す（weight_change の payload に日付があっても足さない）', () => {
    expect(alertScore(alert({ alert_type: 'weight_change', payload: GAP_4_DAYS }))).toBe(30)
  })

  it('payload が壊れた record_gap は重要度の点だけ', () => {
    expect(alertScore(alert({ alert_type: 'record_gap', severity: 'high', payload: null }))).toBe(30)
    expect(
      alertScore(
        alert({ alert_type: 'record_gap', severity: 'high', payload: gapPayload('2026-09-12', '2026-09-09') })
      )
    ).toBe(30)
  })

  it('未知の重要度は medium 扱い、low は 0 点', () => {
    expect(alertScore(alert({ severity: 'critical' }))).toBe(10)
    expect(alertScore(alert({ severity: 'low' }))).toBe(0)
  })
})

describe('triageScore', () => {
  const now = new Date('2026-09-13T09:00:00Z')

  it('未返信・アラート・途絶の日数を足す（期日×達成率の +20 は無い）', () => {
    const score = triageScore({
      alerts: [
        alert({ alert_type: 'weight_change', severity: 'high' }), // 30
        alert({ alert_type: 'record_gap', severity: 'medium', payload: GAP_4_DAYS }), // 10 + 20
        alert({ alert_type: 'weight_change', severity: 'high', status: 'acknowledged' }), // 0
      ],
      unreplied: { since: '2026-09-12T15:00:00Z', now }, // 18時間 → 36
    })
    expect(score).toBe(96)
  })

  it('未返信が無ければアラートの点だけ、どちらも無ければ 0', () => {
    expect(triageScore({ alerts: [alert({ severity: 'medium' })], unreplied: null })).toBe(10)
    expect(triageScore({ alerts: [], unreplied: null })).toBe(0)
  })

  it('未返信の時間は渡した now から数える', () => {
    const since = '2026-09-13T00:00:00Z'
    expect(triageScore({ alerts: [], unreplied: { since, now: new Date('2026-09-13T05:30:00Z') } })).toBe(10)
    expect(triageScore({ alerts: [], unreplied: { since, now: new Date('2026-09-16T00:00:00Z') } })).toBe(144)
  })
})

describe('compareTriagePriority', () => {
  function key(overrides: Partial<TriageSortKey>): TriageSortKey {
    return {
      score: 30,
      unrepliedSince: null,
      firstDetectedOn: null,
      clientName: 'たなか',
      clientId: 'client-x',
      ...overrides,
    }
  }
  const order = (keys: TriageSortKey[]) =>
    [...keys].sort(compareTriagePriority).map((k) => k.clientId)

  it('スコアの高い順', () => {
    expect(order([key({ clientId: 'low', score: 10 }), key({ clientId: 'high', score: 50 })])).toEqual([
      'high',
      'low',
    ])
  })

  it('同点なら未返信が古い順。未返信の無い行は後ろ', () => {
    expect(
      order([
        key({ clientId: 'none' }),
        key({ clientId: 'new', unrepliedSince: '2026-09-13T01:00:00Z' }),
        key({ clientId: 'old', unrepliedSince: '2026-09-12T01:00:00Z' }),
      ])
    ).toEqual(['old', 'new', 'none'])
  })

  it('未返信の時刻は文字列でなく時刻で比べる（+09:00 表記と Z 表記が混ざっても誤らない）', () => {
    // a = UTC 9/12 23:00、b = UTC 9/12 23:30。文字列の比較だと b が古く見える
    expect(
      order([
        key({ clientId: 'b', unrepliedSince: '2026-09-12T23:30:00Z' }),
        key({ clientId: 'a', unrepliedSince: '2026-09-13T08:00:00+09:00' }),
      ])
    ).toEqual(['a', 'b'])
  })

  it('未返信も同じなら、最初の検知日が古い順。アラートの無い行は後ろ', () => {
    expect(
      order([
        key({ clientId: 'none' }),
        key({ clientId: 'new', firstDetectedOn: '2026-09-13' }),
        key({ clientId: 'old', firstDetectedOn: '2026-09-10' }),
      ])
    ).toEqual(['old', 'new', 'none'])
  })

  it('未返信の古さは最初の検知日より先に見る', () => {
    expect(
      order([
        key({ clientId: 'alert-old', firstDetectedOn: '2026-09-01' }),
        key({ clientId: 'unreplied', unrepliedSince: '2026-09-13T01:00:00Z', firstDetectedOn: '2026-09-13' }),
      ])
    ).toEqual(['unreplied', 'alert-old'])
  })

  it('それも同じなら名前、最後に顧客 ID', () => {
    expect(
      order([
        key({ clientId: 'c-2', clientName: 'いとう' }),
        key({ clientId: 'c-3', clientName: 'あべ' }),
        key({ clientId: 'c-1', clientName: 'いとう' }),
      ])
    ).toEqual(['c-3', 'c-1', 'c-2'])
  })
})
