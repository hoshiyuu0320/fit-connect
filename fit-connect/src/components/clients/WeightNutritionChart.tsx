'use client'

import { useMemo } from 'react'
import { format, parseISO } from 'date-fns'
import { LineChart as LineChartIcon } from 'lucide-react'
import {
  Area,
  Bar,
  CartesianGrid,
  ComposedChart,
  Legend,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'
import { usePrefersReducedMotion } from '@/hooks/usePrefersReducedMotion'

interface WeightNutritionChartProps {
  data: DailyNutritionPoint[]
  targetWeight: number
  loading?: boolean
}

const COLORS = {
  protein: '#6366F1',
  fat: '#E6B968',
  carbs: '#E294AE',
  weight: '#3B82F6',
  weightArea: 'rgba(59, 130, 246, 0.10)',
  target: '#22C55E',
  grid: '#E2E8F0',
  axis: '#64748B',
} as const

const KCAL = { protein: 4, fat: 9, carbs: 4 } as const

type ChartRow = DailyNutritionPoint & {
  proteinKcal: number
  fatKcal: number
  carbsKcal: number
}

type TooltipPayloadItem = { payload?: ChartRow }
interface ChartTooltipProps {
  active?: boolean
  payload?: TooltipPayloadItem[]
  label?: string
}

function ChartTooltip({ active, payload, label }: ChartTooltipProps) {
  if (!active || !payload || payload.length === 0 || !label) return null
  const point = payload[0]?.payload
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
          <span className="text-slate-600">体重</span>
          <span className="font-medium text-slate-900">
            {point.weight !== null ? `${point.weight} kg` : '—'}
          </span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span className="text-slate-600">摂取カロリー</span>
          <span className="font-medium text-slate-900">{point.calories.toLocaleString()} kcal</span>
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
      <p className="text-sm text-slate-600 mt-1">選択期間に記録された体重・食事がありません</p>
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

export function WeightNutritionChart({ data, targetWeight, loading = false }: WeightNutritionChartProps) {
  const reducedMotion = usePrefersReducedMotion()

  const chartData = useMemo<ChartRow[]>(
    () =>
      data.map((d) => ({
        ...d,
        proteinKcal: Math.round(d.protein * KCAL.protein),
        fatKcal: Math.round(d.fat * KCAL.fat),
        carbsKcal: Math.round(d.carbs * KCAL.carbs),
      })),
    [data]
  )

  const weightDomain = useMemo<[number, number]>(() => {
    const weights = data
      .map((d) => d.weight)
      .filter((w): w is number => w !== null)
    const all = targetWeight ? [...weights, targetWeight] : weights
    if (all.length === 0) return [0, 100]
    return [Math.floor(Math.min(...all) - 2), Math.ceil(Math.max(...all) + 2)]
  }, [data, targetWeight])

  if (loading) return <LoadingState />
  if (data.length === 0) return <EmptyState />

  const xTickFormatter = (value: string) => {
    try {
      return format(parseISO(value), 'M/d')
    } catch {
      return value
    }
  }

  return (
    <ResponsiveContainer width="100%" height={320}>
      <ComposedChart data={chartData} margin={{ top: 16, right: 8, left: 0, bottom: 8 }}>
        <CartesianGrid stroke={COLORS.grid} strokeDasharray="3 3" vertical={false} />
        <XAxis
          dataKey="date"
          tickFormatter={xTickFormatter}
          tick={{ fill: COLORS.axis, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
        />
        {/* 左軸: 体重 kg（主役） */}
        <YAxis
          yAxisId="weight"
          domain={weightDomain}
          tick={{ fill: COLORS.weight, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
          label={{
            value: '体重 kg',
            angle: -90,
            position: 'insideLeft',
            style: { fill: COLORS.weight, fontSize: 11, textAnchor: 'middle' },
          }}
        />
        {/* 右軸: 摂取 kcal（補助） */}
        <YAxis
          yAxisId="kcal"
          orientation="right"
          tick={{ fill: COLORS.axis, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
          label={{
            value: '摂取 kcal',
            angle: 90,
            position: 'insideRight',
            style: { fill: COLORS.axis, fontSize: 11, textAnchor: 'middle' },
          }}
        />
        <Tooltip content={<ChartTooltip />} cursor={{ fill: 'rgba(15, 23, 42, 0.04)' }} />
        <Legend
          align="right"
          verticalAlign="top"
          iconType="circle"
          wrapperStyle={{ fontSize: 12, color: COLORS.axis, paddingBottom: 8 }}
        />
        {/* PFC 積み上げ棒（kcal換算・背面・淡色） */}
        <Bar
          yAxisId="kcal"
          dataKey="proteinKcal"
          name="P (kcal)"
          stackId="pfc"
          fill={COLORS.protein}
          fillOpacity={0.55}
          maxBarSize={24}
          isAnimationActive={!reducedMotion}
        />
        <Bar
          yAxisId="kcal"
          dataKey="fatKcal"
          name="F (kcal)"
          stackId="pfc"
          fill={COLORS.fat}
          fillOpacity={0.55}
          maxBarSize={24}
          isAnimationActive={!reducedMotion}
        />
        <Bar
          yAxisId="kcal"
          dataKey="carbsKcal"
          name="C (kcal)"
          stackId="pfc"
          fill={COLORS.carbs}
          fillOpacity={0.55}
          radius={[3, 3, 0, 0]}
          maxBarSize={24}
          isAnimationActive={!reducedMotion}
        />
        {/* 目標体重ライン */}
        {targetWeight ? (
          <ReferenceLine
            yAxisId="weight"
            y={targetWeight}
            stroke={COLORS.target}
            strokeDasharray="5 4"
            label={{ value: `目標 ${targetWeight}kg`, position: 'insideTopLeft', fill: '#16A34A', fontSize: 10 }}
          />
        ) : null}
        {/* 体重エリア（淡い塗り・前面） */}
        <Area
          yAxisId="weight"
          type="monotone"
          dataKey="weight"
          fill={COLORS.weightArea}
          stroke="none"
          connectNulls
          legendType="none"
          isAnimationActive={!reducedMotion}
        />
        {/* 体重ライン（主役） */}
        <Line
          yAxisId="weight"
          type="monotone"
          dataKey="weight"
          name="体重 (kg)"
          stroke={COLORS.weight}
          strokeWidth={2.5}
          dot={{ r: 3, fill: '#fff', stroke: COLORS.weight, strokeWidth: 2 }}
          activeDot={{ r: 5 }}
          connectNulls
          isAnimationActive={!reducedMotion}
        />
      </ComposedChart>
    </ResponsiveContainer>
  )
}
