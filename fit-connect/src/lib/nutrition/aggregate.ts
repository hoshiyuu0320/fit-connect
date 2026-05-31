// ================================================
// 栄養トレンド 日次集計ユーティリティ
// ================================================

import { format, startOfDay, subDays, subMonths } from 'date-fns'
import type { MealRecord, WeightRecord } from '@/types/client'
import type { PeriodFilter } from '@/types/period'

export type DailyNutritionPoint = {
  date: string // 'YYYY-MM-DD'
  weight: number | null
  calories: number
  protein: number
  fat: number
  carbs: number
}

/**
 * 期間フィルターから日付範囲（開始日）を算出する。
 * 'all' の場合は null を返し、フィルタしない。
 */
function getStartDate(period: PeriodFilter, today: Date): Date | null {
  switch (period) {
    case 'week':
      return subDays(startOfDay(today), 6) // 今日を含む直近7日
    case 'month':
      return subDays(startOfDay(today), 29) // 今日を含む直近30日
    case 'threeMonths':
      return subMonths(startOfDay(today), 3)
    case 'all':
    default:
      return null
  }
}

/**
 * 食事記録と体重記録を日次で集計し、期間内の全日付を埋めた配列を返す。
 *
 * - 食事: calories / protein_g / fat_g / carbs_g を日次でSUM（NULLは0扱い）
 * - 体重: 日次でAVG。データなしの日は null
 * - 期間内の全日付を埋める（食事0件 + 体重なしの日は calories=0, weight=null）
 *
 * @param meals  食事記録
 * @param weights 体重記録
 * @param period 期間フィルター
 * @returns 日付昇順の日次集計
 */
export function aggregateDailyNutrition(
  meals: MealRecord[],
  weights: WeightRecord[],
  period: PeriodFilter
): DailyNutritionPoint[] {
  const today = new Date()
  const startDate = getStartDate(period, today)

  // 期間でフィルタ（'all' のときは全件）
  const filteredMeals = startDate
    ? meals.filter((m) => new Date(m.recorded_at) >= startDate)
    : meals
  const filteredWeights = startDate
    ? weights.filter((w) => new Date(w.recorded_at) >= startDate)
    : weights

  // 日次集計用マップ
  const mealMap = new Map<
    string,
    { calories: number; protein: number; fat: number; carbs: number }
  >()
  for (const m of filteredMeals) {
    const key = format(new Date(m.recorded_at), 'yyyy-MM-dd')
    const acc = mealMap.get(key) ?? { calories: 0, protein: 0, fat: 0, carbs: 0 }
    acc.calories += m.calories ?? 0
    acc.protein += m.protein_g ?? 0
    acc.fat += m.fat_g ?? 0
    acc.carbs += m.carbs_g ?? 0
    mealMap.set(key, acc)
  }

  const weightAccMap = new Map<string, { sum: number; count: number }>()
  for (const w of filteredWeights) {
    const key = format(new Date(w.recorded_at), 'yyyy-MM-dd')
    const acc = weightAccMap.get(key) ?? { sum: 0, count: 0 }
    acc.sum += w.weight
    acc.count += 1
    weightAccMap.set(key, acc)
  }

  // 期間内の全日付を生成（startDate がない場合はデータ最古日から today まで）
  let rangeStart: Date
  const rangeEnd = startOfDay(today)
  if (startDate) {
    rangeStart = startDate
  } else {
    const allDates = [
      ...filteredMeals.map((m) => new Date(m.recorded_at).getTime()),
      ...filteredWeights.map((w) => new Date(w.recorded_at).getTime()),
    ]
    if (allDates.length === 0) {
      return []
    }
    rangeStart = startOfDay(new Date(Math.min(...allDates)))
  }

  const points: DailyNutritionPoint[] = []
  const cursor = new Date(rangeStart)
  while (cursor.getTime() <= rangeEnd.getTime()) {
    const key = format(cursor, 'yyyy-MM-dd')
    const meal = mealMap.get(key) ?? { calories: 0, protein: 0, fat: 0, carbs: 0 }
    const weightAcc = weightAccMap.get(key)
    points.push({
      date: key,
      weight: weightAcc ? Math.round((weightAcc.sum / weightAcc.count) * 10) / 10 : null,
      calories: Math.round(meal.calories),
      protein: Math.round(meal.protein),
      fat: Math.round(meal.fat),
      carbs: Math.round(meal.carbs),
    })
    cursor.setDate(cursor.getDate() + 1)
  }

  return points
}
