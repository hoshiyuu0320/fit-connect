import { describe, it, expect } from 'vitest'
import type { WeightRecord } from '@/types/client'
import {
  sortWeightRecordsChronologically,
  latestWeightRecord,
  recentWeightRecordsWithChange,
  weightChangeSince,
} from '@/lib/weight/weightRecordSelectors'

function rec(id: string, recordedAt: string, weight: number): WeightRecord {
  return { id, client_id: 'c1', weight, notes: null, recorded_at: recordedAt, image_urls: null }
}

const round1 = (x: number) => Math.round(x * 10) / 10

// 本番相当のフィクスチャ（27件、8/7 63.6kg … 9/22 13:29:20Z 67kg）
const PROD_ROWS: [string, number][] = [
  ['2026-08-07T12:00:00Z', 63.6],
  ['2026-08-08T12:00:00Z', 63.3],
  ['2026-08-09T12:00:00Z', 63.7],
  ['2026-08-10T12:00:00Z', 63.5],
  ['2026-08-11T12:00:00Z', 63.9],
  ['2026-08-12T12:00:00Z', 64.6],
  ['2026-08-14T12:00:00Z', 64.4],
  ['2026-08-16T12:00:00Z', 64.8],
  ['2026-08-18T12:00:00Z', 64.5],
  ['2026-08-20T12:00:00Z', 65.0],
  ['2026-08-22T12:00:00Z', 64.9],
  ['2026-08-23T12:00:00Z', 65.2],
  ['2026-08-25T12:00:00Z', 65.1],
  ['2026-08-27T12:00:00Z', 65.4],
  ['2026-08-29T12:00:00Z', 65.3],
  ['2026-08-31T12:00:00Z', 65.7],
  ['2026-09-02T12:00:00Z', 65.5],
  ['2026-09-04T12:00:00Z', 65.9],
  ['2026-09-06T12:00:00Z', 65.8],
  ['2026-09-08T12:00:00Z', 66.0],
  ['2026-09-10T12:00:00Z', 65.9],
  ['2026-09-12T12:00:00Z', 66.2],
  ['2026-09-14T12:00:00Z', 66.1],
  ['2026-09-16T12:00:00Z', 66.4],
  ['2026-09-18T12:00:00Z', 66.2],
  ['2026-09-19T12:00:00Z', 66.3],
  ['2026-09-22T13:29:20Z', 67],
]

// getWeightRecords と同じ古い順
const ASC: WeightRecord[] = PROD_ROWS.map(([at, w], i) => rec(`w${i + 1}`, at, w))
const DESC: WeightRecord[] = [...ASC].reverse()
// 決定的なシャッフル（7 と 27 は互いに素なので全件を1回ずつ並べ替える）
const SHUFFLED: WeightRecord[] = ASC.map((_, i) => ASC[(i * 7 + 3) % ASC.length])

const ORDERS: [string, WeightRecord[]][] = [
  ['昇順', ASC],
  ['降順', DESC],
  ['シャッフル', SHUFFLED],
]

const NOW = new Date('2026-09-22T14:00:00Z')
const time = (r: WeightRecord) => new Date(r.recorded_at).getTime()

describe('フィクスチャ', () => {
  it('27件で、シャッフルは昇順・降順のどちらとも一致しない', () => {
    expect(ASC).toHaveLength(27)
    expect(new Set(SHUFFLED.map((r) => r.id)).size).toBe(27)
    expect(SHUFFLED.map((r) => r.id)).not.toEqual(ASC.map((r) => r.id))
    expect(SHUFFLED.map((r) => r.id)).not.toEqual(DESC.map((r) => r.id))
  })
})

describe('sortWeightRecordsChronologically', () => {
  it.each(ORDERS)('%s入力でも古い順の新しい配列を返す', (_label, input) => {
    const before = input.map((r) => r.id)
    const out = sortWeightRecordsChronologically(input)
    expect(out).not.toBe(input)
    expect(out.map((r) => r.id)).toEqual(ASC.map((r) => r.id))
    expect(input.map((r) => r.id)).toEqual(before)
  })
  it('同時刻の記録は入力順を維持する', () => {
    const a = rec('a', '2026-09-01T00:00:00Z', 60)
    const b = rec('b', '2026-09-01T00:00:00Z', 61)
    const c = rec('c', '2026-08-01T00:00:00Z', 62)
    expect(sortWeightRecordsChronologically([a, b, c]).map((r) => r.id)).toEqual(['c', 'a', 'b'])
  })
})

describe('latestWeightRecord', () => {
  it.each(ORDERS)('%s入力でも最新は 9/22 の 67kg', (_label, input) => {
    const latest = latestWeightRecord(input)
    expect(latest?.recorded_at).toBe('2026-09-22T13:29:20Z')
    expect(latest?.weight).toBe(67)
  })
  it('空配列は null', () => {
    expect(latestWeightRecord([])).toBeNull()
  })
})

