'use client'

import { useMemo } from 'react'
import { format } from 'date-fns'
import { WeightChart } from '@/components/clients/WeightChart'
import type { WeightRecord, MealRecord, ExerciseRecord, Ticket } from '@/types/client'
import { MEAL_TYPE_OPTIONS, EXERCISE_TYPE_OPTIONS, PURPOSE_OPTIONS } from '@/types/client'

interface SummaryTabProps {
  weightRecords: WeightRecord[]
  mealRecords: MealRecord[]
  exerciseRecords: ExerciseRecord[]
  tickets: Ticket[]
  targetWeight: number
  height?: number
  purpose?: string
  goalDescription?: string | null
  goalDeadline?: string | null
}

const MEAL_EMOJI: Record<string, string> = {
  breakfast: '🍳',
  lunch: '🥗',
  dinner: '🍖',
  snack: '🍪',
}

export function SummaryTab({
  weightRecords,
  mealRecords,
  exerciseRecords,
  tickets,
  targetWeight,
  height,
  purpose,
  goalDescription,
  goalDeadline,
}: SummaryTabProps) {
  // 有効チケット
  const activeTickets = useMemo(() => {
    const todayStr = format(new Date(), 'yyyy-MM-dd')
    return tickets.filter(
      (ticket) =>
        ticket.remaining_sessions > 0 &&
        ticket.valid_until >= todayStr &&
        ticket.valid_from <= todayStr
    )
  }, [tickets])

  // 最近の活動（食事3件 + 運動3件を時系列マージ）
  const recentActivities = useMemo(() => {
    const meals = mealRecords.slice(0, 3).map((m) => ({
      id: `meal-${m.id}`,
      icon: MEAL_EMOJI[m.meal_type] || '🍽',
      label: (MEAL_TYPE_OPTIONS[m.meal_type] as string) + (m.notes ? ` - ${m.notes}` : ''),
      time: format(new Date(m.recorded_at), 'M/d H:mm'),
      calories: m.calories,
      date: new Date(m.recorded_at),
    }))
    const exercises = exerciseRecords.slice(0, 3).map((e) => ({
      id: `exercise-${e.id}`,
      icon: '🏃',
      label:
        (EXERCISE_TYPE_OPTIONS[e.exercise_type] as string) +
        (e.duration ? ` ${e.duration}分` : ''),
      time: format(new Date(e.recorded_at), 'M/d H:mm'),
      calories: e.calories,
      date: new Date(e.recorded_at),
    }))
    return [...meals, ...exercises]
      .sort((a, b) => b.date.getTime() - a.date.getTime())
      .slice(0, 6)
  }, [mealRecords, exerciseRecords])

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
      {/* 左カラム (col-span-2) */}
      <div className="lg:col-span-2 space-y-4">
        {/* 体重グラフカード */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <h3 className="text-sm font-semibold text-[#0F172A] mb-3">体重推移</h3>
          {weightRecords.length > 0 ? (
            <WeightChart weightRecords={weightRecords} targetWeight={targetWeight} />
          ) : (
            <div className="flex items-center justify-center h-[200px] bg-[#F8FAFC] rounded-md">
              <p className="text-sm text-[#94A3B8]">体重記録がありません</p>
            </div>
          )}
        </div>

        {/* 最近の活動タイムライン */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <h3 className="text-sm font-semibold text-[#0F172A] mb-3">最近の活動</h3>
          {recentActivities.length > 0 ? (
            <div className="space-y-0">
              {recentActivities.map((activity) => (
                <div
                  key={activity.id}
                  className="flex items-center gap-3 py-2 border-b border-[#F1F5F9] last:border-0"
                >
                  <span className="text-sm flex-shrink-0">{activity.icon}</span>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-[#0F172A] truncate">{activity.label}</p>
                    <p className="text-[11px] text-[#94A3B8]">{activity.time}</p>
                  </div>
                  {activity.calories != null && (
                    <span className="text-xs text-[#F59E0B] font-medium flex-shrink-0">
                      {activity.calories}kcal
                    </span>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-[#94A3B8]">活動記録がありません</p>
          )}
        </div>
      </div>

      {/* 右カラム (col-span-1) */}
      <div className="space-y-4">
        {/* クライアント情報カード */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <h3 className="text-sm font-semibold text-[#0F172A] mb-3">クライアント情報</h3>
          <div className="space-y-0">
            <div className="flex justify-between py-2.5">
              <span className="text-xs text-[#94A3B8]">身長</span>
              <span className="text-sm font-medium text-[#0F172A]">{height ?? '--'}cm</span>
            </div>
            <div className="flex justify-between border-t border-[#F1F5F9] py-2.5">
              <span className="text-xs text-[#94A3B8]">目標体重</span>
              <span className="text-sm font-medium text-[#0F172A]">{targetWeight}kg</span>
            </div>
            <div className="flex justify-between border-t border-[#F1F5F9] py-2.5">
              <span className="text-xs text-[#94A3B8]">目的</span>
              <span className="text-sm font-medium text-[#14B8A6]">
                {purpose && PURPOSE_OPTIONS[purpose as keyof typeof PURPOSE_OPTIONS]
                  ? PURPOSE_OPTIONS[purpose as keyof typeof PURPOSE_OPTIONS]
                  : '--'}
              </span>
            </div>
            {goalDeadline && (
              <div className="flex justify-between border-t border-[#F1F5F9] py-2.5">
                <span className="text-xs text-[#94A3B8]">目標期日</span>
                <span className="text-sm font-medium text-[#0F172A]">
                  {format(new Date(goalDeadline), 'yyyy/MM/dd')}
                </span>
              </div>
            )}
            {goalDescription && (
              <div className="border-t border-[#F1F5F9] pt-2.5">
                <span className="text-xs text-[#94A3B8] block mb-1">目標</span>
                <p className="text-sm text-[#0F172A]">{goalDescription}</p>
              </div>
            )}
          </div>
        </div>

        {/* チケットステータス */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <h3 className="text-sm font-semibold text-[#0F172A] mb-3">チケット</h3>
          {activeTickets.length > 0 ? (
            <div className="space-y-0">
              {activeTickets.map((ticket) => (
                <div key={ticket.id} className="py-2.5 border-b border-[#F1F5F9] last:border-0">
                  <div className="flex items-center justify-between mb-1.5">
                    <span className="text-sm font-medium text-[#0F172A] truncate mr-2">
                      {ticket.ticket_name}
                    </span>
                    <span className="text-sm font-bold text-[#0F172A] flex-shrink-0">
                      {ticket.remaining_sessions}
                      <span className="text-[10px] text-[#94A3B8] ml-0.5">
                        /{ticket.total_sessions}
                      </span>
                    </span>
                  </div>
                  <div className="w-full bg-[#F1F5F9] rounded h-1.5">
                    <div
                      className="bg-[#14B8A6] h-1.5 rounded"
                      style={{
                        width: `${ticket.total_sessions > 0 ? (ticket.remaining_sessions / ticket.total_sessions) * 100 : 0}%`,
                      }}
                    />
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-[#94A3B8]">有効なチケットはありません</p>
          )}
        </div>
      </div>
    </div>
  )
}
