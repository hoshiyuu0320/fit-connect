'use client'

import { useState, useMemo, useRef, useCallback } from 'react'
import Image from 'next/image'
import { startOfDay, startOfWeek, endOfWeek, startOfMonth, endOfMonth, subMonths, format, isToday, isYesterday, eachDayOfInterval, isBefore } from 'date-fns'
import { ja } from 'date-fns/locale'
import { MEAL_TYPE_OPTIONS } from '@/types/client'
import { ImageModal } from '@/components/message/ImageModal'
import type { MealRecord } from '@/types/client'

type MealPeriod = 'today' | 'week' | 'month' | '3months' | 'all'

const MEAL_PERIOD_BUTTONS: { label: string; value: MealPeriod }[] = [
  { label: '本日', value: 'today' },
  { label: '今週', value: 'week' },
  { label: '今月', value: 'month' },
]

const MEAL_EMOJI: Record<string, string> = {
  breakfast: '🍳',
  lunch: '🥗',
  dinner: '🍖',
  snack: '🍪',
}

const WEEKDAY_LABELS_SHORT = ['月', '火', '水', '木', '金', '土', '日']

const MEAL_TYPE_CHIPS = [
  { value: 'breakfast', label: '朝食' },
  { value: 'lunch', label: '昼食' },
  { value: 'dinner', label: '夕食' },
  { value: 'snack', label: '間食' },
]

interface MealTabProps {
  mealRecords: MealRecord[]
}

