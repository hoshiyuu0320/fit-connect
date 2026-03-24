'use client'

import { useMemo, useState } from 'react'
import { format, subMonths, startOfWeek, startOfMonth } from 'date-fns'
import {
  ResponsiveContainer,
  ComposedChart,
  Line,
  Area,
  CartesianGrid,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceLine,
} from 'recharts'
import type { WeightRecord } from '@/types/client'

interface WeightChartProps {
  weightRecords: WeightRecord[]
  targetWeight: number
  showPeriodFilter?: boolean
  prediction?: {
    monthlyChange: number
    predictedWeight: number
    periodDays: number
  }
}

type PeriodFilter = 'week' | 'month' | '3months' | 'all'

export function WeightChart({ weightRecords, targetWeight, showPeriodFilter = true, prediction }: WeightChartProps) {
  const [periodFilter, setPeriodFilter] = useState<PeriodFilter>('all')

  // フィルター後のデータを計算
  const filteredData = useMemo(() => {
    if (weightRecords.length === 0) return []

    // showPeriodFilter=false の場合は親がフィルター済みなので全データ表示
    if (!showPeriodFilter) {
      return weightRecords
        .sort((a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime())
        .map((record) => ({
          date: new Date(record.recorded_at),
          weight: record.weight,
        }))
    }

    const now = new Date()
    let startDate: Date

    switch (periodFilter) {
      case 'week':
        startDate = startOfWeek(now, { weekStartsOn: 1 }) // 月曜始まり
        break
      case 'month':
        startDate = startOfMonth(now)
        break
      case '3months':
        startDate = subMonths(now, 3)
        break
      case 'all':
      default:
        startDate = new Date(0) // 全期間
        break
    }

    return weightRecords
      .filter((record) => new Date(record.recorded_at) >= startDate)
      .sort((a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime())
      .map((record) => ({
        date: new Date(record.recorded_at),
        weight: record.weight,
      }))
  }, [weightRecords, periodFilter, showPeriodFilter])

  // 予測データを生成
  const predictionData = useMemo(() => {
    if (!prediction || filteredData.length === 0) return []

    const lastPoint = filteredData[filteredData.length - 1]
    const lastWeight = lastPoint.weight
    const lastDate = lastPoint.date.getTime()
    const dailyChange = prediction.monthlyChange / 30

    // 7つの未来データポイントを生成
    const points = []
    const totalFutureDays = Math.min(prediction.periodDays, 90)
    const interval = Math.max(Math.floor(totalFutureDays / 6), 1)

    for (let i = 0; i <= 6; i++) {
      const daysAhead = i === 0 ? 0 : Math.min(i * interval, totalFutureDays)
      const futureDate = new Date(lastDate + daysAhead * 24 * 60 * 60 * 1000)
      const futureWeight = Math.round((lastWeight + dailyChange * daysAhead) * 10) / 10

      points.push({
        date: futureDate,
        predictionWeight: futureWeight,
      })
    }

    return points
  }, [prediction, filteredData])

  // 実データと予測データをマージ
  const chartData = useMemo(() => {
    if (predictionData.length === 0) return filteredData

    // 実データ
    const actual = filteredData.map((d) => ({
      date: d.date,
      weight: d.weight,
      predictionWeight: undefined as number | undefined,
    }))

    // 最後の実データポイントに予測の開始点を追加
    if (actual.length > 0) {
      actual[actual.length - 1].predictionWeight = actual[actual.length - 1].weight
    }

    // 予測データ（最初のポイントは実データと重複するのでスキップ）
    const future = predictionData.slice(1).map((d) => ({
      date: d.date,
      weight: undefined as number | undefined,
      predictionWeight: d.predictionWeight,
    }))

    return [...actual, ...future]
  }, [filteredData, predictionData])

  // Y軸のドメインを計算
  const yAxisDomain = useMemo(() => {
    if (filteredData.length === 0) return [0, 100]

    const weights = filteredData.map((d) => d.weight)
    const dataMin = Math.min(...weights)
    const dataMax = Math.max(...weights)

    return [Math.floor(dataMin - 2), Math.ceil(dataMax + 2)]
  }, [filteredData])

  // 予測を含むY軸ドメイン
  const adjustedYDomain = useMemo(() => {
    if (predictionData.length === 0) return yAxisDomain

    const allWeights = [
      ...filteredData.map((d) => d.weight),
      ...predictionData.map((d) => d.predictionWeight),
    ]
    const dataMin = Math.min(...allWeights)
    const dataMax = Math.max(...allWeights)

    return [Math.floor(dataMin - 2), Math.ceil(dataMax + 2)]
  }, [filteredData, predictionData, yAxisDomain])

  // 期間フィルターボタン
  const periodButtons: { label: string; value: PeriodFilter }[] = [
    { label: '今週', value: 'week' },
    { label: '今月', value: 'month' },
    { label: '3ヶ月', value: '3months' },
    { label: '全期間', value: 'all' },
  ]

  const activeDomain = prediction ? adjustedYDomain : yAxisDomain

  return (
    <div className="space-y-4">
      {/* 期間フィルター */}
      {showPeriodFilter && (
        <div className="flex justify-end" data-pdf-hide>
          <div className="flex bg-gray-100 rounded-lg p-0.5">
            {periodButtons.map((button) => (
              <button
                key={button.value}
                onClick={() => setPeriodFilter(button.value)}
                className={`px-3 py-1 text-xs font-medium rounded-md transition-colors ${
                  periodFilter === button.value
                    ? 'bg-white text-gray-900 shadow-sm'
                    : 'text-gray-500 hover:text-gray-700'
                }`}
              >
                {button.label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* グラフ */}
      {filteredData.length === 0 ? (
        <div className="flex items-center justify-center h-[300px] bg-gray-50 rounded-lg">
          <p className="text-gray-500">選択した期間にデータがありません</p>
        </div>
      ) : (
        <ResponsiveContainer width="100%" height={300}>
          <ComposedChart data={chartData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
            <XAxis
              dataKey="date"
              tickFormatter={(date: Date) => format(date, 'M/d')}
              stroke="#9ca3af"
              style={{ fontSize: '12px' }}
            />
            <YAxis
              domain={activeDomain}
              stroke="#9ca3af"
              style={{ fontSize: '12px' }}
              label={{ value: '体重 (kg)', angle: -90, position: 'insideLeft', style: { fontSize: '12px' } }}
            />
            <Tooltip
              labelFormatter={(label) => {
                if (label instanceof Date) return format(label, 'yyyy年M月d日')
                return String(label)
              }}
              formatter={(value, name) => {
                if (value === undefined || value === null) return ['-', '']
                if (name === 'predictionWeight') return [`${value} kg`, '予測']
                return [`${value} kg`, '体重']
              }}
              contentStyle={{
                backgroundColor: 'white',
                border: '1px solid #e5e7eb',
                borderRadius: '6px',
                fontSize: '12px',
              }}
            />
            {targetWeight && (
              <ReferenceLine
                y={targetWeight}
                stroke="#ef4444"
                strokeDasharray="5 5"
                label={{ value: '目標', position: 'insideTopRight', fill: '#ef4444', fontSize: 12 }}
              />
            )}
            {/* 予測エリア（塗り） */}
            {prediction && (
              <Area
                type="monotone"
                dataKey="predictionWeight"
                fill="#14B8A6"
                fillOpacity={0.1}
                stroke="none"
                connectNulls={false}
              />
            )}
            {/* 予測ライン（破線） */}
            {prediction && (
              <Line
                type="monotone"
                dataKey="predictionWeight"
                stroke="#14B8A6"
                strokeWidth={2}
                strokeDasharray="6 4"
                dot={false}
                connectNulls={false}
              />
            )}
            {/* 実データライン */}
            <Line
              type="monotone"
              dataKey="weight"
              stroke="#3b82f6"
              strokeWidth={2}
              dot={{ fill: '#3b82f6', r: 4 }}
              activeDot={{ r: 6 }}
              connectNulls={false}
            />
          </ComposedChart>
        </ResponsiveContainer>
      )}
    </div>
  )
}
