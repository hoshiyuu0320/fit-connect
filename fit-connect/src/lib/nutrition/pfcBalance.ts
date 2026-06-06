// ================================================
// PFC構成比・適正判定ユーティリティ（純関数）
// ================================================

import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'

export type MacroKey = 'protein' | 'fat' | 'carbs'

/** エネルギー比（%）の目安レンジ */
export type MacroTarget = { lo: number; hi: number }
export type PfcTargets = Record<MacroKey, MacroTarget>

/** 厚労省 食事摂取基準 相当のエネルギー比目安（既定値） */
export const DEFAULT_PFC_TARGETS: PfcTargets = {
  protein: { lo: 13, hi: 20 },
  fat: { lo: 20, hi: 30 },
  carbs: { lo: 50, hi: 65 },
}

export type MacroStatus = 'low' | 'optimal' | 'high'

export type MacroBalance = {
  key: MacroKey
  grams: number // 1日平均グラム（四捨五入）
  ratio: number // エネルギー比 %（生値・未丸め）
  status: MacroStatus
  target: MacroTarget
}

export type PfcBalance = {
  hasData: boolean
  avgCaloriesPerDay: number // 食事記録のある日の平均（四捨五入）
  macros: MacroBalance[] // protein, fat, carbs の順
}

const KCAL_PER_G: Record<MacroKey, number> = { protein: 4, fat: 9, carbs: 4 }
const MACRO_ORDER: MacroKey[] = ['protein', 'fat', 'carbs']

function statusOf(ratio: number, t: MacroTarget): MacroStatus {
  if (ratio < t.lo) return 'low'
  if (ratio > t.hi) return 'high'
  return 'optimal'
}

/**
 * 日次集計から PFC構成比（エネルギー比）と適正判定を算出する。
 *
 * - 構成比はエネルギー(kcal)比。P×4 / F×9 / C×4 で換算。
 * - 平均kcal/日は「食事記録のある日（calories/PFCいずれか>0）」で割る。
 * - 食事記録のある日が0 or 総kcal0なら hasData=false。
 */
export function computePfcBalance(
  points: DailyNutritionPoint[],
  targets: PfcTargets = DEFAULT_PFC_TARGETS
): PfcBalance {
  const totalG: Record<MacroKey, number> = { protein: 0, fat: 0, carbs: 0 }
  let totalCalories = 0
  let daysWithMeals = 0

  for (const p of points) {
    if (p.calories > 0 || p.protein > 0 || p.fat > 0 || p.carbs > 0) {
      daysWithMeals += 1
    }
    totalG.protein += p.protein
    totalG.fat += p.fat
    totalG.carbs += p.carbs
    totalCalories += p.calories
  }

  const kcal: Record<MacroKey, number> = {
    protein: totalG.protein * KCAL_PER_G.protein,
    fat: totalG.fat * KCAL_PER_G.fat,
    carbs: totalG.carbs * KCAL_PER_G.carbs,
  }
  const totalKcal = kcal.protein + kcal.fat + kcal.carbs

  if (daysWithMeals === 0 || totalKcal === 0) {
    return {
      hasData: false,
      avgCaloriesPerDay: 0,
      macros: MACRO_ORDER.map((key) => ({
        key,
        grams: 0,
        ratio: 0,
        status: 'low',
        target: targets[key],
      })),
    }
  }

  const macros: MacroBalance[] = MACRO_ORDER.map((key) => {
    const ratio = (kcal[key] / totalKcal) * 100
    return {
      key,
      grams: Math.round(totalG[key] / daysWithMeals),
      ratio,
      status: statusOf(ratio, targets[key]),
      target: targets[key],
    }
  })

  return {
    hasData: true,
    avgCaloriesPerDay: Math.round(totalCalories / daysWithMeals),
    macros,
  }
}
