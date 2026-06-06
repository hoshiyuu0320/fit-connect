'use client'

import { useMemo } from 'react'
import { Cell, Pie, PieChart, ResponsiveContainer } from 'recharts'
import { PieChart as PieChartIcon } from 'lucide-react'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'
import {
  computePfcBalance,
  DEFAULT_PFC_TARGETS,
  type MacroKey,
  type MacroStatus,
  type PfcTargets,
} from '@/lib/nutrition/pfcBalance'
import { usePrefersReducedMotion } from '@/hooks/usePrefersReducedMotion'

interface PfcBalanceCardProps {
  data: DailyNutritionPoint[]
  targets?: PfcTargets
}

const MACRO_META: Record<MacroKey, { label: string; color: string }> = {
  protein: { label: 'たんぱく質', color: '#6366F1' },
  fat: { label: '脂質', color: '#E6B968' },
  carbs: { label: '炭水化物', color: '#E294AE' },
}

const STATUS_META: Record<MacroStatus, { label: string; color: string }> = {
  low: { label: '不足', color: '#2563EB' },
  optimal: { label: '適正', color: '#16A34A' },
  high: { label: '過剰', color: '#EA580C' },
}

const ZONE_COLOR = '#C2E6A8'
const TARGET_LINE = '#2F7D33'

function EmptyState() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <PieChartIcon className="w-10 h-10 text-slate-400 mb-3" />
      <p className="font-semibold text-slate-900">データがありません</p>
      <p className="text-sm text-slate-600 mt-1">選択期間に食事の記録がありません</p>
    </div>
  )
}

export function PfcBalanceCard({ data, targets = DEFAULT_PFC_TARGETS }: PfcBalanceCardProps) {
  const reducedMotion = usePrefersReducedMotion()
  const balance = useMemo(() => computePfcBalance(data, targets), [data, targets])

  if (!balance.hasData) return <EmptyState />

  // バーのx軸上限（%）。目安レンジの上限から動的に算出し、
  // 将来クライアント別の目標（targets.hi が高い値）でもバーがはみ出さないようにする。
  const scaleMax = Math.max(60, ...balance.macros.map((m) => m.target.hi)) + 5

  const donutData = balance.macros.map((m) => ({
    key: m.key,
    value: m.ratio,
    color: MACRO_META[m.key].color,
  }))

  return (
    <div className="flex flex-wrap items-center gap-7">
      {/* ドーナツ */}
      <div className="relative" style={{ width: 160, height: 160 }}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={donutData}
              dataKey="value"
              nameKey="key"
              cx="50%"
              cy="50%"
              innerRadius={46}
              outerRadius={72}
              startAngle={90}
              endAngle={-270}
              stroke="none"
              isAnimationActive={!reducedMotion}
            >
              {donutData.map((d) => (
                <Cell key={d.key} fill={d.color} />
              ))}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span className="text-lg font-bold text-slate-900 leading-none">
            {balance.avgCaloriesPerDay.toLocaleString()}
          </span>
          <span className="text-[10px] text-slate-600 mt-1">kcal/日 平均</span>
        </div>
      </div>

      {/* あすけん風 目安バー */}
      <div className="flex-1 min-w-[320px]">
        {balance.macros.map((m) => {
          const meta = MACRO_META[m.key]
          const status = STATUS_META[m.status]
          const actW = Math.min(100, (m.ratio / scaleMax) * 100)
          const mid = (m.target.lo + m.target.hi) / 2
          const midL = (mid / scaleMax) * 100
          const zoneL = (m.target.lo / scaleMax) * 100
          const zoneW = ((m.target.hi - m.target.lo) / scaleMax) * 100
          return (
            <div key={m.key} className="mb-4 last:mb-0">
              <div className="flex items-center gap-2 mb-1.5">
                <span className="text-sm text-slate-700 w-20">{meta.label}</span>
                <span
                  className="text-[11px] font-bold text-white rounded px-1.5 py-px"
                  style={{ backgroundColor: status.color }}
                >
                  {status.label}
                </span>
                <span className="ml-auto text-sm font-bold text-slate-900">
                  {Math.round(m.ratio)}%
                </span>
                <span className="text-[11px] text-slate-600 w-11 text-right">{m.grams}g</span>
              </div>
              <div className="relative h-[18px] bg-slate-100 rounded">
                {/* 適正ゾーン */}
                <div
                  className="absolute top-0 bottom-0 rounded-sm"
                  style={{ left: `${zoneL}%`, width: `${zoneW}%`, backgroundColor: ZONE_COLOR }}
                />
                {/* 目標値の縦線 + ▼マーカー */}
                <div
                  className="absolute"
                  style={{
                    left: `${midL}%`,
                    top: -3,
                    height: 24,
                    width: 3,
                    backgroundColor: TARGET_LINE,
                    transform: 'translateX(-50%)',
                  }}
                />
                <div
                  className="absolute text-[9px] leading-none"
                  style={{ left: `${midL}%`, top: -7, transform: 'translateX(-50%)', color: TARGET_LINE }}
                >
                  ▼
                </div>
                {/* 実測バー */}
                <div
                  className="absolute rounded-sm"
                  style={{ left: 0, width: `${actW}%`, top: 4, bottom: 4, backgroundColor: meta.color }}
                />
              </div>
              <div className="text-[10px] text-slate-600 mt-1">
                適正 {m.target.lo}–{m.target.hi}%
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
