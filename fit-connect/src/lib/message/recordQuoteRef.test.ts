import { describe, it, expect } from 'vitest'
import {
  parseRecordQuoteRef,
  formatRecordQuoteRef,
  recordQuoteHref,
  recordQuoteDateRange,
} from '@/lib/message/recordQuoteRef'

describe('parseRecordQuoteRef', () => {
  it('sleep:YYYY-MM-DD は1晩', () => {
    expect(parseRecordQuoteRef('sleep:2026-09-22')).toEqual({ kind: 'sleep_night', date: '2026-09-22' })
  })
  it('sleep:7d は直近7日', () => {
    expect(parseRecordQuoteRef('sleep:7d')).toEqual({ kind: 'sleep_week' })
  })
  it('空・null・未知の種別・形式違いは null', () => {
    expect(parseRecordQuoteRef(null)).toBeNull()
    expect(parseRecordQuoteRef(undefined)).toBeNull()
    expect(parseRecordQuoteRef('')).toBeNull()
    expect(parseRecordQuoteRef('sleep:')).toBeNull()
    expect(parseRecordQuoteRef('weight:2026-09-22')).toBeNull()
    expect(parseRecordQuoteRef('sleep:2026/09/22')).toBeNull()
    expect(parseRecordQuoteRef('sleep:20260922')).toBeNull()
    expect(parseRecordQuoteRef('sleep:2026-09-22T00:00:00Z')).toBeNull()
    expect(parseRecordQuoteRef('SLEEP:2026-09-22')).toBeNull()
  })
  it('暦日として無効な日付は null', () => {
    expect(parseRecordQuoteRef('sleep:2026-13-40')).toBeNull()
    expect(parseRecordQuoteRef('sleep:2026-02-30')).toBeNull()
    expect(parseRecordQuoteRef('sleep:2026-00-10')).toBeNull()
  })
  it('うるう日は有効', () => {
    expect(parseRecordQuoteRef('sleep:2028-02-29')).toEqual({ kind: 'sleep_night', date: '2028-02-29' })
    expect(parseRecordQuoteRef('sleep:2026-02-29')).toBeNull()
  })
})

describe('formatRecordQuoteRef / recordQuoteHref', () => {
  it('parse と往復できる', () => {
    expect(formatRecordQuoteRef({ kind: 'sleep_night', date: '2026-09-22' })).toBe('sleep:2026-09-22')
    expect(formatRecordQuoteRef({ kind: 'sleep_week' })).toBe('sleep:7d')
    expect(parseRecordQuoteRef(formatRecordQuoteRef({ kind: 'sleep_week' }))).toEqual({ kind: 'sleep_week' })
  })
  it('リンクは clientId と record をエンコードする', () => {
    expect(recordQuoteHref('abc-123', { kind: 'sleep_night', date: '2026-09-22' }))
      .toBe('/message?clientId=abc-123&record=sleep%3A2026-09-22')
    expect(recordQuoteHref('a b&c', { kind: 'sleep_week' }))
      .toBe('/message?clientId=a%20b%26c&record=sleep%3A7d')
  })
})

describe('recordQuoteDateRange', () => {
  it('1晩はその日だけ', () => {
    expect(recordQuoteDateRange({ kind: 'sleep_night', date: '2026-09-22' }, new Date('2026-09-23T03:00:00Z')))
      .toEqual({ from: '2026-09-22', to: '2026-09-22' })
  })
  it('7日は今日（ローカル日付）から8日前まで', () => {
    // ローカル時刻で 2026-09-23 12:00 を作る（タイムゾーンに依存しない）
    const now = new Date(2026, 8, 23, 12, 0, 0)
    expect(recordQuoteDateRange({ kind: 'sleep_week' }, now)).toEqual({ from: '2026-09-15', to: '2026-09-23' })
  })
  it('7日の範囲は月をまたいでも正しい', () => {
    const now = new Date(2026, 9, 3, 9, 0, 0) // 2026-10-03
    expect(recordQuoteDateRange({ kind: 'sleep_week' }, now)).toEqual({ from: '2026-09-25', to: '2026-10-03' })
  })
})
