"use client"

import { format, addDays } from 'date-fns'
import { ja } from 'date-fns/locale'
import { CalendarDayCell } from './CalendarDayCell'
import type { WorkoutAssignment } from '@/types/workout'

interface WeeklyCalendarProps {
  currentWeekStart: Date
  assignments: WorkoutAssignment[]
  onPrevWeek: () => void
  onNextWeek: () => void
  onThisWeek: () => void
  onDeleteAssignment: (id: string) => void
}

export function WeeklyCalendar({
  currentWeekStart,
  assignments,
  onPrevWeek,
  onNextWeek,
  onThisWeek,
  onDeleteAssignment,
}: WeeklyCalendarProps) {
  const weekDays = Array.from({ length: 7 }, (_, i) => addDays(currentWeekStart, i))

  const weekEnd = addDays(currentWeekStart, 6)
  const weekLabel = `${format(currentWeekStart, 'yyyy年M月d日', { locale: ja })} - ${format(weekEnd, 'M月d日', { locale: ja })}`

  const assignmentsByDate = (date: Date): WorkoutAssignment[] => {
    const dateStr = format(date, 'yyyy-MM-dd')
    return assignments.filter((a) => a.assigned_date === dateStr)
  }

  return (
    <section className="flex-1 overflow-x-auto p-6 flex flex-col">
      {/* ナビゲーション */}
      <div className="flex items-center justify-between mb-4 flex-shrink-0">
        <div className="flex items-center gap-2">
          <button
            onClick={onPrevWeek}
            className="p-2 border rounded-md hover:bg-gray-100 text-sm text-gray-600"
          >
            &larr; 前週
          </button>
          <button
            onClick={onNextWeek}
            className="p-2 border rounded-md hover:bg-gray-100 text-sm text-gray-600"
          >
            次週 &rarr;
          </button>
        </div>
        <span className="font-semibold text-gray-700 text-sm">{weekLabel}</span>
        <button
          onClick={onThisWeek}
          className="px-3 py-1.5 text-sm border rounded-md hover:bg-gray-100 text-gray-600"
        >
          今週
        </button>
      </div>

      {/* カレンダーグリッド */}
      <div className="grid grid-cols-7 gap-3 min-w-[800px] flex-1">
        {weekDays.map((day) => (
          <CalendarDayCell
            key={format(day, 'yyyy-MM-dd')}
            date={day}
            assignments={assignmentsByDate(day)}
            onDeleteAssignment={onDeleteAssignment}
          />
        ))}
      </div>
    </section>
  )
}
