import { describe, it, expect } from 'vitest'
import { getJstMonthRange, toJstDateString, extractDateOnly } from '@/lib/payments/jstDate'

describe('getJstMonthRange', () => {
  it('月中の時刻 → JST 暦月の [1日00:00, 翌月1日00:00) を UTC ISO で返す', () => {
    const range = getJstMonthRange(new Date('2026-07-12T10:00:00Z')) // JST 7/12 19:00
    expect(range.startIso).toBe('2026-06-30T15:00:00.000Z') // JST 7/1 00:00
    expect(range.endIso).toBe('2026-07-31T15:00:00.000Z') // JST 8/1 00:00
  })

  it('JST では翌月・UTC では月末（月境界をまたぐケース）', () => {
    // UTC 6/30 15:00 = JST 7/1 00:00 ちょうど → 7月扱い
    const range = getJstMonthRange(new Date('2026-06-30T15:00:00Z'))
    expect(range.startIso).toBe('2026-06-30T15:00:00.000Z')
    expect(range.endIso).toBe('2026-07-31T15:00:00.000Z')
  })

  it('JST 月初直前（UTC 6/30 14:59）は 6月扱い', () => {
    const range = getJstMonthRange(new Date('2026-06-30T14:59:59Z'))
    expect(range.startIso).toBe('2026-05-31T15:00:00.000Z') // JST 6/1 00:00
    expect(range.endIso).toBe('2026-06-30T15:00:00.000Z')
  })

  it('年をまたぐ12月も正しく計算する', () => {
    const range = getJstMonthRange(new Date('2026-12-15T00:00:00Z'))
    expect(range.startIso).toBe('2026-11-30T15:00:00.000Z') // JST 12/1 00:00
    expect(range.endIso).toBe('2026-12-31T15:00:00.000Z') // JST 1/1 00:00
  })
})

describe('toJstDateString', () => {
  it('UTC 深夜でも JST の日付を返す', () => {
    expect(toJstDateString(new Date('2026-07-12T20:00:00Z'))).toBe('2026-07-13') // JST 翌日
    expect(toJstDateString(new Date('2026-07-12T10:00:00Z'))).toBe('2026-07-12')
  })
})

describe('extractDateOnly', () => {
  it('YYYY-MM-DD 始まりの文字列は先頭10文字を返す', () => {
    expect(extractDateOnly('2026-07-12')).toBe('2026-07-12')
    expect(extractDateOnly('2026-07-12T20:00:00.000Z')).toBe('2026-07-12')
  })

  it('解釈不能な文字列は null', () => {
    expect(extractDateOnly('not-a-date')).toBe(null)
  })
})
