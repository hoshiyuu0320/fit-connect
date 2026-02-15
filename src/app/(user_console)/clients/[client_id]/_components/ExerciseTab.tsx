'use client'

import { useState, useMemo } from 'react'
import { startOfMonth, endOfMonth, format, isToday, eachDayOfInterval, isBefore, startOfDay } from 'date-fns'
import { EXERCISE_TYPE_OPTIONS } from '@/types/client'
import type { ExerciseRecord } from '@/types/client'

const EXERCISE_EMOJI: Record<string, string> = {
  walking: '🚶',
  running: '🏃',
  strength_training: '🏋️',
  cycling: '🚴',
  swimming: '🏊',
  yoga: '🧘',
  pilates: '🤸',
  cardio: '🏃',
  other: '🏋️'
}

interface ExerciseTabProps {
  exerciseRecords: ExerciseRecord[]
}

export function ExerciseTab({ exerciseRecords }: ExerciseTabProps) {
  const [currentMonth, setCurrentMonth] = useState(new Date())
  const [selectedDate, setSelectedDate] = useState(new Date())

  // 月ナビゲーション
  const handlePreviousMonth = () => {
    setCurrentMonth(prev => new Date(prev.getFullYear(), prev.getMonth() - 1))
  }

  const handleNextMonth = () => {
    setCurrentMonth(prev => new Date(prev.getFullYear(), prev.getMonth() + 1))
  }

  // 月の日付一覧を取得
  const monthDays = useMemo(() => {
    const start = startOfMonth(currentMonth)
    const end = endOfMonth(currentMonth)
    return eachDayOfInterval({ start, end })
  }, [currentMonth])

  // 各日付の運動記録を集計
  const exercisesByDate = useMemo(() => {
    const map = new Map<string, ExerciseRecord[]>()
    exerciseRecords.forEach(record => {
      const dateKey = format(new Date(record.recorded_at), 'yyyy-MM-dd')
      if (!map.has(dateKey)) {
        map.set(dateKey, [])
      }
      map.get(dateKey)!.push(record)
    })
    return map
  }, [exerciseRecords])

  // 選択日の運動記録
  const selectedDateRecords = useMemo(() => {
    const dateKey = format(selectedDate, 'yyyy-MM-dd')
    return exercisesByDate.get(dateKey) || []
  }, [selectedDate, exercisesByDate])

  // 曜日ヘッダー
  const weekDays = ['月', '火', '水', '木', '金', '土', '日']

  // 月の開始曜日（月曜始まり: 0=月, 6=日）
  const firstDayOfMonth = startOfMonth(currentMonth).getDay()
  const adjustedFirstDay = firstDayOfMonth === 0 ? 6 : firstDayOfMonth - 1

  // カレンダーグリッド用の空セル
  const emptyCells = Array(adjustedFirstDay).fill(null)

  return (
    <div className="flex gap-6">
      {/* 左: 月カレンダー */}
      <div className="w-[280px] bg-white rounded-lg shadow-sm border p-4">
        {/* 月ナビゲーション */}
        <div className="flex items-center justify-between mb-4">
          <button
            onClick={handlePreviousMonth}
            className="p-1 hover:bg-gray-100 rounded"
          >
            <span className="text-gray-600">‹</span>
          </button>
          <h3 className="font-semibold text-gray-900">
            {format(currentMonth, 'yyyy年M月')}
          </h3>
          <button
            onClick={handleNextMonth}
            className="p-1 hover:bg-gray-100 rounded"
          >
            <span className="text-gray-600">›</span>
          </button>
        </div>

        {/* 曜日ヘッダー */}
        <div className="grid grid-cols-7 gap-1 mb-2">
          {weekDays.map(day => (
            <div key={day} className="text-center text-xs text-gray-600 font-medium">
              {day}
            </div>
          ))}
        </div>

        {/* 日付グリッド */}
        <div className="grid grid-cols-7 gap-1">
          {emptyCells.map((_, index) => (
            <div key={`empty-${index}`} className="aspect-square" />
          ))}
          {monthDays.map(day => {
            const dateKey = format(day, 'yyyy-MM-dd')
            const dayRecords = exercisesByDate.get(dateKey) || []
            const hasRecords = dayRecords.length > 0
            const isSelected = format(day, 'yyyy-MM-dd') === format(selectedDate, 'yyyy-MM-dd')
            const isTodayDate = isToday(day)
            const isFuture = isBefore(startOfDay(new Date()), startOfDay(day))

            // 複数記録がある場合は最初の運動種目のEmojiを表示
            const firstExerciseType = hasRecords ? dayRecords[0].exercise_type : null
            const exerciseCount = dayRecords.length

            return (
              <button
                key={dateKey}
                onClick={() => setSelectedDate(day)}
                className={`
                  aspect-square p-1 rounded relative text-sm
                  ${isSelected ? 'ring-2 ring-blue-600' : ''}
                  ${isTodayDate ? 'bg-blue-50' : ''}
                  ${isFuture ? 'text-gray-300' : hasRecords ? 'text-gray-900' : 'text-gray-400'}
                  ${!isFuture && !hasRecords ? 'hover:bg-gray-50' : ''}
                  ${hasRecords ? 'hover:bg-gray-50' : ''}
                `}
              >
                <div className="text-center">
                  {format(day, 'd')}
                </div>
                {hasRecords && firstExerciseType && (
                  <div className="absolute bottom-0 left-1/2 transform -translate-x-1/2 flex items-center gap-0.5">
                    <span className="text-xs">{EXERCISE_EMOJI[firstExerciseType]}</span>
                    {exerciseCount > 1 && (
                      <span className="text-[10px] bg-blue-600 text-white rounded-full w-3 h-3 flex items-center justify-center">
                        {exerciseCount}
                      </span>
                    )}
                  </div>
                )}
              </button>
            )
          })}
        </div>
      </div>

      {/* 右: 選択日の運動記録 */}
      <div className="flex-1 bg-white rounded-lg shadow-sm border p-4">
        <h3 className="font-semibold text-gray-900 mb-4">
          {format(selectedDate, 'M月d日')}の運動記録
        </h3>

        {selectedDateRecords.length === 0 ? (
          <div className="text-center py-8 text-gray-400">
            この日の運動記録はありません
          </div>
        ) : (
          <div className="space-y-3 max-h-[400px] overflow-y-auto custom-scrollbar">
            {selectedDateRecords.map(record => (
              <div
                key={record.id}
                className="bg-white rounded-lg shadow-sm border p-4 flex gap-4"
              >
                {/* 運動Emoji */}
                <div className="flex-shrink-0">
                  <div className="w-12 h-12 bg-blue-50 rounded-lg flex items-center justify-center text-2xl">
                    {EXERCISE_EMOJI[record.exercise_type]}
                  </div>
                </div>

                {/* 運動詳細 */}
                <div className="flex-1">
                  <h4 className="font-semibold text-gray-900 mb-1">
                    {EXERCISE_TYPE_OPTIONS[record.exercise_type]}
                  </h4>
                  <div className="flex flex-wrap gap-3 text-sm text-gray-600">
                    {record.duration !== null && (
                      <span>時間: {record.duration}分</span>
                    )}
                    {record.distance !== null && (
                      <span>距離: {record.distance}km</span>
                    )}
                    {record.calories !== null && (
                      <span>カロリー: {record.calories}kcal</span>
                    )}
                  </div>
                  {record.memo && (
                    <p className="mt-2 text-sm text-gray-700">{record.memo}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
