'use client'

import { format, parseISO } from 'date-fns'
import { LineChart as LineChartIcon } from 'lucide-react'
import {
  Bar,
  CartesianGrid,
  ComposedChart,
  Legend,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'

interface NutritionTrendChartProps {
  data: DailyNutritionPoint[]
  loading?: boolean
}

const COLORS = {
  protein: '#0D9488',
  fat: '#F59E0B',
  carbs: '#6366F1',
  weight: '#0F172A',
  grid: '#E2E8F0',
  axis: '#64748B',
} as const

type TooltipPayloadItem = {
  dataKey?: string | number
  value?: number | string
  payload?: DailyNutritionPoint
}

interface NutritionTooltipProps {
  active?: boolean
  payload?: TooltipPayloadItem[]
  label?: string
}

function NutritionTooltip({ active, payload, label }: NutritionTooltipProps) {
  if (!active || !payload || payload.length === 0 || !label) return null

  const point = payload[0]?.payload as DailyNutritionPoint | undefined
  if (!point) return null

  const formattedDate = (() => {
    try {
      return format(parseISO(label), 'yyyy年M月d日')
    } catch {
      return label
    }
  })()

  return (
    <div className="bg-white border border-slate-200 rounded-md p-3 text-xs shadow-sm">
      <div className="font-semibold text-slate-900 mb-1.5">{formattedDate}</div>
      <div className="space-y-0.5">
        <div className="flex items-center justify-between gap-4">
          <span className="text-slate-500">体重</span>
          <span className="font-medium text-slate-900">
            {point.weight !== null ? `${point.weight} kg` : '—'}
          </span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span className="text-slate-500">カロリー</span>
          <span className="font-medium text-slate-900">
            {point.calories.toLocaleString()} kcal
          </span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span style={{ color: COLORS.protein }}>P タンパク質</span>
          <span className="font-medium text-slate-900">{point.protein} g</span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span style={{ color: COLORS.fat }}>F 脂質</span>
          <span className="font-medium text-slate-900">{point.fat} g</span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span style={{ color: COLORS.carbs }}>C 炭水化物</span>
          <span className="font-medium text-slate-900">{point.carbs} g</span>
        </div>
      </div>
    </div>
  )
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      <LineChartIcon className="w-12 h-12 text-slate-400 mb-3" />
      <p className="font-semibold text-slate-900">データがありません</p>
      <p className="text-sm text-slate-500 mt-1">
        選択期間に記録された体重・食事がありません
      </p>
    </div>
  )
}

function LoadingState() {
  return (
    <div className="flex items-center justify-center h-[320px]">
      <div className="w-full h-full bg-slate-50 rounded-md animate-pulse" />
    </div>
  )
}

export function NutritionTrendChart({ data, loading = false }: NutritionTrendChartProps) {
  if (loading) {
    return <LoadingState />
  }

  if (data.length === 0) {
    return <EmptyState />
  }

  const xTickFormatter = (value: string) => {
    try {
      return format(parseISO(value), 'M/d')
    } catch {
      return value
    }
  }

  return (
    <ResponsiveContainer width="100%" height={320}>
      <ComposedChart
        data={data}
        margin={{ top: 16, right: 16, left: 0, bottom: 8 }}
      >
        <CartesianGrid
          stroke={COLORS.grid}
          strokeDasharray="3 3"
          vertical={false}
        />
        <XAxis
          dataKey="date"
          tickFormatter={xTickFormatter}
          tick={{ fill: COLORS.axis, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
        />
        <YAxis
          yAxisId="left"
          tick={{ fill: COLORS.axis, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
          label={{
            value: 'kcal / g',
            angle: -90,
            position: 'insideLeft',
            style: { fill: COLORS.axis, fontSize: 11, textAnchor: 'middle' },
          }}
        />
        <YAxis
          yAxisId="right"
          orientation="right"
          tick={{ fill: COLORS.axis, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
          label={{
            value: 'kg',
            angle: 90,
            position: 'insideRight',
            style: { fill: COLORS.axis, fontSize: 11, textAnchor: 'middle' },
          }}
        />
        <Tooltip content={<NutritionTooltip />} cursor={{ fill: 'rgba(15, 23, 42, 0.04)' }} />
        <Legend
          align="right"
          verticalAlign="top"
          iconType="circle"
          wrapperStyle={{ fontSize: 12, color: COLORS.axis, paddingBottom: 8 }}
        />
        <Bar
          yAxisId="left"
          dataKey="protein"
          name="タンパク質 (g)"
          stackId="pfc"
          fill={COLORS.protein}
          radius={[0, 0, 0, 0]}
          maxBarSize={28}
        />
        <Bar
          yAxisId="left"
          dataKey="fat"
          name="脂質 (g)"
          stackId="pfc"
          fill={COLORS.fat}
          radius={[0, 0, 0, 0]}
          maxBarSize={28}
        />
        <Bar
          yAxisId="left"
          dataKey="carbs"
          name="炭水化物 (g)"
          stackId="pfc"
          fill={COLORS.carbs}
          radius={[4, 4, 0, 0]}
          maxBarSize={28}
        />
        <Line
          yAxisId="right"
          type="monotone"
          dataKey="weight"
          name="体重 (kg)"
          stroke={COLORS.weight}
          strokeWidth={2}
          dot={{ r: 3, fill: COLORS.weight }}
          activeDot={{ r: 5 }}
          connectNulls
        />
      </ComposedChart>
    </ResponsiveContainer>
  )
}
