'use client'

import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dumbbell } from 'lucide-react'
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

    // 記録率
    const recordedDaysPercentage =
      totalDays > 0 ? Math.round((recordedDays / totalDays) * 100) : 0

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

    // 消費カロリー合計
    const totalCalories = exerciseRecords
      .filter(r => r.calories !== null)
      .reduce((sum, r) => sum + (r.calories || 0), 0)

    return {
      recordedDays,
      recordedDaysPercentage,
      topExerciseTypes,
      totalDuration,
      totalCalories,
    }
  }, [exerciseRecords, totalDays])

  // 最大回数（バー比率計算用）
  const maxCount = statistics.topExerciseTypes.length > 0
    ? statistics.topExerciseTypes[0][1]
    : 1

  return (
    <Card className="border border-[#E2E8F0] rounded-md" style={{ boxShadow: 'none' }}>
      <CardHeader>
        <div className="flex items-center gap-2">
          <Dumbbell className="w-4 h-4 text-[#94A3B8]" />
          <CardTitle className="text-[#0F172A]">運動記録統計</CardTitle>
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
            <p className="text-[11px] text-[#94A3B8] mb-1">合計時間</p>
            <p className="text-lg font-semibold text-[#0F172A]">
              {statistics.totalDuration}
              <span className="text-xs text-[#64748B] ml-0.5">分</span>
            </p>
          </div>
          <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md p-3">
            <p className="text-[11px] text-[#94A3B8] mb-1">消費カロリー合計</p>
            <p className="text-lg font-semibold text-[#0F172A]">
              {statistics.totalCalories}
              <span className="text-xs text-[#64748B] ml-0.5">kcal</span>
            </p>
          </div>
        </div>

        {/* 種目別プログレスバー（上位5件） */}
        <div>
          <h3 className="text-[11px] text-[#94A3B8] mb-3">種目別カウント（上位5件）</h3>
          <div className="space-y-3">
            {statistics.topExerciseTypes.length > 0 ? (
              statistics.topExerciseTypes.map(([exerciseType, count]) => (
                <div key={exerciseType}>
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-[11px] text-[#475569]">
                      {EXERCISE_TYPE_OPTIONS[exerciseType as keyof typeof EXERCISE_TYPE_OPTIONS] ?? exerciseType}
                    </span>
                    <span className="text-[11px] font-semibold text-[#0F172A]">
                      {count}回
                    </span>
                  </div>
                  <div className="w-full h-[6px] bg-[#F8FAFC] border border-[#E2E8F0] rounded-full overflow-hidden">
                    <div
                      className="h-full rounded-full transition-all"
                      style={{
                        width: `${maxCount > 0 ? (count / maxCount) * 100 : 0}%`,
                        backgroundColor: '#16A34A',
                      }}
                    />
                  </div>
                </div>
              ))
            ) : (
              <p className="text-sm text-[#94A3B8]">記録なし</p>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
