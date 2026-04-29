'use client'

import { useState, useMemo } from 'react'
import { format, parseISO } from 'date-fns'
import { SleepChart } from '@/components/clients/SleepChart'
import type { SleepRecord } from '@/types/client'
import { WAKEUP_RATING_OPTIONS, SLEEP_SOURCE_LABELS } from '@/types/client'

interface SleepTabProps {
  sleepRecords: SleepRecord[]
}

type SleepPeriod = '1W' | '1M' | '3M' | 'ALL'

const SLEEP_PERIOD_BUTTONS: { value: SleepPeriod; label: string }[] = [
  { value: '1W', label: '1W' },
  { value: '1M', label: '1M' },
  { value: '3M', label: '3M' },
  { value: 'ALL', label: 'ALL' },
]

export function SleepTab({ sleepRecords }: SleepTabProps) {
  const [sleepPeriod, setSleepPeriod] = useState<SleepPeriod>('1M')

  const filteredRecords = useMemo(() => {
    const now = new Date()
    let startDate: Date
    switch (sleepPeriod) {
      case '1W':
        startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
        break
      case '1M':
        startDate = new Date(now.getFullYear(), now.getMonth() - 1, now.getDate())
        break
      case '3M':
        startDate = new Date(now.getFullYear(), now.getMonth() - 3, now.getDate())
        break
      case 'ALL':
      default:
        return sleepRecords
    }
    return sleepRecords.filter((r) => parseISO(r.recorded_date) >= startDate)
  }, [sleepRecords, sleepPeriod])

  const sleepStats = useMemo(() => {
    // 平均睡眠時間 — total_sleep_minutes が非nullのレコードのみ
    const totalSleepRecords = filteredRecords.filter(
      (r) => r.total_sleep_minutes !== null
    )
    const avgTotalMinutes =
      totalSleepRecords.length > 0
        ? totalSleepRecords.reduce(
            (sum, r) => sum + (r.total_sleep_minutes as number),
            0
          ) / totalSleepRecords.length
        : null

    // 平均深い睡眠 — deep_minutes が非nullのレコードのみ
    const deepRecords = filteredRecords.filter((r) => r.deep_minutes !== null)
    const avgDeepMinutes =
      deepRecords.length > 0
        ? deepRecords.reduce((sum, r) => sum + (r.deep_minutes as number), 0) /
          deepRecords.length
        : null

    // 平均レム割合 — rem_minutes と total_sleep_minutes 両方非nullのレコードのみ
    const remRatioRecords = filteredRecords.filter(
      (r) => r.rem_minutes !== null && r.total_sleep_minutes !== null && r.total_sleep_minutes > 0
    )
    const avgRemRatio =
      remRatioRecords.length > 0
        ? remRatioRecords.reduce(
            (sum, r) =>
              sum + (r.rem_minutes as number) / (r.total_sleep_minutes as number),
            0
          ) / remRatioRecords.length
        : null

    // 平均目覚め評価 — wakeup_rating が非nullのレコードのみ
    const wakeupRecords = filteredRecords.filter((r) => r.wakeup_rating !== null)
    const avgWakeupRating =
      wakeupRecords.length > 0
        ? wakeupRecords.reduce((sum, r) => sum + (r.wakeup_rating as number), 0) /
          wakeupRecords.length
        : null

    return { avgTotalMinutes, avgDeepMinutes, avgRemRatio, avgWakeupRating }
  }, [filteredRecords])

  // 空状態
  if (sleepRecords.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <p className="text-[#94A3B8] text-sm">まだ睡眠記録がありません</p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* グラフカード */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-semibold text-[#0F172A]">睡眠推移</h3>
          <div className="flex items-center gap-1">
            {SLEEP_PERIOD_BUTTONS.map((btn) => (
              <button
                key={btn.value}
                onClick={() => setSleepPeriod(btn.value)}
                className={`px-2.5 py-1 text-xs font-medium rounded-md transition-colors ${
                  sleepPeriod === btn.value
                    ? 'bg-[#14B8A6] text-white'
                    : 'bg-[#F8FAFC] text-[#64748B] border border-[#E2E8F0] hover:border-[#14B8A6]'
                }`}
              >
                {btn.label}
              </button>
            ))}
          </div>
        </div>

        {/* 凡例 */}
        <div className="flex items-center gap-4 mb-2 text-xs text-[#94A3B8]">
          <div className="flex items-center gap-2">
            <span
              className="inline-block w-4 h-2 rounded-sm"
              style={{ backgroundColor: '#14B8A6', opacity: 0.16 }}
            />
            <span>推奨睡眠帯 7-9h</span>
          </div>
        </div>

        <SleepChart sleepRecords={filteredRecords} />
      </div>

      {/* 期間統計 */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <h3 className="text-sm font-semibold text-[#0F172A] mb-3">期間統計</h3>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div>
            <p className="text-sm text-[#94A3B8]">平均睡眠時間</p>
            <p className="text-lg font-bold text-[#0F172A]">
              {sleepStats.avgTotalMinutes !== null
                ? `${(sleepStats.avgTotalMinutes / 60).toFixed(1)}h`
                : '--'}
            </p>
          </div>
          <div>
            <p className="text-sm text-[#94A3B8]">平均深い睡眠</p>
            <p className="text-lg font-bold text-[#0F172A]">
              {sleepStats.avgDeepMinutes !== null
                ? `${Math.round(sleepStats.avgDeepMinutes)}min`
                : '--'}
            </p>
          </div>
          <div>
            <p className="text-sm text-[#94A3B8]">平均レム割合</p>
            <p className="text-lg font-bold text-[#0F172A]">
              {sleepStats.avgRemRatio !== null
                ? `${Math.round(sleepStats.avgRemRatio * 100)}%`
                : '--'}
            </p>
          </div>
          <div>
            <p className="text-sm text-[#94A3B8]">平均目覚め評価</p>
            <p className="text-lg font-bold text-[#0F172A]">
              {sleepStats.avgWakeupRating !== null
                ? sleepStats.avgWakeupRating.toFixed(1)
                : '--'}
            </p>
          </div>
        </div>
      </div>

      {/* 最近の記録（最新5件） */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <h3 className="text-sm font-semibold text-[#0F172A] mb-3">最近の記録</h3>
        <div className="space-y-0">
          {sleepRecords.slice(0, 5).map((record) => {
            const totalLabel =
              record.total_sleep_minutes !== null
                ? `${Math.floor(record.total_sleep_minutes / 60)}h ${
                    record.total_sleep_minutes % 60
                  }m`
                : '--'
            const wakeupLabel =
              record.wakeup_rating !== null
                ? WAKEUP_RATING_OPTIONS[record.wakeup_rating]
                : '--'
            const sourceLabel = SLEEP_SOURCE_LABELS[record.source]
            const sourceBadgeClass =
              record.source === 'healthkit'
                ? 'bg-[#F0FDFA] text-[#14B8A6]'
                : 'bg-[#F1F5F9] text-[#64748B]'

            return (
              <div
                key={record.id}
                className="py-3 border-b border-[#F1F5F9] last:border-0"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <span className="text-xs text-[#94A3B8] w-12">
                      {format(parseISO(record.recorded_date), 'M/d')}
                    </span>
                    <span className="text-sm font-bold text-[#0F172A] w-20">
                      {totalLabel}
                    </span>
                    <span className="text-xs text-[#64748B]">{wakeupLabel}</span>
                  </div>
                  <span
                    className={`text-[10px] px-1.5 py-0.5 rounded ${sourceBadgeClass}`}
                  >
                    {sourceLabel}
                  </span>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
