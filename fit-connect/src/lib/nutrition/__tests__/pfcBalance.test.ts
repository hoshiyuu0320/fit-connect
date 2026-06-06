import { describe, it, expect } from 'vitest'
import { computePfcBalance, DEFAULT_PFC_TARGETS } from '@/lib/nutrition/pfcBalance'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'

function pt(over: Partial<DailyNutritionPoint>): DailyNutritionPoint {
  return { date: '2026-05-01', weight: null, calories: 0, protein: 0, fat: 0, carbs: 0, ...over }
}

describe('computePfcBalance', () => {
  it('データが空なら hasData=false', () => {
    const r = computePfcBalance([])
    expect(r.hasData).toBe(false)
    expect(r.avgCaloriesPerDay).toBe(0)
    expect(r.macros.map((m) => m.key)).toEqual(['protein', 'fat', 'carbs'])
  })

  it('全日0なら hasData=false（食事記録のある日0扱い）', () => {
    const r = computePfcBalance([pt({}), pt({ date: '2026-05-02' })])
    expect(r.hasData).toBe(false)
  })

  it('記録のある日だけで平均kcal/日を算出する', () => {
    const points = [
      pt({ date: '2026-05-01', calories: 1800, protein: 100, fat: 60, carbs: 200 }),
      pt({ date: '2026-05-02' }), // 食事なしの日 → 平均の分母に含めない
    ]
    const r = computePfcBalance(points)
    expect(r.hasData).toBe(true)
    expect(r.avgCaloriesPerDay).toBe(1800)
  })

  it('エネルギー比%とステータスを算出する（高/高/低の例）', () => {
    const points = [pt({ calories: 1800, protein: 100, fat: 60, carbs: 200 })]
    // kcal: P400 F540 C800 = 1740 → P22.99% F31.03% C45.98%
    const r = computePfcBalance(points)
    const [p, f, c] = r.macros
    expect(p.ratio).toBeCloseTo(22.99, 1)
    expect(f.ratio).toBeCloseTo(31.03, 1)
    expect(c.ratio).toBeCloseTo(45.98, 1)
    expect(p.status).toBe('high') // 20超
    expect(f.status).toBe('high') // 30超
    expect(c.status).toBe('low') // 50未満
    expect(p.grams).toBe(100)
  })

  it('全て目安内なら optimal', () => {
    const points = [pt({ calories: 1795, protein: 75, fat: 55, carbs: 250 })]
    // kcal: P300 F495 C1000 = 1795 → P16.7% F27.6% C55.7%
    const r = computePfcBalance(points)
    expect(r.macros.every((m) => m.status === 'optimal')).toBe(true)
  })

  it('1日平均グラムは記録日数で割って四捨五入する', () => {
    const points = [
      pt({ date: '2026-05-01', calories: 1000, protein: 90 }),
      pt({ date: '2026-05-02', calories: 1000, protein: 110 }),
    ]
    const r = computePfcBalance(points)
    expect(r.macros[0].grams).toBe(100) // (90+110)/2
  })

  it('既定の目安レンジは厚労省基準相当', () => {
    expect(DEFAULT_PFC_TARGETS.protein).toEqual({ lo: 13, hi: 20 })
    expect(DEFAULT_PFC_TARGETS.fat).toEqual({ lo: 20, hi: 30 })
    expect(DEFAULT_PFC_TARGETS.carbs).toEqual({ lo: 50, hi: 65 })
  })
})
