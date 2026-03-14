'use client'

import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Utensils } from 'lucide-react'
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

    // 食事区分別の記録率
    const mealTypeRates = (Object.keys(MEAL_TYPE_OPTIONS) as Array<keyof typeof MEAL_TYPE_OPTIONS>).map(
      (mealType) => {
        const count = mealTypeCounts[mealType] || 0
        // 各食事区分の記録率 = 記録数 / totalDays * 100
        const rate = totalDays > 0 ? Math.round((count / totalDays) * 100) : 0
        return { type: mealType, label: MEAL_TYPE_OPTIONS[mealType], count, rate }
      }
    )

    return {
      recordedDaysCount,
      recordedDaysPercentage:
        totalDays > 0 ? Math.round((recordedDaysCount / totalDays) * 100) : 0,
      mealTypeCounts,
      averageCalories,
      totalRecords: mealRecords.length,
      mealTypeRates,
    }
  }, [mealRecords, totalDays])

  // 最大記録率（バー比率計算用）
  const maxRate = Math.max(...statistics.mealTypeRates.map((r) => r.rate), 1)

  return (
    <Card className="border border-[#E2E8F0] rounded-md" style={{ boxShadow: 'none' }}>
      <CardHeader>
        <div className="flex items-center gap-2">
          <Utensils className="w-4 h-4 text-[#94A3B8]" />
          <CardTitle className="text-[#0F172A]">食事記録統計</CardTitle>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* 3ミニstat表示 */}
        <div className="grid grid-cols-3 gap-3">
          <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md p-3">
            <p className="text-[11px] text-[#94A3B8] mb-1">記録率</p>
            <p className="text-lg font-semibold text-[#0F172A]">
              {statistics.recordedDaysPercentage}
              <span className="text-xs text-[#64748B] ml-0.5">%</span>
            </p>
          </div>
          <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md p-3">
            <p className="text-[11px] text-[#94A3B8] mb-1">平均カロリー</p>
            <p className="text-lg font-semibold text-[#0F172A]">
              {statistics.averageCalories !== null ? (
                <>
                  {statistics.averageCalories}
                  <span className="text-xs text-[#64748B] ml-0.5">kcal</span>
                </>
              ) : (
                <span className="text-sm text-[#94A3B8]">--</span>
              )}
            </p>
          </div>
          <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md p-3">
            <p className="text-[11px] text-[#94A3B8] mb-1">合計記録件数</p>
            <p className="text-lg font-semibold text-[#0F172A]">
              {statistics.totalRecords}
              <span className="text-xs text-[#64748B] ml-0.5">件</span>
            </p>
          </div>
        </div>

        {/* 食事区分別プログレスバー */}
        <div>
          <h3 className="text-[11px] text-[#94A3B8] mb-3">食事区分別記録率</h3>
          <div className="space-y-3">
            {statistics.mealTypeRates.map((item) => (
              <div key={item.type}>
                <div className="flex items-center justify-between mb-1">
                  <span className="text-[11px] text-[#475569]">{item.label}</span>
                  <span className="text-[11px] font-semibold text-[#0F172A]">
                    {item.count}回
                    <span className="text-[#94A3B8] ml-1">({item.rate}%)</span>
                  </span>
                </div>
                <div className="w-full h-[6px] bg-[#F8FAFC] border border-[#E2E8F0] rounded-full overflow-hidden">
                  <div
                    className="h-full rounded-full transition-all"
                    style={{
                      width: `${maxRate > 0 ? (item.rate / maxRate) * 100 : 0}%`,
                      backgroundColor: '#EA580C',
                    }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
