import { describe, it, expect, afterEach } from 'vitest'
import { exclusiveEndDate } from '@/lib/report/recordedAtRange'

const DAY_MS = 24 * 60 * 60 * 1000

/** 期待値: 'yyyy-MM-dd' を UTC 0時のエポックミリ秒として 1日足した日付（ローカルタイムゾーンを一切通さない） */
function expectedNextDay(date: string): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + DAY_MS).toISOString().slice(0, 10)
}

describe('exclusiveEndDate', () => {
  it('翌日を返す（今日の 13:29Z の記録が lt 翌日 0時 に含まれる）', () => {
    expect(exclusiveEndDate('2026-09-22')).toBe('2026-09-23')
  })

  it('月末は翌月1日に繰り上がる', () => {
    expect(exclusiveEndDate('2026-09-30')).toBe('2026-10-01')
    expect(exclusiveEndDate('2026-01-31')).toBe('2026-02-01')
  })

  it('年末は翌年1月1日に繰り上がる', () => {
    expect(exclusiveEndDate('2026-12-31')).toBe('2027-01-01')
  })

  it('うるう年の2月は29日まである', () => {
    expect(exclusiveEndDate('2028-02-28')).toBe('2028-02-29')
    expect(exclusiveEndDate('2028-02-29')).toBe('2028-03-01')
  })

  it('平年の2月28日の翌日は3月1日', () => {
    expect(exclusiveEndDate('2027-02-28')).toBe('2027-03-01')
  })

  it('0〜99年も1900年代に読み替えない（日付入力で年を打ち込み途中の値）', () => {
    expect(exclusiveEndDate('0002-09-22')).toBe('0002-09-23')
  })

  it.each([
    '',
    '2026-9-22',
    '2026/09/22',
    '20260922',
    '2026-09-22T00:00:00Z',
    ' 2026-09-22',
    'abcd-ef-gh',
  ])("'yyyy-MM-dd' 形式でない値は例外を投げる: %j", (input) => {
    expect(() => exclusiveEndDate(input)).toThrow()
  })

  it.each(['2026-02-30', '2027-02-29', '2026-13-01', '2026-00-10', '2026-09-00', '2026-09-31'])(
    '実在しない日付は例外を投げる: %s',
    (input) => {
      expect(() => exclusiveEndDate(input)).toThrow()
    }
  )
})

describe('exclusiveEndDate はローカルタイムゾーンに依存しない', () => {
  const originalTz = process.env.TZ
  afterEach(() => {
    // undefined を代入すると文字列 'undefined' になるので、元が無ければ消す
    if (originalTz === undefined) delete process.env.TZ
    else process.env.TZ = originalTz
  })

  // UTC より東（JST・+14h）と西（-8h・-11h）の両方で確認する
  it.each(['UTC', 'Asia/Tokyo', 'America/Los_Angeles', 'Pacific/Kiritimati', 'Pacific/Pago_Pago'])(
    'TZ=%s でも 2024〜2029 年の全日付で UTC 計算の期待値と一致する',
    (tz) => {
      process.env.TZ = tz
      const start = Date.parse('2024-01-01T00:00:00Z')
      const end = Date.parse('2029-12-31T00:00:00Z')
      for (let ms = start; ms <= end; ms += DAY_MS) {
        const date = new Date(ms).toISOString().slice(0, 10)
        expect(exclusiveEndDate(date)).toBe(expectedNextDay(date))
      }
    }
  )
})