describe('recentWeightRecordsWithChange', () => {
  it.each(ORDERS)('%s入力でも新しい順5件・直前（古い）記録との差分', (_label, input) => {
    const out = recentWeightRecordsWithChange(input, 5)
    expect(out).toHaveLength(5)
    expect(out[0].record.recorded_at).toBe('2026-09-22T13:29:20Z')
    for (let i = 1; i < out.length; i++) {
      expect(time(out[i].record)).toBeLessThan(time(out[i - 1].record))
    }
    // 全体の新しい順（6件目まで）と比較
    const newest = DESC.slice(0, 6)
    out.forEach((row, i) => {
      expect(row.record.id).toBe(newest[i].id)
      expect(row.change).toBe(round1(newest[i].weight - newest[i + 1].weight))
    })
    // 5件目も6件目（9/12）と比較するので null にならない
    expect(out[4].change).not.toBeNull()
    expect(out.map((r) => r.change)).toEqual([0.7, 0.1, -0.2, 0.3, -0.1])
  })

  it('回帰: [8/7 63.6, 8/8 63.3] は 8/8 が -0.3、8/7 が null（旧実装は 8/7 に +0.3）', () => {
    const input = [rec('a', '2026-08-07T12:00:00Z', 63.6), rec('b', '2026-08-08T12:00:00Z', 63.3)]
    expect(recentWeightRecordsWithChange(input, 5)).toEqual([
      { record: input[1], change: -0.3 },
      { record: input[0], change: null },
    ])
    // 入力順を逆にしても同じ
    expect(recentWeightRecordsWithChange([input[1], input[0]], 5)).toEqual([
      { record: input[1], change: -0.3 },
      { record: input[0], change: null },
    ])
  })

  it('63.3 → 63.6 の差分はちょうど 0.3（浮動小数の誤差を残さない）', () => {
    const input = [rec('a', '2026-08-07T12:00:00Z', 63.3), rec('b', '2026-08-08T12:00:00Z', 63.6)]
    const [first] = recentWeightRecordsWithChange(input, 1)
    expect(first.change).toBe(0.3)
  })

  it('差分が 0 付近でも -0 にならない', () => {
    const same = [rec('a', '2026-08-07T12:00:00Z', 63.6), rec('b', '2026-08-08T12:00:00Z', 63.6)]
    expect(Object.is(recentWeightRecordsWithChange(same, 1)[0].change, 0)).toBe(true)
    // -0.04 は丸めると -0 になるケース
    const tiny = [rec('a', '2026-08-07T12:00:00Z', 63.64), rec('b', '2026-08-08T12:00:00Z', 63.6)]
    expect(Object.is(recentWeightRecordsWithChange(tiny, 1)[0].change, 0)).toBe(true)
  })

  it('件数が n 未満なら全件、最古の記録は null', () => {
    const out = recentWeightRecordsWithChange(ASC.slice(0, 3), 5)
    expect(out).toHaveLength(3)
    expect(out.map((r) => r.record.id)).toEqual(['w3', 'w2', 'w1'])
    expect(out[2].change).toBeNull()
  })

  it('空配列は空配列', () => {
    expect(recentWeightRecordsWithChange([], 5)).toEqual([])
  })
})

describe('weightChangeSince', () => {
  it.each(ORDERS)('%s入力でも 67kg − 基準日以前で最も新しい記録（8/23 65.2kg）', (_label, input) => {
    // 基準日 = 2026-08-23T14:00:00Z → 最古の 8/7 ではなく 8/23 12:00Z の記録
    expect(weightChangeSince(input, NOW)).toBe(1.8)
    expect(weightChangeSince(input, NOW)).toBe(round1(67 - 65.2))
  })

  it('基準日ちょうどの記録は基準に含める', () => {
    const input = [
      rec('a', '2026-08-01T00:00:00Z', 70),
      rec('b', '2026-08-23T14:00:00Z', 66),
      rec('c', '2026-08-23T14:00:01Z', 99),
      rec('d', '2026-09-22T13:29:20Z', 67),
    ]
    expect(weightChangeSince(input, NOW)).toBe(1)
  })

  it('全記録が基準日より新しいと null', () => {
    const input = [rec('a', '2026-09-01T00:00:00Z', 66), rec('b', '2026-09-22T13:29:20Z', 67)]
    expect(weightChangeSince(input, NOW)).toBeNull()
  })

  it('空配列は null', () => {
    expect(weightChangeSince([], NOW)).toBeNull()
  })

  it('差が無いときは -0 ではなく 0', () => {
    const input = [rec('a', '2026-08-01T00:00:00Z', 67), rec('b', '2026-09-22T13:29:20Z', 67)]
    expect(Object.is(weightChangeSince(input, NOW), 0)).toBe(true)
  })

  it('days を指定できる', () => {
    // 7日前 = 2026-09-15T14:00:00Z → 9/14 の 66.1kg が基準
    expect(weightChangeSince(ASC, NOW, 7)).toBe(round1(67 - 66.1))
  })
})

describe('入力を変更しない', () => {
  it('Object.freeze した配列・要素でも例外を出さず、並びも変わらない', () => {
    const frozen = Object.freeze(SHUFFLED.map((r) => Object.freeze({ ...r })))
    const before = frozen.map((r) => r.id)
    expect(() => sortWeightRecordsChronologically(frozen)).not.toThrow()
    expect(() => latestWeightRecord(frozen)).not.toThrow()
    expect(() => recentWeightRecordsWithChange(frozen, 5)).not.toThrow()
    expect(() => weightChangeSince(frozen, NOW)).not.toThrow()
    expect(frozen.map((r) => r.id)).toEqual(before)
    expect(latestWeightRecord(frozen)?.weight).toBe(67)
  })
})
