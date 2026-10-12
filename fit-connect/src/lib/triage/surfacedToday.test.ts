import { describe, it, expect } from 'vitest'
import { isSurfacedToday } from './surfacedToday'

describe('isSurfacedToday', () => {
  const now = new Date('2026-10-04T00:30:00Z') // JST 2026-10-04 09:30

  it('同じ日 → 今朝', () => {
    expect(isSurfacedToday('2026-10-04', now)).toBe(true)
  })

  it('前日 → 違う', () => {
    expect(isSurfacedToday('2026-10-03', now)).toBe(false)
  })

  it('翌日 → 違う', () => {
    expect(isSurfacedToday('2026-10-05', now)).toBe(false)
  })

  it('UTC 14:59:59 はまだ JST の同じ日、15:00:00 で JST の翌日になる', () => {
    const before = new Date('2026-10-03T14:59:59Z') // JST 2026-10-03 23:59:59
    const after = new Date('2026-10-03T15:00:00Z') // JST 2026-10-04 00:00:00
    expect(isSurfacedToday('2026-10-03', before)).toBe(true)
    expect(isSurfacedToday('2026-10-04', before)).toBe(false)
    expect(isSurfacedToday('2026-10-03', after)).toBe(false)
    expect(isSurfacedToday('2026-10-04', after)).toBe(true)
  })

  it('年をまたぐ境目', () => {
    expect(isSurfacedToday('2027-01-01', new Date('2026-12-31T15:00:00Z'))).toBe(true)
    expect(isSurfacedToday('2026-12-31', new Date('2026-12-31T15:00:00Z'))).toBe(false)
  })

  it.each([
    ['空文字', ''],
    ['時刻つき', '2026-10-04T00:00:00Z'],
    ['区切り違い', '2026/10/04'],
    ['桁不足', '2026-10-4'],
    ['文字列でない', 20261004],
    ['null', null],
    ['undefined', undefined],
  ])('読めない値（%s）→ 違う', (_label, value) => {
    expect(isSurfacedToday(value as string | null | undefined, now)).toBe(false)
  })

  it('now が不正な日時 → 違う', () => {
    expect(isSurfacedToday('2026-10-04', new Date('invalid'))).toBe(false)
  })
})