export function MealTab({ mealRecords }: MealTabProps) {
  const [period, setPeriod] = useState<MealPeriod>('today')
  const [displayMonth, setDisplayMonth] = useState(new Date())
  const [selectedImageUrl, setSelectedImageUrl] = useState<string | null>(null)
  const [selectedMealTypes, setSelectedMealTypes] = useState<Set<string>>(new Set())
  const [viewMode, setViewMode] = useState<'list' | 'gallery'>('list')

  const toggleMealType = (value: string) => {
    setSelectedMealTypes((prev) => {
      const next = new Set(prev)
      if (next.has(value)) {
        next.delete(value)
      } else {
        next.add(value)
      }
      return next
    })
  }

  const filteredMeals = useMemo(() => {
    if (mealRecords.length === 0) return []
    const now = new Date()
    let startDate: Date
    let endDate: Date | null = null
    switch (period) {
      case 'today':
        startDate = startOfDay(now)
        break
      case 'week':
        startDate = startOfWeek(now, { weekStartsOn: 1 })
        break
      case 'month':
        startDate = startOfMonth(displayMonth)
        endDate = endOfMonth(displayMonth)
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
      .filter((m) => {
        const d = new Date(m.recorded_at)
        const inRange = endDate ? d >= startDate && d <= endDate : d >= startDate
        if (!inRange) return false
        if (selectedMealTypes.size > 0 && !selectedMealTypes.has(m.meal_type)) return false
        return true
      })
      .sort((a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime())
  }, [mealRecords, period, displayMonth, selectedMealTypes])

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

  // サマリー計算（全期間で表示）
  const summary = useMemo(() => {
    const totalMeals = filteredMeals.length
    const totalCalories = filteredMeals.reduce((sum, m) => sum + (m.calories || 0), 0)
    const avgCalories = totalMeals > 0 ? Math.round(totalCalories / totalMeals) : 0
    const totalPhotos = filteredMeals.reduce((sum, m) => sum + (m.images?.length || 0), 0)
    return { totalMeals, totalCalories, avgCalories, totalPhotos }
  }, [filteredMeals])

  return (
    <div>
      {/* 期間フィルター + ビュー切替 */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex space-x-1.5">
          {MEAL_PERIOD_BUTTONS.map((btn) => (
            <button
              key={btn.value}
              onClick={() => setPeriod(btn.value)}
              className={`px-3 py-1 text-xs font-medium rounded-md transition-colors ${
                period === btn.value
                  ? 'bg-[#14B8A6] text-white'
                  : 'bg-[#F8FAFC] text-[#64748B] border border-[#E2E8F0] hover:border-[#14B8A6]'
              }`}
            >
              {btn.label}
            </button>
          ))}
        </div>
        {/* リスト/ギャラリー切替（週・月以外で有効） */}
        {period !== 'week' && period !== 'month' && (
          <div className="flex items-center gap-1 border border-[#E2E8F0] rounded-md p-0.5">
            <button
              onClick={() => setViewMode('list')}
              className={`px-2 py-1 text-xs rounded transition-colors ${
                viewMode === 'list'
                  ? 'bg-white border border-[#E2E8F0] text-[#0F172A] font-medium'
                  : 'text-[#94A3B8]'
              }`}
            >
              リスト
            </button>
            <button
              onClick={() => setViewMode('gallery')}
              className={`px-2 py-1 text-xs rounded transition-colors ${
                viewMode === 'gallery'
                  ? 'bg-white border border-[#E2E8F0] text-[#0F172A] font-medium'
                  : 'text-[#94A3B8]'
              }`}
            >
              ギャラリー
            </button>
          </div>
        )}
      </div>

      {/* 食事種別フィルターチップ */}
      <div className="flex items-center gap-2 mb-4">
        <span className="text-xs text-[#94A3B8]">種別:</span>
        {MEAL_TYPE_CHIPS.map((chip) => (
          <button
            key={chip.value}
            onClick={() => toggleMealType(chip.value)}
            className={`px-2.5 py-1 text-xs font-medium rounded-md transition-colors ${
              selectedMealTypes.has(chip.value)
                ? 'bg-[#F0FDFA] text-[#14B8A6] border border-[#CCFBF1]'
                : 'bg-[#F8FAFC] text-[#64748B] border border-[#E2E8F0] hover:border-[#14B8A6]'
            }`}
          >
            {chip.label}
          </button>
        ))}
      </div>

      {/* サマリーバー（常時表示） */}
      <div className="grid grid-cols-4 gap-3 mb-4">
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
          <p className="text-lg font-bold text-[#0F172A]">{summary.totalMeals}</p>
          <p className="text-[11px] text-[#94A3B8]">食事数</p>
        </div>
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
          <p className="text-lg font-bold text-[#0F172A]">{summary.totalCalories}</p>
          <p className="text-[11px] text-[#94A3B8]">合計カロリー</p>
        </div>
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
          <p className="text-lg font-bold text-[#0F172A]">{summary.avgCalories}</p>
          <p className="text-[11px] text-[#94A3B8]">平均カロリー</p>
        </div>
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
          <p className="text-lg font-bold text-[#0F172A]">{summary.totalPhotos}</p>
          <p className="text-[11px] text-[#94A3B8]">写真数</p>
        </div>
      </div>

      {/* 週カレンダー */}
      {period === 'week' && <WeekCalendar meals={mealRecords} />}

      {/* 月カレンダー */}
      {period === 'month' && <MonthCalendar meals={mealRecords} displayMonth={displayMonth} setDisplayMonth={setDisplayMonth} />}

      {/* 食事一覧（週・月カレンダー表示時は非表示） */}
      {period !== 'week' && period !== 'month' && groupedMeals.length > 0 ? (
        viewMode === 'gallery' ? (
          /* ギャラリーモード */
          <div className="max-h-[500px] overflow-y-auto custom-scrollbar">
            <div className="grid grid-cols-3 gap-2">
              {filteredMeals.map((meal) => (
                <div key={meal.id} className="bg-white border border-[#E2E8F0] rounded-md overflow-hidden">
                  {meal.images && meal.images.length > 0 ? (
                    <button
                      type="button"
                      onClick={() => setSelectedImageUrl(meal.images![0])}
                      className="relative w-full aspect-square"
                    >
                      <Image src={meal.images![0]} alt="" fill className="object-cover" unoptimized />
                      {meal.images!.length > 1 && (
                        <span className="absolute bottom-1 right-1 bg-black/60 text-white text-[10px] px-1 rounded">
                          +{meal.images!.length - 1}
                        </span>
                      )}
                    </button>
                  ) : (
                    <div className="w-full aspect-square bg-[#F8FAFC] flex items-center justify-center">
                      <span className="text-3xl">{MEAL_EMOJI[meal.meal_type] || '🍽️'}</span>
                    </div>
                  )}
                  <div className="p-2">
                    <p className="text-[11px] font-medium text-[#0F172A]">{MEAL_TYPE_OPTIONS[meal.meal_type]}</p>
                    <p className="text-[10px] text-[#94A3B8]">{format(new Date(meal.recorded_at), 'M/d H:mm')}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ) : (
          /* リストモード */
          <div className="max-h-[500px] overflow-y-auto custom-scrollbar space-y-6">
            {groupedMeals.map((group) => (
              <div key={group.dateKey}>
                {/* 日付ヘッダー */}
                <div className="mb-3">
                  <h4 className="font-semibold text-sm text-[#0F172A]">{group.label}</h4>
                  <div className="border-b border-[#E2E8F0] mt-1" />
                </div>
                {/* その日の食事カード */}
                <div className="space-y-3">
                  {group.meals.map((meal) => {
                    const hasImage = meal.images && meal.images.length > 0
                    return (
                      <div key={meal.id} className="bg-white border border-[#E2E8F0] rounded-md p-4">
                        {/* 上段: 食事種別・時刻 */}
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-sm text-[#0F172A]">{MEAL_TYPE_OPTIONS[meal.meal_type]}</span>
                          <span className="text-xs text-[#94A3B8]">
                            {format(new Date(meal.recorded_at), 'H:mm')}
                          </span>
                          {meal.calories != null && (
                            <span className="ml-auto text-xs font-medium text-[#F59E0B]">{meal.calories} kcal</span>
                          )}
                        </div>
                        {meal.notes && (
                          <div className="mt-2 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-center gap-2">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0">
                              <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                            </svg>
                            <p className="text-sm text-[#64748B] whitespace-pre-wrap leading-tight">{meal.notes}</p>
                          </div>
                        )}

                        {/* 下段: 写真セクション */}
                        {hasImage && (
                          <>
                            <div className="border-t border-dashed border-[#E2E8F0] mt-3 pt-3" />
                            <div className="flex gap-2">
                              {meal.images!.map((url, imgIndex) => (
                                <button
                                  key={imgIndex}
                                  type="button"
                                  onClick={() => setSelectedImageUrl(url)}
                                  className="relative w-24 h-24 rounded-md overflow-hidden bg-[#F8FAFC] cursor-pointer hover:opacity-80 transition-opacity"
                                >
                                  <Image
                                    src={url}
                                    alt={`食事画像 ${imgIndex + 1}`}
                                    fill
                                    className="object-cover"
                                    unoptimized
                                  />
                                </button>
                              ))}
                            </div>
                          </>
                        )}
                      </div>
                    )
                  })}
                </div>
              </div>
            ))}
          </div>
        )
      ) : period !== 'week' && period !== 'month' ? (
        <p className="text-[#94A3B8] text-sm">
          {mealRecords.length === 0 ? 'まだ食事記録がありません' : '選択した期間にデータがありません'}
        </p>
      ) : null}
      <ImageModal imageUrl={selectedImageUrl} onClose={() => setSelectedImageUrl(null)} />
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
  const [selectedImageUrl, setSelectedImageUrl] = useState<string | null>(null)
  const hoverTimeout = useRef<NodeJS.Timeout | null>(null)

  const scheduleClosePopup = useCallback(() => {
    hoverTimeout.current = setTimeout(() => setHoveredMeal(null), 150)
  }, [])

  const cancelClosePopup = useCallback(() => {
    if (hoverTimeout.current) {
      clearTimeout(hoverTimeout.current)
      hoverTimeout.current = null
    }
  }, [])

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
    cancelClosePopup()
    const rect = e.currentTarget.getBoundingClientRect()
    setHoverPos({ x: rect.left + rect.width / 2, y: rect.top })
    setHoveredMeal(meal)
  }

  return (
    <div className="mb-4">
      <h4 className="font-semibold text-sm text-[#0F172A] mb-3">{rangeLabel}</h4>
      <div className="grid grid-cols-7 gap-px bg-[#E2E8F0] rounded-md overflow-hidden border border-[#E2E8F0] relative">
        {days.map((day, i) => {
          const key = format(day, 'yyyy-MM-dd')
          const dayMeals = mealsByDay.get(key) || []
          const today = isToday(day)
          return (
            <div key={key} className="bg-white flex flex-col min-h-[200px]">
              {/* 日付ヘッダー */}
              <div className={`text-center py-1.5 text-xs font-bold border-b ${today ? 'bg-[#14B8A6] text-white' : 'bg-[#F8FAFC] text-[#64748B]'}`}>
                {format(day, 'M/d')} {WEEKDAY_LABELS_SHORT[i]}
              </div>
              {/* 食事カード */}
              <div className="flex-1 p-1 space-y-1 overflow-y-auto custom-scrollbar">
                {dayMeals.length > 0 ? dayMeals.map((meal) => {
                  const hasImage = meal.images && meal.images.length > 0
                  return (
                    <div
                      key={meal.id}
                      className={`rounded-md border p-1 cursor-pointer transition-colors ${today ? 'border-[#CCFBF1]' : 'border-[#E2E8F0]'} hover:border-[#14B8A6]`}
                      onMouseEnter={(e) => handleMouseEnter(meal, e)}
                      onMouseLeave={scheduleClosePopup}
                    >
                      {hasImage ? (
                        <button
                          type="button"
                          onClick={() => setSelectedImageUrl(meal.images![0])}
                          className="relative w-full aspect-square rounded overflow-hidden bg-[#F8FAFC] cursor-pointer hover:opacity-80 transition-opacity"
                        >
                          <Image src={meal.images![0]} alt="" fill className="object-cover" unoptimized />
                          {meal.images!.length > 1 && (
                            <span className="absolute bottom-1 right-1 bg-black/60 text-white text-[10px] font-bold rounded px-1 py-0.5">
                              +{meal.images!.length - 1}
                            </span>
                          )}
                        </button>
                      ) : (
                        <div className="w-full aspect-square rounded bg-[#F8FAFC] flex items-center justify-center">
                          <span className="text-2xl">{MEAL_EMOJI[meal.meal_type] || '🍽️'}</span>
                        </div>
                      )}
                      <p className="text-[10px] text-[#64748B] mt-1 truncate">
                        {MEAL_TYPE_OPTIONS[meal.meal_type]} {format(new Date(meal.recorded_at), 'H:mm')}
                      </p>
                    </div>
                  )
                }) : (
                  <p className="text-[10px] text-[#94A3B8] text-center mt-8">記録が<br />ありません</p>
                )}
              </div>
            </div>
          )
        })}
      </div>
      {/* ホバーポップアップ */}
      {hoveredMeal && (
        <div
          className="fixed z-50 bg-white rounded-md border border-[#E2E8F0] p-3 w-72"
          style={{ left: Math.min(hoverPos.x - 144, window.innerWidth - 300), top: hoverPos.y - 10, transform: 'translateY(-100%)' }}
          onMouseEnter={cancelClosePopup}
          onMouseLeave={scheduleClosePopup}
        >
          {hoveredMeal.images && hoveredMeal.images.length > 0 && (
            <div className="flex gap-1.5 mb-2">
              {hoveredMeal.images.map((url, i) => (
                <button
                  key={i}
                  type="button"
                  onClick={() => setSelectedImageUrl(url)}
                  className="relative flex-1 aspect-square rounded-md overflow-hidden bg-[#F8FAFC] cursor-pointer hover:opacity-80 transition-opacity"
                >
                  <Image src={url} alt="" fill className="object-cover" unoptimized />
                </button>
              ))}
            </div>
          )}
          <p className="text-xs text-[#94A3B8]">
            {MEAL_TYPE_OPTIONS[hoveredMeal.meal_type]} {format(new Date(hoveredMeal.recorded_at), 'H:mm')}
          </p>
          {hoveredMeal.notes && (
            <p className="text-sm font-semibold text-[#0F172A] mt-0.5">{hoveredMeal.notes}</p>
          )}
        </div>
      )}
      <ImageModal imageUrl={selectedImageUrl} onClose={() => setSelectedImageUrl(null)} />
    </div>
  )
}

// --- 月カレンダー（カレンダー + 日別記録 横並び） ---
function MonthCalendar({ meals, displayMonth, setDisplayMonth }: { meals: MealRecord[]; displayMonth: Date; setDisplayMonth: (d: Date | ((prev: Date) => Date)) => void }) {
  const now = new Date()
  const [selectedDate, setSelectedDate] = useState<string>(format(now, 'yyyy-MM-dd'))
  const [selectedImageUrl, setSelectedImageUrl] = useState<string | null>(null)

  const monthStart = startOfMonth(displayMonth)
  const monthEnd = endOfMonth(displayMonth)
  const days = eachDayOfInterval({ start: monthStart, end: monthEnd })
  const firstDayOfWeek = (monthStart.getDay() + 6) % 7

  // 全食事データから日別にグループ化（カウント＋画像取得用）
  const monthMealsByDay = useMemo(() => {
    const map = new Map<string, MealRecord[]>()
    for (const meal of meals) {
      const key = format(new Date(meal.recorded_at), 'yyyy-MM-dd')
      if (!map.has(key)) map.set(key, [])
      map.get(key)!.push(meal)
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
    if (isToday(day)) return `bg-green-600 text-white ${isSelected ? 'ring-2 ring-[#14B8A6]' : ''}`
    if (isSelected) return 'ring-2 ring-green-700 bg-green-200 text-gray-800'
    if (count >= 3) return 'bg-green-600 text-white'
    if (count === 2) return 'bg-green-500 text-white'
    if (count === 1) return 'bg-green-200 text-gray-700'
    if (isBefore(day, startOfDay(now))) return 'bg-[#F1F5F9] text-[#94A3B8]'
    return 'text-[#94A3B8]'
  }

  const prevMonth = () => setDisplayMonth((d) => new Date(d.getFullYear(), d.getMonth() - 1, 1))
  const nextMonth = () => setDisplayMonth((d) => new Date(d.getFullYear(), d.getMonth() + 1, 1))

  const selectedLabel = format(new Date(selectedDate + 'T00:00:00'), 'M月d日')

  return (
    <div className="space-y-4 mb-4">
      {/* 上段: カレンダー（全幅） */}
      <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md p-4">
        {/* ヘッダー */}
        <div className="flex justify-between items-center mb-3">
          <button onClick={prevMonth} className="text-[#94A3B8] hover:text-[#0F172A] px-2 py-1">‹</button>
          <h4 className="font-semibold text-sm text-[#0F172A]">{format(displayMonth, 'yyyy年M月')}</h4>
          <button onClick={nextMonth} className="text-[#94A3B8] hover:text-[#0F172A] px-2 py-1">›</button>
        </div>
        {/* 曜日 */}
        <div className="grid grid-cols-7 text-center mb-1">
          {WEEKDAY_LABELS_SHORT.map((label, i) => (
            <span key={i} className="text-xs text-[#94A3B8] font-medium">{label}</span>
          ))}
        </div>
        {/* 日付グリッド */}
        <div className="grid grid-cols-7 gap-1">
          {Array.from({ length: firstDayOfWeek }).map((_, i) => (
            <div key={`empty-${i}`} />
          ))}
          {days.map((day) => {
            const key = format(day, 'yyyy-MM-dd')
            const dayMeals = monthMealsByDay.get(key) || []
            const count = dayMeals.length
            return (
              <button
                key={key}
                onClick={() => setSelectedDate(key)}
                className={`rounded-md flex flex-col items-center justify-center p-1 cursor-pointer transition-all min-h-[60px] ${getDayColor(count, day)}`}
              >
                <span className="text-xs font-medium">{format(day, 'd')}</span>
                {count > 0 && (
                  <span className="text-[10px] mt-0.5 opacity-75">{count}食</span>
                )}
              </button>
            )
          })}
        </div>
        {/* 凡例 */}
        <div className="flex justify-end items-center gap-3 mt-3 text-xs text-[#94A3B8]">
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-green-600 inline-block" /> 3+</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-green-500 inline-block" /> 2</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-green-200 inline-block" /> 1</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-[#F1F5F9] inline-block" /> 0</span>
        </div>
      </div>

      {/* 下段: 選択日の記録リスト */}
      <div>
        <h4 className="font-semibold text-sm text-[#0F172A] mb-3">{selectedLabel}の記録</h4>
        {selectedDayMeals.length > 0 ? (
          <div className="space-y-3 max-h-[400px] overflow-y-auto custom-scrollbar">
            {selectedDayMeals.map((meal) => {
              const hasImage = meal.images && meal.images.length > 0
              return (
                <div key={meal.id} className="bg-white border border-[#E2E8F0] rounded-md p-4">
                  {/* 上段: 食事種別・時刻 */}
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-sm text-[#0F172A]">{MEAL_TYPE_OPTIONS[meal.meal_type]}</span>
                    <span className="text-xs text-[#94A3B8]">
                      {format(new Date(meal.recorded_at), 'H:mm')}
                    </span>
                    {meal.calories != null && (
                      <span className="ml-auto text-xs font-medium text-[#F59E0B]">{meal.calories} kcal</span>
                    )}
                  </div>
                  {meal.notes && (
                    <div className="mt-2 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-center gap-2">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0">
                        <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                      </svg>
                      <p className="text-sm text-[#64748B] whitespace-pre-wrap leading-tight">{meal.notes}</p>
                    </div>
                  )}

                  {/* 下段: 写真セクション */}
                  {hasImage && (
                    <>
                      <div className="border-t border-dashed border-[#E2E8F0] mt-3 pt-3" />
                      <div className="flex gap-2">
                        {meal.images!.map((url, imgIndex) => (
                          <button
                            key={imgIndex}
                            type="button"
                            onClick={() => setSelectedImageUrl(url)}
                            className="relative w-24 h-24 rounded-md overflow-hidden bg-[#F8FAFC] cursor-pointer hover:opacity-80 transition-opacity"
                          >
                            <Image
                              src={url}
                              alt={`食事画像 ${imgIndex + 1}`}
                              fill
                              className="object-cover"
                              unoptimized
                            />
                          </button>
                        ))}
                      </div>
                    </>
                  )}
                </div>
              )
            })}
          </div>
        ) : (
          <p className="text-sm text-[#94A3B8]">記録がありません</p>
        )}
      </div>
      <ImageModal imageUrl={selectedImageUrl} onClose={() => setSelectedImageUrl(null)} />
    </div>
  )
}
