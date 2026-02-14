'use client'

import { useMemo } from 'react'
import Image from 'next/image'
import { subMonths, format, isAfter, isBefore } from 'date-fns'
import { WeightChart } from '@/components/clients/WeightChart'
import type { WeightRecord, MealRecord, ExerciseRecord, Ticket } from '@/types/client'
import { MEAL_TYPE_OPTIONS } from '@/types/client'

interface SummaryTabProps {
  weightRecords: WeightRecord[]
  mealRecords: MealRecord[]
  exerciseRecords: ExerciseRecord[]
  tickets: Ticket[]
  targetWeight: number
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
}: SummaryTabProps) {
  // 統計データの計算
  const stats = useMemo(() => {
    const now = new Date()
    const thirtyDaysAgo = subMonths(now, 1)
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)

    // 体重変動（直近30日）
    const recentWeights = weightRecords.filter((record) => new Date(record.recorded_at) >= thirtyDaysAgo)
    const currentWeight = weightRecords.length > 0 ? weightRecords[weightRecords.length - 1]?.weight : null
    const oldestRecentWeight = recentWeights.length > 0 ? recentWeights[0]?.weight : null
    const weightChange =
      currentWeight !== null && oldestRecentWeight !== null ? currentWeight - oldestRecentWeight : null

    // 食事記録（直近7日）
    const recentMeals = mealRecords.filter((record) => new Date(record.recorded_at) >= sevenDaysAgo).length

    // 運動記録（直近7日）
    const recentExercises = exerciseRecords.filter((record) => new Date(record.recorded_at) >= sevenDaysAgo).length

    // チケット情報
    const validTickets = tickets.filter(
      (ticket) =>
        ticket.remaining_sessions > 0 &&
        isAfter(new Date(ticket.valid_until), now) &&
        isBefore(new Date(ticket.valid_from), now)
    )
    const totalRemainingSessions = validTickets.reduce((sum, ticket) => sum + ticket.remaining_sessions, 0)

    return {
      currentWeight,
      weightChange,
      recentMeals,
      recentExercises,
      validTicketsCount: validTickets.length,
      totalRemainingSessions,
    }
  }, [weightRecords, mealRecords, exerciseRecords, tickets])

  // 最近の食事3件
  const recentMealsList = useMemo(() => {
    return [...mealRecords]
      .sort((a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime())
      .slice(0, 3)
  }, [mealRecords])

  // チケットリスト（有効期限順）
  const sortedTickets = useMemo(() => {
    const now = new Date()
    return [...tickets]
      .sort((a, b) => new Date(a.valid_until).getTime() - new Date(b.valid_until).getTime())
      .map((ticket) => ({
        ...ticket,
        isExpired:
          ticket.remaining_sessions <= 0 ||
          isAfter(new Date(ticket.valid_from), now) ||
          isBefore(new Date(ticket.valid_until), now),
      }))
  }, [tickets])

  return (
    <div className="space-y-6">
      {/* 統計サマリーカード */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* 体重変動 */}
        <div className="bg-white rounded-lg shadow-sm border p-4">
          <h3 className="text-sm font-medium text-gray-600 mb-2">体重変動（30日）</h3>
          {stats.currentWeight !== null ? (
            <>
              <p className="text-2xl font-bold text-gray-900">{stats.currentWeight.toFixed(1)} kg</p>
              {stats.weightChange !== null && (
                <p
                  className={`text-sm mt-1 ${
                    stats.weightChange > 0
                      ? 'text-rose-600'
                      : stats.weightChange < 0
                        ? 'text-emerald-600'
                        : 'text-gray-600'
                  }`}
                >
                  {stats.weightChange > 0 ? '+' : ''}
                  {stats.weightChange.toFixed(1)} kg
                </p>
              )}
            </>
          ) : (
            <p className="text-sm text-gray-500">データなし</p>
          )}
        </div>

        {/* 食事記録 */}
        <div className="bg-white rounded-lg shadow-sm border p-4">
          <h3 className="text-sm font-medium text-gray-600 mb-2">食事記録（7日）</h3>
          <p className="text-2xl font-bold text-gray-900">{stats.recentMeals} 件</p>
        </div>

        {/* 運動記録 */}
        <div className="bg-white rounded-lg shadow-sm border p-4">
          <h3 className="text-sm font-medium text-gray-600 mb-2">運動記録（7日）</h3>
          <p className="text-2xl font-bold text-gray-900">{stats.recentExercises} 件</p>
        </div>

        {/* チケット */}
        <div className="bg-white rounded-lg shadow-sm border p-4">
          <h3 className="text-sm font-medium text-gray-600 mb-2">有効チケット</h3>
          <p className="text-2xl font-bold text-gray-900">
            {stats.validTicketsCount} 枚 / {stats.totalRemainingSessions} 回
          </p>
        </div>
      </div>

      {/* 体重推移ミニグラフ */}
      <div className="bg-white rounded-lg shadow-sm border p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">体重推移</h3>
        {weightRecords.length > 0 ? (
          <WeightChart weightRecords={weightRecords} targetWeight={targetWeight} />
        ) : (
          <div className="flex items-center justify-center h-[300px] bg-gray-50 rounded-lg">
            <p className="text-gray-500">体重記録がありません</p>
          </div>
        )}
      </div>

      {/* 最近の記録セクション */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* 最近の食事 */}
        <div className="bg-white rounded-lg shadow-sm border p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">最近の食事</h3>
          {recentMealsList.length > 0 ? (
            <div className="space-y-3">
              {recentMealsList.map((meal) => (
                <div key={meal.id} className="flex items-start space-x-3 p-3 bg-gray-50 rounded-lg">
                  {/* 画像またはEmoji */}
                  <div className="flex-shrink-0">
                    {meal.images && meal.images.length > 0 ? (
                      <div className="w-16 h-16 rounded-lg overflow-hidden bg-gray-200">
                        <Image
                          src={meal.images[0]}
                          alt="食事"
                          width={64}
                          height={64}
                          className="w-full h-full object-cover"
                        />
                      </div>
                    ) : (
                      <div className="w-16 h-16 flex items-center justify-center text-3xl bg-white rounded-lg">
                        {MEAL_EMOJI[meal.meal_type] || '🍽️'}
                      </div>
                    )}
                  </div>

                  {/* 食事情報 */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-medium text-gray-900">
                        {MEAL_TYPE_OPTIONS[meal.meal_type]}
                      </span>
                      {meal.calories !== null && (
                        <span className="text-sm font-semibold text-blue-600">{meal.calories} kcal</span>
                      )}
                    </div>
                    <p className="text-xs text-gray-500 mt-1">{format(new Date(meal.recorded_at), 'M/d HH:mm')}</p>
                    {meal.notes && <p className="text-sm text-gray-700 mt-1 line-clamp-2">{meal.notes}</p>}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="flex items-center justify-center h-32 bg-gray-50 rounded-lg">
              <p className="text-gray-500 text-sm">食事記録がありません</p>
            </div>
          )}
        </div>

        {/* 保有チケット */}
        <div className="bg-white rounded-lg shadow-sm border p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">保有チケット</h3>
          {sortedTickets.length > 0 ? (
            <div className="space-y-3">
              {sortedTickets.map((ticket) => (
                <div
                  key={ticket.id}
                  className={`p-4 rounded-lg border ${
                    ticket.isExpired ? 'bg-gray-50 border-gray-300 opacity-60' : 'bg-blue-50 border-blue-200'
                  }`}
                >
                  <div className="flex items-center justify-between mb-2">
                    <h4
                      className={`text-sm font-semibold ${ticket.isExpired ? 'text-gray-600' : 'text-gray-900'}`}
                    >
                      {ticket.ticket_name}
                    </h4>
                    {ticket.isExpired && <span className="text-xs text-gray-500 font-medium">期限切れ</span>}
                  </div>

                  {/* プログレスバー */}
                  <div className="mb-2">
                    <div className="flex items-center justify-between text-xs text-gray-600 mb-1">
                      <span>残り {ticket.remaining_sessions} 回</span>
                      <span>
                        {ticket.total_sessions > 0
                          ? Math.round((ticket.remaining_sessions / ticket.total_sessions) * 100)
                          : 0}
                        %
                      </span>
                    </div>
                    <div className="w-full bg-gray-200 rounded-full h-2">
                      <div
                        className={`h-2 rounded-full ${ticket.isExpired ? 'bg-gray-400' : 'bg-blue-600'}`}
                        style={{
                          width: `${ticket.total_sessions > 0 ? (ticket.remaining_sessions / ticket.total_sessions) * 100 : 0}%`,
                        }}
                      ></div>
                    </div>
                  </div>

                  {/* 有効期限 */}
                  <p className="text-xs text-gray-600">
                    有効期限: {format(new Date(ticket.valid_from), 'yyyy/M/d')} -{' '}
                    {format(new Date(ticket.valid_until), 'yyyy/M/d')}
                  </p>
                </div>
              ))}
            </div>
          ) : (
            <div className="flex items-center justify-center h-32 bg-gray-50 rounded-lg">
              <p className="text-gray-500 text-sm">保有チケットがありません</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
