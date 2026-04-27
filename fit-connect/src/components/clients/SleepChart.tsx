'use client'

import { useMemo } from 'react'
import { format, parseISO } from 'date-fns'
import {
  ResponsiveContainer,
  ComposedChart,
  Line,
  CartesianGrid,
  XAxis,
  YAxis,
  Tooltip,
  ReferenceArea,
} from 'recharts'
import type { SleepRecord } from '@/types/client'
import { WAKEUP_RATING_OPTIONS, SLEEP_SOURCE_LABELS } from '@/types/client'

interface SleepChartProps {
  sleepRecords: SleepRecord[]
}

// グラフ描画用に整形した1日分の睡眠データ
type SleepChartDatum = {
  date: Date
  totalHours: number              // 総睡眠時間（h）— Lineの dataKey
  totalMinutes: number            // 総睡眠時間（m）— ツールチップで時/分に分解
  deepMinutes: number | null
  lightMinutes: number | null
  remMinutes: number | null
  awakeMinutes: number | null
  wakeupRating: 1 | 2 | 3 | null
  source: SleepRecord['source']
}

export function SleepChart({ sleepRecords }: SleepChartProps) {
  // recorded_date と total_sleep_minutes が両方ある記録のみを採用し、日付昇順にソート
  const chartData = useMemo<SleepChartDatum[]>(() => {
    if (sleepRecords.length === 0) return []

    return sleepRecords
      .filter((record) => record.recorded_date && record.total_sleep_minutes !== null)
      .sort(
        (a, b) =>
          new Date(a.recorded_date).getTime() - new Date(b.recorded_date).getTime()
      )
      .map((record) => {
        // total_sleep_minutes は filter で null 除外済みだが TS 的に narrow するため再代入
        const totalMinutes = record.total_sleep_minutes as number
        return {
          date: parseISO(record.recorded_date),
          // h 単位は小数第1位までに丸めて Y軸メモリと整合させる
          totalHours: Math.round((totalMinutes / 60) * 10) / 10,
          totalMinutes,
          deepMinutes: record.deep_minutes,
          lightMinutes: record.light_minutes,
          remMinutes: record.rem_minutes,
          awakeMinutes: record.awake_minutes,
          wakeupRating: record.wakeup_rating,
          source: record.source,
        }
      })
  }, [sleepRecords])

  // データが0件、または客観的な総睡眠時間が全て null の場合は空状態を表示
  if (chartData.length === 0) {
    return (
      <div className="flex items-center justify-center h-[300px] bg-gray-50 rounded-lg">
        <p className="text-gray-500">客観的な睡眠データがありません</p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <ResponsiveContainer width="100%" height={300}>
        <ComposedChart data={chartData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#E2E8F0" />
          <XAxis
            dataKey="date"
            tickFormatter={(date: Date) => format(date, 'M/d')}
            stroke="#94A3B8"
            style={{ fontSize: '12px' }}
          />
          <YAxis
            domain={[0, 12]}
            ticks={[0, 3, 6, 9, 12]}
            stroke="#94A3B8"
            style={{ fontSize: '12px' }}
            label={{
              value: '睡眠時間 (h)',
              angle: -90,
              position: 'insideLeft',
              style: { fontSize: '12px', fill: '#0F172A' },
            }}
          />
          {/* 推奨睡眠帯 7h〜9h を薄くハイライト */}
          <ReferenceArea
            y1={7}
            y2={9}
            fill="#14B8A6"
            fillOpacity={0.08}
            stroke="none"
          />
          <Tooltip content={<SleepTooltip />} />
          {/* 総睡眠時間（折れ線） */}
          <Line
            type="monotone"
            dataKey="totalHours"
            stroke="#14B8A6"
            strokeWidth={2}
            dot={{ fill: '#14B8A6', r: 4 }}
            activeDot={{ r: 6 }}
            connectNulls={false}
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}

type SleepTooltipProps = {
  active?: boolean
  payload?: Array<{ payload: SleepChartDatum }>
}

// カスタムツールチップ — 日付・総睡眠（h, m）・各ステージ分・目覚め評価・ソースを表示
function SleepTooltip({ active, payload }: SleepTooltipProps) {
  if (!active || !payload || payload.length === 0) return null

  const datum = payload[0]?.payload
  if (!datum) return null

  // 総睡眠時間を「Xh Ym」形式に分解
  const totalHours = Math.floor(datum.totalMinutes / 60)
  const totalRemainder = datum.totalMinutes % 60

  const wakeupLabel =
    datum.wakeupRating !== null ? WAKEUP_RATING_OPTIONS[datum.wakeupRating] : '-'
  const sourceLabel = SLEEP_SOURCE_LABELS[datum.source]

  return (
    <div
      className="bg-white border border-[#E2E8F0] rounded-md px-3 py-2 text-xs"
      style={{ color: '#0F172A' }}
    >
      <div className="font-medium mb-1">{format(datum.date, 'yyyy年M月d日')}</div>
      <div>
        総睡眠: <span className="font-medium">{totalHours}h {totalRemainder}m</span>
      </div>
      <div className="mt-1 space-y-0.5 text-[#475569]">
        <div>深い: {datum.deepMinutes !== null ? `${datum.deepMinutes}m` : '-'}</div>
        <div>レム: {datum.remMinutes !== null ? `${datum.remMinutes}m` : '-'}</div>
        <div>浅い: {datum.lightMinutes !== null ? `${datum.lightMinutes}m` : '-'}</div>
        <div>覚醒: {datum.awakeMinutes !== null ? `${datum.awakeMinutes}m` : '-'}</div>
      </div>
      <div className="mt-1 pt-1 border-t border-[#E2E8F0] text-[#475569]">
        <div>目覚め: {wakeupLabel}</div>
        <div>ソース: {sourceLabel}</div>
      </div>
    </div>
  )
}
