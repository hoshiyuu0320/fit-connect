'use client'

import { useMemo } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import {
  startOfMonth,
  endOfMonth,
  getDay,
  eachDayOfInterval,
  format,
  isToday,
} from 'date-fns'
import type { CalendarActivity } from '@/types/report'

interface ActivityCalendarProps {
  year: number
  month: number // 1-12
  activities: CalendarActivity[]
  onMonthChange: (year: number, month: number) => void
}

const WEEKDAY_LABELS = ['月', '火', '水', '木', '金', '土', '日']

const ACTIVITY_COLORS: Record<string, string> = {
  weight: '#2563EB',
  meal: '#EA580C',
  exercise: '#16A34A',
}

const LEGEND_ITEMS = [
  { type: 'weight', label: '体重', color: '#2563EB' },
  { type: 'meal', label: '食事', color: '#EA580C' },
  { type: 'exercise', label: '運動', color: '#16A34A' },
]

export function ActivityCalendar({
  year,
  month,
  activities,
  onMonthChange,
}: ActivityCalendarProps) {
  // Build activity map for quick lookup
  const activityMap = useMemo(() => {
    const map = new Map<string, CalendarActivity>()
    for (const a of activities) {
      map.set(a.date, a)
    }
    return map
  }, [activities])

  // Calendar grid data
  const calendarData = useMemo(() => {
    const monthStart = startOfMonth(new Date(year, month - 1))
    const monthEnd = endOfMonth(new Date(year, month - 1))
    const days = eachDayOfInterval({ start: monthStart, end: monthEnd })

    // getDay returns 0=Sunday. Convert to Monday-start: Mon=0, Tue=1, ... Sun=6
    const startDayOfWeek = (getDay(monthStart) + 6) % 7

    return { days, startDayOfWeek }
  }, [year, month])

  const handlePrevMonth = () => {
    if (month === 1) {
      onMonthChange(year - 1, 12)
    } else {
      onMonthChange(year, month - 1)
    }
  }

  const handleNextMonth = () => {
    if (month === 12) {
      onMonthChange(year + 1, 1)
    } else {
      onMonthChange(year, month + 1)
    }
  }

  return (
    <div className="bg-white border border-[#E2E8F0] rounded-md">
      {/* ヘッダー */}
      <div className="px-4 py-3 border-b border-[#E2E8F0] flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-bold text-[#0F172A]">
            アクティビティカレンダー
          </h3>
          <span className="text-xs text-[#94A3B8]">
            {year}年{month}月
          </span>
        </div>
        <div className="flex items-center gap-4">
          {/* 凡例 */}
          <div className="flex items-center gap-3">
            {LEGEND_ITEMS.map((item) => (
              <div key={item.type} className="flex items-center gap-1">
                <span
                  className="inline-block w-[6px] h-[6px] rounded-full"
                  style={{ backgroundColor: item.color }}
                />
                <span className="text-[10px] text-[#94A3B8]">{item.label}</span>
              </div>
            ))}
          </div>
          {/* 月送りボタン */}
          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={handlePrevMonth}
              className="p-1 rounded-md border border-[#E2E8F0] hover:bg-[#F8FAFC] transition-colors"
            >
              <ChevronLeft className="w-4 h-4 text-[#64748B]" />
            </button>
            <button
              type="button"
              onClick={handleNextMonth}
              className="p-1 rounded-md border border-[#E2E8F0] hover:bg-[#F8FAFC] transition-colors"
            >
              <ChevronRight className="w-4 h-4 text-[#64748B]" />
            </button>
          </div>
        </div>
      </div>

      {/* カレンダーグリッド */}
      <div className="p-4">
        {/* 曜日ヘッダー */}
        <div className="grid grid-cols-7">
          {WEEKDAY_LABELS.map((label) => (
            <div
              key={label}
              className="bg-[#F8FAFC] text-center py-1 text-[10px] font-semibold text-[#94A3B8]"
            >
              {label}
            </div>
          ))}
        </div>

        {/* 日付セル */}
        <div className="grid grid-cols-7">
          {/* 月初の空セル */}
          {Array.from({ length: calendarData.startDayOfWeek }).map((_, i) => (
            <div
              key={`empty-${i}`}
              className="min-h-[60px] border-b border-r border-[#E2E8F0]"
            />
          ))}

          {/* 各日付 */}
          {calendarData.days.map((day) => {
            const dateStr = format(day, 'yyyy-MM-dd')
            const activity = activityMap.get(dateStr)
            const today = isToday(day)

            return (
              <div
                key={dateStr}
                className={`min-h-[60px] p-2 border-b border-r border-[#E2E8F0] ${
                  today ? 'bg-[#F0FDFA] border-[#14B8A6]' : 'bg-white'
                }`}
              >
                <div className="flex items-center justify-between">
                  <span
                    className={`text-[11px] font-semibold ${
                      today ? 'text-[#14B8A6]' : 'text-[#0F172A]'
                    }`}
                  >
                    {format(day, 'd')}
                  </span>
                  {today && (
                    <span className="text-[8px] font-bold text-[#14B8A6]">
                      TODAY
                    </span>
                  )}
                </div>

                {/* アクティビティドット */}
                {activity && activity.types.length > 0 && (
                  <div className="flex items-center gap-1 mt-2">
                    {activity.types.map((type) => (
                      <span
                        key={type}
                        className="inline-block w-[6px] h-[6px] rounded-full"
                        style={{
                          backgroundColor: ACTIVITY_COLORS[type] ?? '#94A3B8',
                        }}
                      />
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
