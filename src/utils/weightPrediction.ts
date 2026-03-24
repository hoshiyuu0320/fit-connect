export type BmrFormula = 'mifflin' | 'harris'
export type Gender = 'male' | 'female' | 'other'

/**
 * BMR（基礎代謝量）を計算する
 */
export function calculateBmr(params: {
  weight: number
  height: number
  age: number
  gender: Gender
  formula: BmrFormula
}): number {
  const { weight, height, age, gender, formula } = params

  const calcForGender = (g: 'male' | 'female'): number => {
    if (formula === 'mifflin') {
      // ミフリン・セントジョール式
      return g === 'male'
        ? 10 * weight + 6.25 * height - 5 * age + 5
        : 10 * weight + 6.25 * height - 5 * age - 161
    }
    // ハリス・ベネディクト式（改良版）
    return g === 'male'
      ? 13.397 * weight + 4.799 * height - 5.677 * age + 88.362
      : 9.247 * weight + 3.098 * height - 4.33 * age + 447.593
  }

  if (gender === 'other') {
    return (calcForGender('male') + calcForGender('female')) / 2
  }
  return calcForGender(gender)
}

export type CalorieBalance = {
  avgIntake: number | null
  avgExerciseBurn: number | null
  dailyBalance: number | null
}

/**
 * 期間内のカロリー収支を算出する
 */
export function calculateCalorieBalance(params: {
  mealRecords: { calories: number | null }[]
  exerciseRecords: { calories: number | null }[]
  bmr: number
  periodDays: number
}): CalorieBalance {
  const { mealRecords, exerciseRecords, bmr, periodDays } = params

  if (periodDays <= 0) {
    return { avgIntake: null, avgExerciseBurn: null, dailyBalance: null }
  }

  // calories が null でない記録のみ集計
  const validMeals = mealRecords.filter((m) => m.calories !== null)
  const validExercises = exerciseRecords.filter((e) => e.calories !== null)

  const totalIntake = validMeals.reduce((sum, m) => sum + (m.calories ?? 0), 0)
  const totalBurn = validExercises.reduce((sum, e) => sum + (e.calories ?? 0), 0)

  const avgIntake = validMeals.length > 0 ? Math.round(totalIntake / periodDays) : null
  const avgExerciseBurn = validExercises.length > 0 ? Math.round(totalBurn / periodDays) : null

  const dailyBalance = avgIntake !== null ? avgIntake - (bmr + (avgExerciseBurn ?? 0)) : null

  return { avgIntake, avgExerciseBurn, dailyBalance }
}

export type WeightPrediction = {
  monthlyChange: number
  predictedWeight: number
  monthsToGoal: number | null
}

const KCAL_PER_KG_FAT = 7200

/**
 * カロリー収支から体重変動を予測する
 */
export function predictWeight(params: {
  currentWeight: number
  targetWeight: number
  dailyBalance: number
}): WeightPrediction {
  const { currentWeight, targetWeight, dailyBalance } = params

  const monthlyChange = (dailyBalance * 30) / KCAL_PER_KG_FAT
  const predictedWeight = currentWeight + monthlyChange

  // 目標到達予測
  const weightDiff = currentWeight - targetWeight
  let monthsToGoal: number | null = null

  if (Math.abs(monthlyChange) > 0.01) {
    const isMovingTowardGoal =
      (weightDiff > 0 && monthlyChange < 0) || (weightDiff < 0 && monthlyChange > 0)

    if (isMovingTowardGoal) {
      monthsToGoal = Math.round((Math.abs(weightDiff) / Math.abs(monthlyChange)) * 10) / 10
    }
  }

  return {
    monthlyChange: Math.round(monthlyChange * 10) / 10,
    predictedWeight: Math.round(predictedWeight * 10) / 10,
    monthsToGoal,
  }
}

export type WeightPeriod = '1W' | '1M' | '3M' | 'ALL'

/**
 * 期間フィルターに対応する日数を返す
 */
export function getPeriodDays(period: WeightPeriod): number {
  switch (period) {
    case '1W': return 7
    case '1M': return 30
    case '3M': return 90
    case 'ALL': return 30 // ALLのデフォルトは30日で計算
  }
}
