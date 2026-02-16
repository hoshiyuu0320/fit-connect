'use client'

import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { MealRecord, MEAL_TYPE_OPTIONS } from '@/types/client'

interface MealStatisticsProps {
  mealRecords: MealRecord[]
  totalDays: number
}

export function MealStatistics({ mealRecords, totalDays }: MealStatisticsProps) {
  const statistics = useMemo(() => {
    // 記録がある日数をカウント（recorded_atの日付部分でユニーク集計）
    const recordedDates = new Set(
      mealRecords.map((record) => record.recorded_at.split('T')[0])
    )
    const recordedDaysCount = recordedDates.size

    // 食事区分別カウント
    const mealTypeCounts = mealRecords.reduce(
      (acc, record) => {
        acc[record.meal_type] = (acc[record.meal_type] || 0) + 1
        return acc
      },
      {} as Record<MealRecord['meal_type'], number>
    )

    // 平均カロリー計算（caloriesがnullでないものの平均）
    const recordsWithCalories = mealRecords.filter(
      (record) => record.calories !== null
    )
    const totalCalories = recordsWithCalories.reduce(
      (sum, record) => sum + (record.calories || 0),
      0
    )
    const averageCalories =
      recordsWithCalories.length > 0
        ? Math.round(totalCalories / recordedDaysCount)
        : null

    return {
      recordedDaysCount,
      recordedDaysPercentage:
        totalDays > 0 ? Math.round((recordedDaysCount / totalDays) * 100) : 0,
      mealTypeCounts,
      averageCalories,
    }
  }, [mealRecords, totalDays])

  return (
    <Card>
      <CardHeader>
        <CardTitle>食事記録統計</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* 記録頻度 */}
        <div>
          <h3 className="text-sm font-medium text-gray-700 mb-2">記録頻度</h3>
          <p className="text-lg">
            <span className="font-bold text-blue-600">
              {statistics.recordedDaysCount}
            </span>{' '}
            / {totalDays} 日
            <span className="text-sm text-gray-600 ml-2">
              ({statistics.recordedDaysPercentage}%)
            </span>
          </p>
        </div>

        {/* 食事区分別カウント */}
        <div>
          <h3 className="text-sm font-medium text-gray-700 mb-2">
            食事区分別記録数
          </h3>
          <div className="flex flex-wrap gap-3">
            {(Object.keys(MEAL_TYPE_OPTIONS) as Array<keyof typeof MEAL_TYPE_OPTIONS>).map(
              (mealType) => (
                <div
                  key={mealType}
                  className="bg-gray-50 rounded-lg px-3 py-2 text-sm"
                >
                  <span className="text-gray-600">
                    {MEAL_TYPE_OPTIONS[mealType]}
                  </span>
                  <span className="font-semibold ml-1">
                    {statistics.mealTypeCounts[mealType] || 0}回
                  </span>
                </div>
              )
            )}
          </div>
        </div>

        {/* 平均カロリー */}
        <div>
          <h3 className="text-sm font-medium text-gray-700 mb-2">
            平均カロリー
          </h3>
          {statistics.averageCalories !== null ? (
            <p className="text-lg">
              <span className="font-bold text-emerald-600">
                {statistics.averageCalories}
              </span>{' '}
              kcal / 日
            </p>
          ) : (
            <p className="text-sm text-gray-500">カロリーデータなし</p>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
