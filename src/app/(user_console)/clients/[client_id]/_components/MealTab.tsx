'use client'

import { useState, useMemo } from 'react'
import Image from 'next/image'
import { startOfDay, startOfWeek, endOfWeek, startOfMonth, endOfMonth, subMonths, format, isToday, isYesterday, eachDayOfInterval, isBefore } from 'date-fns'
import { ja } from 'date-fns/locale'
import { MEAL_TYPE_OPTIONS } from '@/types/client'
import type { MealRecord } from '@/types/client'

type MealPeriod = 'today' | 'week' | 'month' | '3months' | 'all'

const MEAL_PERIOD_BUTTONS: { label: string; value: MealPeriod }[] = [
  { label: '本日', value: 'today' },
  { label: '今週', value: 'week' },
  { label: '今月', value: 'month' },
  { label: '3ヶ月', value: '3months' },
  { label: '全期間', value: 'all' },
]

const MEAL_EMOJI: Record<string, string> = {
  breakfast: '🍳',
  lunch: '🥗',
  dinner: '🍖',
  snack: '🍪',
}

const WEEKDAY_LABELS_SHORT = ['月', '火', '水', '木', '金', '土', '日']

interface MealTabProps {
  mealRecords: MealRecord[]
}

export function MealTab({ mealRecords }: MealTabProps) {
  const [period, setPeriod] = useState<MealPeriod>('today')

  const filteredMeals = useMemo(() => {
    if (mealRecords.length === 0) return []
    const now = new Date()
    let startDate: Date
    switch (period) {
      case 'today':
        startDate = startOfDay(now)
        break
      case 'week':
        startDate = startOfWeek(now, { weekStartsOn: 1 })
        break
      case 'month':
        startDate = startOfMonth(now)
        break
      case '3months':
        startDate = subMonths(now, 3)
        break
      case 'all':
      default:
        startDate = new Date(0)
        break
    }
    return mealRecords
      .filter((m) => new Date(m.recorded_at) >= startDate)
      .sort((a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime())
  }, [mealRecords, period])

  // 日付ごとにグループ化
  const groupedMeals = useMemo(() => {
    const groups: { dateKey: string; label: string; meals: MealRecord[] }[] = []
    const map = new Map<string, MealRecord[]>()
    for (const meal of filteredMeals) {
      const d = new Date(meal.recorded_at)
      const key = format(d, 'yyyy-MM-dd')
      if (!map.has(key)) map.set(key, [])
      map.get(key)!.push(meal)
    }
    for (const [key, meals] of map) {
      const d = new Date(key + 'T00:00:00')
      let label: string
      if (isToday(d)) {
        label = 'Today'
      } else if (isYesterday(d)) {
        label = 'Yesterday'
      } else {
        label = format(d, 'M月d日 (E)', { locale: ja })
      }
      groups.push({ dateKey: key, label, meals })
    }
    return groups
  }, [filteredMeals])

  // Summary 計算（本日のみ表示）
  const summary = useMemo(() => {
    if (period !== 'today') return null
    const totalMeals = filteredMeals.length
    const totalPhotos = filteredMeals.reduce(
      (sum, m) => sum + (m.images?.length || 0), 0
    )
    const totalKcal = filteredMeals.reduce(
      (sum, m) => sum + (m.calories || 0), 0
    )
    return { totalMeals, totalPhotos, totalKcal }
  }, [filteredMeals, period])

  return (
    <div>
      {/* 期間フィルター */}
      <div className="flex justify-end mb-4">
        <div className="flex space-x-2">
          {MEAL_PERIOD_BUTTONS.map((btn) => (
            <button
              key={btn.value}
              onClick={() => setPeriod(btn.value)}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                period === btn.value
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {btn.label}
            </button>
          ))}
        </div>
      </div>

      {/* Today's Summary */}
      {summary && (
        <div className="rounded-xl bg-gray-50 border border-gray-100 p-4 mb-4">
          <h4 className="font-bold text-sm mb-3">Today&apos;s Summary</h4>
          <div className="grid grid-cols-3 text-center">
            <div>
              <div className="w-12 h-12 rounded-xl bg-blue-50 flex items-center justify-center mx-auto mb-1">
                <span className="text-xl">🍴</span>
              </div>
              <p className="text-lg font-bold">{summary.totalMeals}</p>
              <p className="text-xs text-gray-500">Meals</p>
            </div>
            <div>
              <div className="w-12 h-12 rounded-xl bg-green-50 flex items-center justify-center mx-auto mb-1">
                <span className="text-xl">📷</span>
              </div>
              <p className="text-lg font-bold">{summary.totalPhotos}</p>
              <p className="text-xs text-gray-500">Photos</p>
            </div>
            <div>
              <div className="w-12 h-12 rounded-xl bg-orange-50 flex items-center justify-center mx-auto mb-1">
                <span className="text-xl">🔥</span>
              </div>
              <p className="text-lg font-bold">{summary.totalKcal}</p>
              <p className="text-xs text-gray-500">kcal</p>
            </div>
          </div>
        </div>
      )}

      {/* 週カレンダー */}
      {period === 'week' && <WeekCalendar meals={mealRecords} />}

      {/* 月カレンダー */}
      {period === 'month' && <MonthCalendar meals={mealRecords} />}

      {/* 食事一覧（日付グループ） */}
      {groupedMeals.length > 0 ? (
        <div className="max-h-[500px] overflow-y-auto custom-scrollbar space-y-6">
          {groupedMeals.map((group) => (
            <div key={group.dateKey}>
              {/* 日付ヘッダー */}
              <div className="mb-3">
                <h4 className="font-bold text-base">{group.label}</h4>
                <div className="border-b border-gray-200 mt-1" />
              </div>
              {/* その日の食事カード */}
              <div className="space-y-3">
                {group.meals.map((meal) => {
                  const hasImage = meal.images && meal.images.length > 0
                  return (
                    <div key={meal.id} className="rounded-xl bg-white shadow-sm border border-gray-100 p-4 flex gap-4">
                      <div className="flex-shrink-0">
                        {hasImage ? (
                          <div className="relative w-20 h-20 rounded-lg overflow-hidden bg-gray-100">
                            <Image
                              src={meal.images![0]}
                              alt="食事画像"
                              fill
                              className="object-cover"
                              unoptimized
                            />
                          </div>
                        ) : (
                          <div className="w-20 h-20 rounded-lg bg-gray-100 flex items-center justify-center">
                            <span className="text-3xl">{MEAL_EMOJI[meal.meal_type] || '🍽️'}</span>
                          </div>
                        )}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-sm">{MEAL_TYPE_OPTIONS[meal.meal_type]}</span>
                          <span className="text-xs text-gray-500">
                            {format(new Date(meal.recorded_at), 'H:mm')}
                          </span>
                        </div>
                        {meal.notes && (
                          <p className="text-sm text-gray-800 mt-1 whitespace-pre-wrap">{meal.notes}</p>
                        )}
                        {meal.calories && (
                          <span className="text-xs font-semibold text-orange-600 mt-1 inline-block">
                            {meal.calories} kcal
                          </span>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-gray-500">
          {mealRecords.length === 0 ? 'まだ食事記録がありません' : '選択した期間にデータがありません'}
        </p>
      )}
    </div>
  )
}

// --- 週カレンダー（7カラムレイアウト） ---
function WeekCalendar({ meals }: { meals: MealRecord[] }) {
  const now = new Date()
  const weekStart = startOfWeek(now, { weekStartsOn: 1 })
  const weekEnd = endOfWeek(now, { weekStartsOn: 1 })
  const days = eachDayOfInterval({ start: weekStart, end: weekEnd })
  const rangeLabel = `${format(weekStart, 'M月d日')}〜${format(weekEnd, 'M月d日')}`
  const [hoveredMeal, setHoveredMeal] = useState<MealRecord | null>(null)
  const [hoverPos, setHoverPos] = useState<{ x: number; y: number }>({ x: 0, y: 0 })

  // 日別にグループ
  const mealsByDay = useMemo(() => {
    const map = new Map<string, MealRecord[]>()
    for (const day of days) {
      map.set(format(day, 'yyyy-MM-dd'), [])
    }
    for (const meal of meals) {
      const key = format(new Date(meal.recorded_at), 'yyyy-MM-dd')
      if (map.has(key)) map.get(key)!.push(meal)
    }
    // 各日を時刻降順でソート
    for (const [, dayMeals] of map) {
      dayMeals.sort((a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime())
    }
    return map
  }, [meals, days])

  const handleMouseEnter = (meal: MealRecord, e: React.MouseEvent) => {
    const rect = e.currentTarget.getBoundingClientRect()
    setHoverPos({ x: rect.left + rect.width / 2, y: rect.top })
    setHoveredMeal(meal)
  }

  return (
    <div className="mb-4">
      <h4 className="font-bold text-sm mb-3">{rangeLabel}</h4>
      <div className="grid grid-cols-7 gap-px bg-gray-200 rounded-xl overflow-hidden border border-gray-200 relative">
        {days.map((day, i) => {
          const key = format(day, 'yyyy-MM-dd')
          const dayMeals = mealsByDay.get(key) || []
          const today = isToday(day)
          return (
            <div key={key} className="bg-white flex flex-col min-h-[200px]">
              {/* 日付ヘッダー */}
              <div className={`text-center py-1.5 text-xs font-bold border-b ${today ? 'bg-blue-600 text-white' : 'bg-gray-50 text-gray-700'}`}>
                {format(day, 'M/d')} {WEEKDAY_LABELS_SHORT[i]}
              </div>
              {/* 食事カード */}
              <div className="flex-1 p-1 space-y-1 overflow-y-auto custom-scrollbar">
                {dayMeals.length > 0 ? dayMeals.map((meal) => {
                  const hasImage = meal.images && meal.images.length > 0
                  return (
                    <div
                      key={meal.id}
                      className={`rounded-md border p-1 cursor-pointer hover:shadow-md transition-shadow ${today ? 'border-blue-300' : 'border-gray-100'}`}
                      onMouseEnter={(e) => handleMouseEnter(meal, e)}
                      onMouseLeave={() => setHoveredMeal(null)}
                    >
                      {hasImage ? (
                        <div className="relative w-full aspect-square rounded overflow-hidden bg-gray-100">
                          <Image src={meal.images![0]} alt="" fill className="object-cover" unoptimized />
                        </div>
                      ) : (
                        <div className="w-full aspect-square rounded bg-gray-100 flex items-center justify-center">
                          <span className="text-2xl">{MEAL_EMOJI[meal.meal_type] || '🍽️'}</span>
                        </div>
                      )}
                      <p className="text-[10px] text-gray-600 mt-1 truncate">
                        {MEAL_TYPE_OPTIONS[meal.meal_type]} {format(new Date(meal.recorded_at), 'H:mm')}
                      </p>
                    </div>
                  )
                }) : (
                  <p className="text-[10px] text-gray-400 text-center mt-8">記録が<br />ありません</p>
                )}
              </div>
            </div>
          )
        })}
      </div>
      {/* ホバーポップアップ */}
      {hoveredMeal && (
        <div
          className="fixed z-50 bg-white rounded-xl shadow-xl border border-gray-200 p-3 w-72 pointer-events-none"
          style={{ left: Math.min(hoverPos.x - 144, window.innerWidth - 300), top: hoverPos.y - 10, transform: 'translateY(-100%)' }}
        >
          {hoveredMeal.images && hoveredMeal.images.length > 0 && (
            <div className="relative w-full aspect-video rounded-lg overflow-hidden bg-gray-100 mb-2">
              <Image src={hoveredMeal.images[0]} alt="" fill className="object-cover" unoptimized />
            </div>
          )}
          <p className="text-xs text-gray-500">
            {MEAL_TYPE_OPTIONS[hoveredMeal.meal_type]} {format(new Date(hoveredMeal.recorded_at), 'H:mm')}
          </p>
          {hoveredMeal.notes && (
            <p className="text-sm font-bold mt-0.5">{hoveredMeal.notes}</p>
          )}
          {hoveredMeal.calories && (
            <p className="text-xs text-orange-600 mt-1">{hoveredMeal.calories} kcal</p>
          )}
        </div>
      )}
    </div>
  )
}

// --- 月カレンダー（カレンダー + 日別記録 横並び） ---
function MonthCalendar({ meals }: { meals: MealRecord[] }) {
  const now = new Date()
  const [displayMonth, setDisplayMonth] = useState(now)
  const [selectedDate, setSelectedDate] = useState<string>(format(now, 'yyyy-MM-dd'))

  const monthStart = startOfMonth(displayMonth)
  const monthEnd = endOfMonth(displayMonth)
  const days = eachDayOfInterval({ start: monthStart, end: monthEnd })
  const firstDayOfWeek = (monthStart.getDay() + 6) % 7

  // 全食事データから日別カウント（表示月用）
  const monthMealCount = useMemo(() => {
    const map = new Map<string, number>()
    for (const meal of meals) {
      const key = format(new Date(meal.recorded_at), 'yyyy-MM-dd')
      map.set(key, (map.get(key) || 0) + 1)
    }
    return map
  }, [meals])

  // 選択日の食事
  const selectedDayMeals = useMemo(() => {
    return meals
      .filter((m) => format(new Date(m.recorded_at), 'yyyy-MM-dd') === selectedDate)
      .sort((a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime())
  }, [meals, selectedDate])

  const getDayColor = (count: number, day: Date) => {
    const key = format(day, 'yyyy-MM-dd')
    const isSelected = key === selectedDate
    if (isToday(day)) return `bg-green-600 text-white ${isSelected ? 'ring-2 ring-blue-500' : ''}`
    if (isSelected) return 'ring-2 ring-green-700 bg-green-200 text-gray-800'
    if (count >= 3) return 'bg-green-600 text-white'
    if (count === 2) return 'bg-green-500 text-white'
    if (count === 1) return 'bg-green-200 text-gray-700'
    if (isBefore(day, startOfDay(now))) return 'bg-gray-200 text-gray-500'
    return 'text-gray-400'
  }

  const prevMonth = () => setDisplayMonth((d) => new Date(d.getFullYear(), d.getMonth() - 1, 1))
  const nextMonth = () => setDisplayMonth((d) => new Date(d.getFullYear(), d.getMonth() + 1, 1))

  const selectedLabel = format(new Date(selectedDate + 'T00:00:00'), 'M月d日')

  return (
    <div className="flex gap-4 mb-4">
      {/* 左: カレンダー */}
      <div className="rounded-xl bg-gray-50 border border-gray-100 p-3 flex-shrink-0" style={{ width: '280px' }}>
        {/* ヘッダー */}
        <div className="flex justify-between items-center mb-2">
          <button onClick={prevMonth} className="text-gray-500 hover:text-gray-800 px-1">‹</button>
          <h4 className="font-bold text-sm">{format(displayMonth, 'yyyy年M月')}</h4>
          <button onClick={nextMonth} className="text-gray-500 hover:text-gray-800 px-1">›</button>
        </div>
        {/* 曜日 */}
        <div className="grid grid-cols-7 text-center mb-1">
          {WEEKDAY_LABELS_SHORT.map((label, i) => (
            <span key={i} className="text-[10px] text-gray-400 font-medium">{label}</span>
          ))}
        </div>
        {/* 日付グリッド */}
        <div className="grid grid-cols-7 gap-0.5">
          {Array.from({ length: firstDayOfWeek }).map((_, i) => (
            <div key={`empty-${i}`} />
          ))}
          {days.map((day) => {
            const key = format(day, 'yyyy-MM-dd')
            const count = monthMealCount.get(key) || 0
            return (
              <button
                key={key}
                onClick={() => setSelectedDate(key)}
                className={`aspect-square rounded-md flex items-center justify-center text-xs font-medium cursor-pointer transition-all ${getDayColor(count, day)}`}
              >
                {format(day, 'd')}
              </button>
            )
          })}
        </div>
        {/* 凡例 */}
        <div className="flex justify-end items-center gap-2 mt-2 text-[10px] text-gray-500">
          <span className="flex items-center gap-0.5"><span className="w-2.5 h-2.5 rounded-sm bg-green-600 inline-block" /> 3+</span>
          <span className="flex items-center gap-0.5"><span className="w-2.5 h-2.5 rounded-sm bg-green-500 inline-block" /> 2</span>
          <span className="flex items-center gap-0.5"><span className="w-2.5 h-2.5 rounded-sm bg-green-200 inline-block" /> 1</span>
          <span className="flex items-center gap-0.5"><span className="w-2.5 h-2.5 rounded-sm bg-gray-200 inline-block" /> 0</span>
        </div>
      </div>

      {/* 右: 選択日の記録 */}
      <div className="flex-1 min-w-0">
        <h4 className="font-bold text-sm mb-2">{selectedLabel}の記録</h4>
        {selectedDayMeals.length > 0 ? (
          <div className="space-y-2 max-h-[320px] overflow-y-auto custom-scrollbar">
            {selectedDayMeals.map((meal) => {
              const hasImage = meal.images && meal.images.length > 0
              return (
                <div key={meal.id} className="rounded-lg bg-white shadow-sm border border-gray-100 p-3 flex gap-3">
                  {hasImage ? (
                    <div className="relative w-16 h-16 rounded-md overflow-hidden bg-gray-100 flex-shrink-0">
                      <Image src={meal.images![0]} alt="" fill className="object-cover" unoptimized />
                    </div>
                  ) : (
                    <div className="w-16 h-16 rounded-md bg-gray-100 flex items-center justify-center flex-shrink-0">
                      <span className="text-2xl">{MEAL_EMOJI[meal.meal_type] || '🍽️'}</span>
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-gray-500">
                      {MEAL_TYPE_OPTIONS[meal.meal_type]} {format(new Date(meal.recorded_at), 'H:mm')}
                    </p>
                    {meal.notes && <p className="text-sm font-medium mt-0.5 truncate">{meal.notes}</p>}
                    {meal.calories && <p className="text-xs text-orange-600 mt-0.5">{meal.calories} kcal</p>}
                  </div>
                </div>
              )
            })}
          </div>
        ) : (
          <p className="text-sm text-gray-400 mt-8">記録がありません</p>
        )}
      </div>
    </div>
  )
}
