'use client'

import { useMemo, useState } from 'react'
import { format, subMonths, startOfWeek, startOfMonth } from 'date-fns'
import {
  ResponsiveContainer,
  LineChart,
  Line,
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
}

type PeriodFilter = 'week' | 'month' | '3months' | 'all'

export function WeightChart({ weightRecords, targetWeight }: WeightChartProps) {
  const [periodFilter, setPeriodFilter] = useState<PeriodFilter>('all')

  // フィルター後のデータを計算
  const filteredData = useMemo(() => {
    if (weightRecords.length === 0) return []

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
  }, [weightRecords, periodFilter])

  // Y軸のドメインを計算
  const yAxisDomain = useMemo(() => {
    if (filteredData.length === 0) return [0, 100]

    const weights = filteredData.map((d) => d.weight)
    const dataMin = Math.min(...weights)
    const dataMax = Math.max(...weights)

    return [Math.floor(dataMin - 2), Math.ceil(dataMax + 2)]
  }, [filteredData])

  // 期間フィルターボタン
  const periodButtons: { label: string; value: PeriodFilter }[] = [
    { label: '今週', value: 'week' },
    { label: '今月', value: 'month' },
    { label: '3ヶ月', value: '3months' },
    { label: '全期間', value: 'all' },
  ]

  return (
    <div className="space-y-4">
      {/* 期間フィルター */}
      <div className="flex justify-end">
        <div className="flex space-x-2">
          {periodButtons.map((button) => (
            <button
              key={button.value}
              onClick={() => setPeriodFilter(button.value)}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                periodFilter === button.value
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {button.label}
            </button>
          ))}
        </div>
      </div>

      {/* グラフ */}
      {filteredData.length === 0 ? (
        <div className="flex items-center justify-center h-[300px] bg-gray-50 rounded-lg">
          <p className="text-gray-500">選択した期間にデータがありません</p>
        </div>
      ) : (
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={filteredData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
            <XAxis
              dataKey="date"
              tickFormatter={(date: Date) => format(date, 'M/d')}
              stroke="#9ca3af"
              style={{ fontSize: '12px' }}
            />
            <YAxis
              domain={yAxisDomain}
              stroke="#9ca3af"
              style={{ fontSize: '12px' }}
              label={{ value: '体重 (kg)', angle: -90, position: 'insideLeft', style: { fontSize: '12px' } }}
            />
            <Tooltip
              labelFormatter={(label) => format(label as Date, 'yyyy年M月d日')}
              formatter={(value) => [`${value} kg`, '体重']}
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
            <Line
              type="monotone"
              dataKey="weight"
              stroke="#3b82f6"
              strokeWidth={2}
              dot={{ fill: '#3b82f6', r: 4 }}
              activeDot={{ r: 6 }}
            />
          </LineChart>
        </ResponsiveContainer>
      )}
    </div>
  )
}
