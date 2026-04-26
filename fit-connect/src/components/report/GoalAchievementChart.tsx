'use client'

import { useMemo, useState } from 'react'
import {
  ResponsiveContainer,
  LineChart,
  Line,
  CartesianGrid,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
} from 'recharts'
import {
  eachWeekOfInterval,
  eachMonthOfInterval,
  endOfWeek,
  endOfMonth,
  differenceInDays,
  format,
} from 'date-fns'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import type { WeightRecord, MealRecord, ExerciseRecord } from '@/types/client'

interface GoalAchievementChartProps {
  weightRecords: WeightRecord[]
  allWeightRecords: WeightRecord[]
  mealRecords: MealRecord[]
  exerciseRecords: ExerciseRecord[]
  startDate: string
  endDate: string
  targetWeight: number
}

type ViewMode = 'weekly' | 'monthly'

interface ChartDataPoint {
  label: string
  weightProgress: number | null
  mealRate: number
  exerciseRate: number
  totalScore: number
}

function minDate(a: Date, b: Date): Date {
  return a < b ? a : b
}

export function GoalAchievementChart({
  weightRecords,
  allWeightRecords,
  mealRecords,
  exerciseRecords,
  startDate,
  endDate,
  targetWeight,
}: GoalAchievementChartProps) {
  const [viewMode, setViewMode] = useState<ViewMode>('weekly')

  const initialWeight = useMemo(() => {
    if (allWeightRecords.length === 0) return null
    const sorted = [...allWeightRecords].sort(
      (a, b) =>
        new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime()
    )
    return sorted[0].weight
  }, [allWeightRecords])

  const chartData = useMemo((): ChartDataPoint[] => {
    const start = new Date(startDate)
    const end = new Date(endDate)

    // 期間が不正な場合は空配列を返す
    if (start > end) return []

    // 各期間の開始日リストを生成
    let intervals: Date[]
    if (viewMode === 'weekly') {
      intervals = eachWeekOfInterval({ start, end }, { weekStartsOn: 1 })
    } else {
      intervals = eachMonthOfInterval({ start, end })
    }

    if (intervals.length === 0) return []

    // 前の期間の体重進捗率を引き継ぐための変数
    let lastWeightProgress: number | null = null

    return intervals.map((intervalStart) => {
      // 各期間の終了日を算出
      const periodEnd =
        viewMode === 'weekly'
          ? minDate(endOfWeek(intervalStart, { weekStartsOn: 1 }), end)
          : minDate(endOfMonth(intervalStart), end)

      // ラベル生成
      const label =
        viewMode === 'weekly'
          ? format(intervalStart, 'M/d') + '〜'
          : format(intervalStart, 'yyyy/M')

      // 文字列ベースの日付比較（タイムゾーンの影響を回避）
      const startStr = format(intervalStart, 'yyyy-MM-dd')
      const endStr = format(periodEnd, 'yyyy-MM-dd')

      // 期間内の日数
      const daysInPeriod = differenceInDays(periodEnd, intervalStart) + 1

      // 食事記録率: 記録がある日のユニーク数 / 期間日数 * 100
      const mealDates = new Set(
        mealRecords
          .filter((record) => {
            const dateStr = record.recorded_at.split('T')[0]
            return dateStr >= startStr && dateStr <= endStr
          })
          .map((record) => record.recorded_at.split('T')[0])
      )
      const mealRate =
        Math.round((mealDates.size / daysInPeriod) * 100 * 10) / 10

      // 運動記録率: 記録がある日のユニーク数 / 期間日数 * 100
      const exerciseDates = new Set(
        exerciseRecords
          .filter((record) => {
            const dateStr = record.recorded_at.split('T')[0]
            return dateStr >= startStr && dateStr <= endStr
          })
          .map((record) => record.recorded_at.split('T')[0])
      )
      const exerciseRate =
        Math.round((exerciseDates.size / daysInPeriod) * 100 * 10) / 10

      // 体重進捗率の計算
      let weightProgress: number | null = null

      const hasTargetWeight = targetWeight !== 0
      const hasInitialWeight = initialWeight !== null

      if (hasTargetWeight && hasInitialWeight && initialWeight !== targetWeight) {
        // 期間内の最新体重記録を取得
        const periodWeightRecords = weightRecords
          .filter((record) => {
            const dateStr = record.recorded_at.split('T')[0]
            return dateStr >= startStr && dateStr <= endStr
          })
          .sort(
            (a, b) =>
              new Date(b.recorded_at).getTime() -
              new Date(a.recorded_at).getTime()
          )

        if (periodWeightRecords.length > 0) {
          const currentWeight = periodWeightRecords[0].weight
          const rawProgress =
            ((initialWeight - currentWeight) /
              (initialWeight - targetWeight)) *
            100
          // 0〜100 にクランプして小数第1位に丸める
          weightProgress =
            Math.round(Math.min(100, Math.max(0, rawProgress)) * 10) / 10
          lastWeightProgress = weightProgress
        } else {
          // 期間内に記録がなければ前の期間の値を引き継ぐ（初期値は0%）
          weightProgress = lastWeightProgress ?? 0
        }
      }

      // 総合スコアの計算
      let totalScore: number
      if (hasTargetWeight && weightProgress !== null) {
        // 体重あり: 体重0.4 + 食事0.3 + 運動0.3
        totalScore =
          Math.round(
            (weightProgress * 0.4 + mealRate * 0.3 + exerciseRate * 0.3) * 10
          ) / 10
      } else {
        // 体重null: 食事0.6 + 運動0.4
        totalScore =
          Math.round((mealRate * 0.6 + exerciseRate * 0.4) * 10) / 10
      }

      return {
        label,
        weightProgress,
        mealRate,
        exerciseRate,
        totalScore,
      }
    })
  }, [
    viewMode,
    weightRecords,
    mealRecords,
    exerciseRecords,
    startDate,
    endDate,
    targetWeight,
    initialWeight,
  ])

  const hasData = chartData.length > 0

  return (
    <Card className="border border-[#E2E8F0] rounded-md" style={{ boxShadow: 'none' }}>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="text-[#0F172A]">目標達成率推移</CardTitle>
          <div className="inline-flex rounded-md border border-[#E2E8F0] p-1" data-pdf-hide>
            <button
              type="button"
              onClick={() => setViewMode('weekly')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                viewMode === 'weekly'
                  ? 'bg-[#14B8A6] text-white'
                  : 'bg-[#F8FAFC] text-[#64748B] hover:text-[#475569]'
              }`}
            >
              週次
            </button>
            <button
              type="button"
              onClick={() => setViewMode('monthly')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                viewMode === 'monthly'
                  ? 'bg-[#14B8A6] text-white'
                  : 'bg-[#F8FAFC] text-[#64748B] hover:text-[#475569]'
              }`}
            >
              月次
            </button>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {hasData ? (
          <ResponsiveContainer width="100%" height={300}>
            <LineChart
              data={chartData}
              margin={{ top: 5, right: 20, left: 0, bottom: 5 }}
            >
              <CartesianGrid strokeDasharray="3 3" stroke="#E2E8F0" />
              <XAxis dataKey="label" tick={{ fontSize: 12, fill: '#94A3B8' }} />
              <YAxis
                domain={[0, 100]}
                unit="%"
                tick={{ fontSize: 12, fill: '#94A3B8' }}
                width={45}
              />
              <Tooltip
                formatter={(value, name) => {
                  if (value == null) return ['--', name]
                  return [`${value}%`, name]
                }}
                contentStyle={{
                  backgroundColor: '#FFFFFF',
                  border: '1px solid #E2E8F0',
                  borderRadius: '6px',
                  boxShadow: 'none',
                }}
              />
              <Legend />
              {targetWeight !== 0 && (
                <Line
                  type="monotone"
                  dataKey="weightProgress"
                  stroke="#2563EB"
                  name="体重進捗"
                  dot={{ r: 4 }}
                  connectNulls={true}
                />
              )}
              <Line
                type="monotone"
                dataKey="mealRate"
                stroke="#EA580C"
                name="食事記録"
                dot={{ r: 4 }}
                connectNulls={true}
              />
              <Line
                type="monotone"
                dataKey="exerciseRate"
                stroke="#16A34A"
                name="運動記録"
                dot={{ r: 4 }}
                connectNulls={true}
              />
              <Line
                type="monotone"
                dataKey="totalScore"
                stroke="#14B8A6"
                strokeWidth={3}
                name="総合スコア"
                dot={{ r: 4 }}
                connectNulls={true}
              />
            </LineChart>
          </ResponsiveContainer>
        ) : (
          <div className="flex items-center justify-center h-[300px]">
            <p className="text-[#94A3B8] text-sm">データがありません</p>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
