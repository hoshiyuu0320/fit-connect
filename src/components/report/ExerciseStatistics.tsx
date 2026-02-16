'use client'

import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { ExerciseRecord, EXERCISE_TYPE_OPTIONS } from '@/types/client'

interface ExerciseStatisticsProps {
  exerciseRecords: ExerciseRecord[]
  totalDays: number
}

export function ExerciseStatistics({ exerciseRecords, totalDays }: ExerciseStatisticsProps) {
  const statistics = useMemo(() => {
    // 記録がある日数
    const recordedDates = new Set(
      exerciseRecords.map(r => r.recorded_at.split('T')[0])
    )
    const recordedDays = recordedDates.size

    // 種目別カウント
    const exerciseTypeCounts = exerciseRecords.reduce((acc, record) => {
      acc[record.exercise_type] = (acc[record.exercise_type] || 0) + 1
      return acc
    }, {} as Record<string, number>)

    // 上位5件を降順でソート
    const topExerciseTypes = Object.entries(exerciseTypeCounts)
      .sort(([, a], [, b]) => b - a)
      .slice(0, 5)

    // 合計時間（duration が non-null のもの）
    const totalDuration = exerciseRecords
      .filter(r => r.duration !== null)
      .reduce((sum, r) => sum + (r.duration || 0), 0)

    // 平均カロリー消費
    const calorieRecords = exerciseRecords.filter(r => r.calories !== null)
    const averageCalories = calorieRecords.length > 0
      ? Math.round(calorieRecords.reduce((sum, r) => sum + (r.calories || 0), 0) / calorieRecords.length)
      : null

    return {
      recordedDays,
      topExerciseTypes,
      totalDuration,
      averageCalories,
    }
  }, [exerciseRecords])

  return (
    <Card>
      <CardHeader>
        <CardTitle>運動記録統計</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* 記録頻度 */}
        <div>
          <h4 className="text-sm font-semibold text-gray-700 mb-2">記録頻度</h4>
          <p className="text-lg">
            {statistics.recordedDays} / {totalDays} 日
          </p>
        </div>

        {/* 種目別カウント */}
        <div>
          <h4 className="text-sm font-semibold text-gray-700 mb-2">種目別カウント（上位5件）</h4>
          <div className="space-y-2">
            {statistics.topExerciseTypes.length > 0 ? (
              statistics.topExerciseTypes.map(([exerciseType, count]) => (
                <div key={exerciseType} className="flex justify-between">
                  <span className="text-gray-700">
                    {EXERCISE_TYPE_OPTIONS[exerciseType as keyof typeof EXERCISE_TYPE_OPTIONS]}
                  </span>
                  <span className="font-semibold">{count} 回</span>
                </div>
              ))
            ) : (
              <p className="text-gray-500">記録なし</p>
            )}
          </div>
        </div>

        {/* 合計時間 */}
        <div>
          <h4 className="text-sm font-semibold text-gray-700 mb-2">合計時間</h4>
          <p className="text-lg">{statistics.totalDuration} 分</p>
        </div>

        {/* 平均カロリー消費 */}
        <div>
          <h4 className="text-sm font-semibold text-gray-700 mb-2">平均カロリー消費</h4>
          <p className="text-lg">
            {statistics.averageCalories !== null
              ? `${statistics.averageCalories} kcal / 回`
              : 'カロリーデータなし'}
          </p>
        </div>
      </CardContent>
    </Card>
  )
}
