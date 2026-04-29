'use client'

import { useMemo } from 'react'
import { format } from 'date-fns'
import { WeightChart } from '@/components/clients/WeightChart'
import type { WeightRecord, MealRecord, ExerciseRecord, Ticket, SleepRecord } from '@/types/client'
import { MEAL_TYPE_OPTIONS, EXERCISE_TYPE_OPTIONS, PURPOSE_OPTIONS } from '@/types/client'
import {
  type BmrFormula,
  calculateBmr,
  calculateCalorieBalance,
  predictWeight,
} from '@/utils/weightPrediction'

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
  clientAge?: number
  clientGender?: 'male' | 'female' | 'other'
  bmrFormula?: BmrFormula
  sleepRecords?: SleepRecord[]
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
  clientAge,
  clientGender,
  bmrFormula = 'mifflin',
  sleepRecords = [],
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

  // 直近7日の睡眠サマリー
  const sleepSummary = useMemo(() => {
    if (sleepRecords.length === 0) {
      return { avgHours: null, avgWakeupRating: null, hasWarning: false, recentCount: 0 }
    }
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
    const recent = sleepRecords.filter((r) => new Date(r.recorded_date) >= sevenDaysAgo)
    if (recent.length === 0) {
      return { avgHours: null, avgWakeupRating: null, hasWarning: false, recentCount: 0 }
    }
    const totalMins = recent.filter((r) => r.total_sleep_minutes !== null)
    const avgHours = totalMins.length > 0
      ? totalMins.reduce((sum, r) => sum + (r.total_sleep_minutes ?? 0), 0) / totalMins.length / 60
      : null
    const ratings = recent.filter((r) => r.wakeup_rating !== null)
    const avgWakeupRating = ratings.length > 0
      ? ratings.reduce((sum, r) => sum + (r.wakeup_rating ?? 0), 0) / ratings.length
      : null
    // 6時間未満 or 平均評価1.5以下なら注意喚起
    const hasWarning = (avgHours !== null && avgHours < 6) || (avgWakeupRating !== null && avgWakeupRating <= 1.5)
    return { avgHours, avgWakeupRating, hasWarning, recentCount: recent.length }
  }, [sleepRecords])

  // 予測データ（30日固定）
  const predictionData = useMemo(() => {
    const currentWeight = weightRecords[0]?.weight ?? null
    if (!currentWeight || !height || !clientAge || !clientGender) return null

    const bmr = calculateBmr({
      weight: currentWeight,
      height,
      age: clientAge,
      gender: clientGender,
      formula: bmrFormula,
    })

    // 直近30日の食事・運動記録をフィルタ
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    const recentMeals = mealRecords.filter((m) => new Date(m.recorded_at) >= thirtyDaysAgo)
    const recentExercises = exerciseRecords.filter((e) => new Date(e.recorded_at) >= thirtyDaysAgo)

    const balance = calculateCalorieBalance({
      mealRecords: recentMeals,
      exerciseRecords: recentExercises,
      bmr,
      periodDays: 30,
    })

    if (balance.dailyBalance === null) return { bmr, prediction: null, currentWeight }

    const prediction = predictWeight({
      currentWeight,
      targetWeight,
      dailyBalance: balance.dailyBalance,
    })

    return { bmr, prediction, currentWeight }
  }, [weightRecords, height, clientAge, clientGender, bmrFormula, mealRecords, exerciseRecords, targetWeight])

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

        {/* 睡眠サマリー（直近7日） */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-semibold text-[#0F172A]">睡眠（直近7日）</h3>
            {sleepSummary.hasWarning && (
              <span className="text-[10px] px-1.5 py-0.5 rounded bg-[#FEF3C7] text-[#B45309]">
                改善余地あり
              </span>
            )}
          </div>
          {sleepSummary.recentCount === 0 ? (
            <p className="text-sm text-[#94A3B8]">記録がありません</p>
          ) : (
            <div className="space-y-2.5">
              <div className="flex justify-between py-1">
                <span className="text-xs text-[#94A3B8]">平均睡眠時間</span>
                <span className="text-sm font-medium text-[#0F172A]">
                  {sleepSummary.avgHours !== null ? `${sleepSummary.avgHours.toFixed(1)}h` : '--'}
                </span>
              </div>
              <div className="flex justify-between border-t border-[#F1F5F9] py-1 pt-2.5">
                <span className="text-xs text-[#94A3B8]">平均目覚め評価</span>
                <span className="text-sm font-medium text-[#0F172A]">
                  {sleepSummary.avgWakeupRating !== null ? sleepSummary.avgWakeupRating.toFixed(1) : '--'}
                  <span className="text-[10px] text-[#94A3B8] ml-1">/3.0</span>
                </span>
              </div>
              <div className="flex justify-between border-t border-[#F1F5F9] py-1 pt-2.5">
                <span className="text-xs text-[#94A3B8]">記録日数</span>
                <span className="text-sm font-medium text-[#0F172A]">{sleepSummary.recentCount}日</span>
              </div>
            </div>
          )}
        </div>

        {/* 体重予測カード（コンパクト） */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <h3 className="text-sm font-semibold text-[#0F172A] mb-3">体重予測</h3>
          {predictionData ? (
            <div className="space-y-2.5">
              <div className="flex justify-between py-1">
                <span className="text-xs text-[#94A3B8]">基礎代謝 (BMR)</span>
                <span className="text-sm font-medium text-[#0F172A]">
                  {Math.round(predictionData.bmr).toLocaleString()}kcal/日
                </span>
              </div>
              {predictionData.prediction && (
                <>
                  <div className="flex justify-between border-t border-[#F1F5F9] py-1 pt-2.5">
                    <span className="text-xs text-[#94A3B8]">1ヶ月後予測</span>
                    <span className={`text-sm font-bold ${predictionData.prediction.monthlyChange > 0 ? 'text-[#DC2626]' : 'text-[#16A34A]'}`}>
                      {predictionData.prediction.predictedWeight}kg
                      <span className="text-[10px] ml-1">
                        ({predictionData.prediction.monthlyChange > 0 ? '+' : ''}
                        {predictionData.prediction.monthlyChange}kg)
                      </span>
                    </span>
                  </div>
                  {predictionData.prediction.monthsToGoal !== null && (
                    <div className="flex justify-between border-t border-[#F1F5F9] py-1 pt-2.5">
                      <span className="text-xs text-[#94A3B8]">目標到達</span>
                      <span className="text-sm font-bold text-[#14B8A6]">
                        {predictionData.prediction.monthsToGoal}ヶ月
                      </span>
                    </div>
                  )}
                </>
              )}
            </div>
          ) : (
            <p className="text-sm text-[#94A3B8]">クライアント情報が不足しています</p>
          )}
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
