'use client'

import { useState, useMemo } from 'react'
import { startOfDay, startOfWeek, endOfWeek, startOfMonth, endOfMonth, subMonths, format, isToday, isYesterday, eachDayOfInterval, isBefore } from 'date-fns'
import { ja } from 'date-fns/locale'
import { EXERCISE_TYPE_OPTIONS } from '@/types/client'
import type { ExerciseRecord } from '@/types/client'
import type { WorkoutAssignment } from '@/types/workout'
import { WORKOUT_CATEGORY_OPTIONS, ASSIGNMENT_STATUS_OPTIONS, ASSIGNMENT_STATUS_COLORS } from '@/types/workout'

type ExercisePeriod = 'today' | 'week' | 'month' | '3months' | 'all'

type MergedExerciseItem =
  | { type: 'workout'; date: string; data: WorkoutAssignment }
  | { type: 'exercise'; date: string; data: ExerciseRecord }

const EXERCISE_PERIOD_BUTTONS: { label: string; value: ExercisePeriod }[] = [
  { label: '本日', value: 'today' },
  { label: '今週', value: 'week' },
  { label: '今月', value: 'month' },
  { label: '3ヶ月', value: '3months' },
  { label: '全期間', value: 'all' },
]

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

const WEEKDAY_LABELS_SHORT = ['月', '火', '水', '木', '金', '土', '日']

interface ExerciseTabProps {
  exerciseRecords: ExerciseRecord[]
  workoutAssignments: WorkoutAssignment[]
}

export function ExerciseTab({ exerciseRecords, workoutAssignments }: ExerciseTabProps) {
  const [period, setPeriod] = useState<ExercisePeriod>('today')
  const [displayMonth, setDisplayMonth] = useState(new Date())

  // 期間フィルタリング（運動記録）
  const filteredExercises = useMemo(() => {
    if (exerciseRecords.length === 0) return []
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
    return exerciseRecords
      .filter((e) => {
        const d = new Date(e.recorded_at)
        if (endDate) return d >= startDate && d <= endDate
        return d >= startDate
      })
      .sort((a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime())
  }, [exerciseRecords, period, displayMonth])

  // 期間フィルタリング（ワークアウトアサインメント）
  const filteredAssignments = useMemo(() => {
    if (workoutAssignments.length === 0) return []
    const now = new Date()
    const todayStr = format(now, 'yyyy-MM-dd')

    return workoutAssignments.filter((a) => {
      switch (period) {
        case 'today':
          return a.assigned_date === todayStr
        case 'week': {
          const weekStartStr = format(startOfWeek(now, { weekStartsOn: 1 }), 'yyyy-MM-dd')
          const weekEndStr = format(endOfWeek(now, { weekStartsOn: 1 }), 'yyyy-MM-dd')
          return a.assigned_date >= weekStartStr && a.assigned_date <= weekEndStr
        }
        case 'month': {
          const monthStartStr = format(startOfMonth(displayMonth), 'yyyy-MM-dd')
          const monthEndStr = format(endOfMonth(displayMonth), 'yyyy-MM-dd')
          return a.assigned_date >= monthStartStr && a.assigned_date <= monthEndStr
        }
        case '3months': {
          const threeMonthsAgoStr = format(subMonths(now, 3), 'yyyy-MM-dd')
          return a.assigned_date >= threeMonthsAgoStr
        }
        case 'all':
        default:
          return true
      }
    }).sort((a, b) => b.assigned_date.localeCompare(a.assigned_date))
  }, [workoutAssignments, period, displayMonth])

  // ワークアウトアサインメントと運動記録を統合して日付でグループ化
  const mergedGroups = useMemo(() => {
    const items: MergedExerciseItem[] = []

    for (const a of filteredAssignments) {
      items.push({ type: 'workout', date: a.assigned_date, data: a })
    }

    for (const e of filteredExercises) {
      items.push({ type: 'exercise', date: format(new Date(e.recorded_at), 'yyyy-MM-dd'), data: e })
    }

    const map = new Map<string, MergedExerciseItem[]>()
    for (const item of items) {
      if (!map.has(item.date)) map.set(item.date, [])
      map.get(item.date)!.push(item)
    }

    const groups: { dateKey: string; label: string; items: MergedExerciseItem[] }[] = []
    const sortedKeys = [...map.keys()].sort((a, b) => b.localeCompare(a))

    for (const key of sortedKeys) {
      const d = new Date(key + 'T00:00:00')
      let label: string
      if (isToday(d)) label = 'Today'
      else if (isYesterday(d)) label = 'Yesterday'
      else label = format(d, 'M月d日 (E)', { locale: ja })

      const groupItems = map.get(key)!
      groupItems.sort((a, b) => {
        if (a.type !== b.type) return a.type === 'workout' ? -1 : 1
        return 0
      })

      groups.push({ dateKey: key, label, items: groupItems })
    }

    return groups
  }, [filteredAssignments, filteredExercises])

  // Today's Summary（本日のみ表示）
  const summary = useMemo(() => {
    if (period !== 'today') return null
    const totalExercises = filteredExercises.length
    const totalDuration = filteredExercises.reduce(
      (sum, e) => sum + (e.duration || 0), 0
    )
    const totalCalories = filteredExercises.reduce(
      (sum, e) => sum + (e.calories || 0), 0
    )
    return { totalExercises, totalDuration, totalCalories }
  }, [filteredExercises, period])

  return (
    <div>
      {/* 期間フィルター */}
      <div className="flex justify-end mb-4">
        <div className="flex space-x-2">
          {EXERCISE_PERIOD_BUTTONS.map((btn) => (
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
                <span className="text-xl">🏃</span>
              </div>
              <p className="text-lg font-bold">{summary.totalExercises}</p>
              <p className="text-xs text-gray-500">回</p>
            </div>
            <div>
              <div className="w-12 h-12 rounded-xl bg-green-50 flex items-center justify-center mx-auto mb-1">
                <span className="text-xl">⏱️</span>
              </div>
              <p className="text-lg font-bold">{summary.totalDuration}</p>
              <p className="text-xs text-gray-500">分</p>
            </div>
            <div>
              <div className="w-12 h-12 rounded-xl bg-orange-50 flex items-center justify-center mx-auto mb-1">
                <span className="text-xl">🔥</span>
              </div>
              <p className="text-lg font-bold">{summary.totalCalories}</p>
              <p className="text-xs text-gray-500">kcal</p>
            </div>
          </div>
        </div>
      )}

      {/* 週カレンダー */}
      {period === 'week' && <WeekCalendar exercises={exerciseRecords} />}

      {/* 月カレンダー */}
      {period === 'month' && <MonthCalendar exercises={exerciseRecords} displayMonth={displayMonth} setDisplayMonth={setDisplayMonth} />}

      {/* 統合運動一覧 */}
      <div>
        {mergedGroups.length > 0 ? (
          <div className="space-y-6">
            {mergedGroups.map((group) => (
              <div key={group.dateKey}>
                {/* 日付ヘッダー */}
                <div className="mb-3">
                  <h4 className="font-bold text-base">{group.label}</h4>
                  <div className="border-b border-gray-200 mt-1" />
                </div>
                {/* 統合アイテムリスト */}
                <div className="space-y-3">
                  {group.items.map((item) => {
                    if (item.type === 'workout') {
                      const assignment = item.data
                      const statusColor = ASSIGNMENT_STATUS_COLORS[assignment.status]
                      const sortedExercises = assignment.exercises
                        ? [...assignment.exercises].sort((a, b) => a.order_index - b.order_index)
                        : []

                      return (
                        <div
                          key={`workout-${assignment.id}`}
                          className="rounded-xl bg-white shadow-sm border border-gray-100 p-4"
                        >
                          {/* カードヘッダー */}
                          <div className="flex items-start justify-between mb-2">
                            <div className="flex items-center gap-2">
                              <span className="text-base">🏋️</span>
                              <span className="font-bold text-sm text-gray-800">
                                {assignment.plan?.title ?? 'ワークアウト'}
                              </span>
                            </div>
                            <span
                              className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${statusColor.bg} ${statusColor.text}`}
                            >
                              <span>{statusColor.icon}</span>
                              {ASSIGNMENT_STATUS_OPTIONS[assignment.status]}
                            </span>
                          </div>

                          {/* カテゴリ・目安時間 */}
                          <div className="flex items-center gap-3 text-xs text-gray-500 mb-3">
                            {assignment.plan?.category && (
                              <span>
                                カテゴリ: {WORKOUT_CATEGORY_OPTIONS[assignment.plan.category as keyof typeof WORKOUT_CATEGORY_OPTIONS] ?? assignment.plan.category}
                              </span>
                            )}
                            {assignment.plan?.estimated_minutes && (
                              <span>目安: {assignment.plan.estimated_minutes}分</span>
                            )}
                          </div>

                          {/* 種目リスト */}
                          {sortedExercises.length > 0 && (
                            <div className="space-y-2 mb-3">
                              {sortedExercises.map((exercise) => {
                                const actualSets = exercise.actual_sets ?? []
                                const isCompleted = exercise.is_completed

                                return (
                                  <div
                                    key={exercise.id}
                                    className="rounded-lg border border-gray-100 bg-gray-50 p-3"
                                  >
                                    {/* 種目名 */}
                                    <div className="flex items-center justify-between mb-1">
                                      <span className="font-medium text-sm text-gray-800">
                                        {exercise.exercise_name}
                                      </span>
                                      <span className={`text-xs font-medium ${isCompleted ? 'text-green-600' : 'text-gray-400'}`}>
                                        {isCompleted ? '✅ 完了' : '未完了'}
                                      </span>
                                    </div>

                                    {/* 目標 */}
                                    <p className="text-xs text-gray-500 mb-2">
                                      目標: {exercise.target_sets}セット × {exercise.target_reps}回
                                      {exercise.target_weight !== null && ` × ${exercise.target_weight}kg`}
                                    </p>

                                    {/* 実際のセット記録 */}
                                    {actualSets.length > 0 ? (
                                      <div className="space-y-1">
                                        <div className="border-t border-gray-200 pt-1" />
                                        {actualSets.map((set) => (
                                          <div key={set.set_number} className="flex items-center gap-2 text-xs text-gray-600">
                                            <span className="w-10 font-medium text-gray-500">
                                              Set {set.set_number}:
                                            </span>
                                            <span>
                                              {set.weight !== null ? `${set.weight}kg` : '-'}
                                              {' × '}
                                              {set.reps !== null ? `${set.reps}回` : '-'}
                                            </span>
                                            {set.done && (
                                              <span className="text-green-500 font-bold">✓</span>
                                            )}
                                          </div>
                                        ))}
                                      </div>
                                    ) : (
                                      <p className="text-xs text-gray-400 pt-1 border-t border-gray-200">実績なし</p>
                                    )}
                                  </div>
                                )
                              })}
                            </div>
                          )}

                          {/* クライアントフィードバック */}
                          {assignment.client_feedback && (
                            <div className="mt-2 pt-2 border-t border-gray-100">
                              <p className="text-xs text-gray-500 mb-1">💬 クライアントフィードバック:</p>
                              <p className="text-sm text-gray-700 whitespace-pre-wrap">{assignment.client_feedback}</p>
                            </div>
                          )}
                        </div>
                      )
                    }

                    // item.type === 'exercise'
                    const record = item.data
                    return (
                      <div
                        key={`exercise-${record.id}`}
                        className="rounded-xl bg-white shadow-sm border border-gray-100 p-4 flex gap-4"
                      >
                        {/* 運動Emoji */}
                        <div className="flex-shrink-0">
                          <div className="w-12 h-12 bg-blue-50 rounded-lg flex items-center justify-center text-2xl">
                            {EXERCISE_EMOJI[record.exercise_type]}
                          </div>
                        </div>

                        {/* 運動詳細 */}
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <span className="font-bold text-sm">{EXERCISE_TYPE_OPTIONS[record.exercise_type]}</span>
                            <span className="text-xs text-gray-500">
                              {format(new Date(record.recorded_at), 'H:mm')}
                            </span>
                          </div>
                          <div className="flex flex-wrap gap-3 text-sm text-gray-600 mt-1">
                            {record.duration !== null && (
                              <span>時間: {record.duration}分</span>
                            )}
                            {record.distance !== null && (
                              <span>距離: {record.distance}km</span>
                            )}
                            {record.calories !== null && (
                              <span className="text-orange-600 font-semibold">{record.calories}kcal</span>
                            )}
                          </div>
                          {record.memo && (
                            <p className="mt-2 text-sm text-gray-700 whitespace-pre-wrap">{record.memo}</p>
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
            {workoutAssignments.length === 0 && exerciseRecords.length === 0
              ? 'まだ運動記録がありません'
              : '選択した期間にデータがありません'}
          </p>
        )}
      </div>
    </div>
  )
}

// --- 週カレンダー（7カラムレイアウト） ---
function WeekCalendar({ exercises }: { exercises: ExerciseRecord[] }) {
  const now = new Date()
  const weekStart = startOfWeek(now, { weekStartsOn: 1 })
  const weekEnd = endOfWeek(now, { weekStartsOn: 1 })
  const days = eachDayOfInterval({ start: weekStart, end: weekEnd })
  const rangeLabel = `${format(weekStart, 'M月d日')}〜${format(weekEnd, 'M月d日')}`

  // 日別にグループ
  const exercisesByDay = useMemo(() => {
    const map = new Map<string, ExerciseRecord[]>()
    for (const day of days) {
      map.set(format(day, 'yyyy-MM-dd'), [])
    }
    for (const exercise of exercises) {
      const key = format(new Date(exercise.recorded_at), 'yyyy-MM-dd')
      if (map.has(key)) map.get(key)!.push(exercise)
    }
    // 各日を時刻降順でソート
    for (const [, dayExercises] of map) {
      dayExercises.sort((a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime())
    }
    return map
  }, [exercises, days])

  return (
    <div className="mb-4">
      <h4 className="font-bold text-sm mb-3">{rangeLabel}</h4>
      <div className="grid grid-cols-7 gap-px bg-gray-200 rounded-xl overflow-hidden border border-gray-200">
        {days.map((day, i) => {
          const key = format(day, 'yyyy-MM-dd')
          const dayExercises = exercisesByDay.get(key) || []
          const today = isToday(day)
          return (
            <div key={key} className="bg-white flex flex-col min-h-[200px]">
              {/* 日付ヘッダー */}
              <div className={`text-center py-1.5 text-xs font-bold border-b ${today ? 'bg-blue-600 text-white' : 'bg-gray-50 text-gray-700'}`}>
                {format(day, 'M/d')} {WEEKDAY_LABELS_SHORT[i]}
              </div>
              {/* 運動カード */}
              <div className="flex-1 p-1 space-y-1 overflow-y-auto custom-scrollbar">
                {dayExercises.length > 0 ? dayExercises.map((exercise) => (
                  <div
                    key={exercise.id}
                    className={`rounded-md border p-2 ${today ? 'border-blue-300' : 'border-gray-100'}`}
                  >
                    <div className="w-full aspect-square rounded bg-gray-100 flex items-center justify-center mb-1">
                      <span className="text-2xl">{EXERCISE_EMOJI[exercise.exercise_type]}</span>
                    </div>
                    <p className="text-[10px] text-gray-600 truncate">
                      {EXERCISE_TYPE_OPTIONS[exercise.exercise_type]}
                    </p>
                    <p className="text-[10px] text-gray-500">
                      {format(new Date(exercise.recorded_at), 'H:mm')}
                    </p>
                    {exercise.duration !== null && (
                      <p className="text-[10px] text-gray-600">⏱️ {exercise.duration}分</p>
                    )}
                  </div>
                )) : (
                  <p className="text-[10px] text-gray-400 text-center mt-8">記録が<br />ありません</p>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

// --- 月カレンダー（カレンダー + 日別記録 横並び） ---
function MonthCalendar({ exercises, displayMonth, setDisplayMonth }: { exercises: ExerciseRecord[]; displayMonth: Date; setDisplayMonth: (d: Date | ((prev: Date) => Date)) => void }) {
  const now = new Date()
  const [selectedDate, setSelectedDate] = useState<string>(format(now, 'yyyy-MM-dd'))

  const monthStart = startOfMonth(displayMonth)
  const monthEnd = endOfMonth(displayMonth)
  const days = eachDayOfInterval({ start: monthStart, end: monthEnd })
  const firstDayOfWeek = (monthStart.getDay() + 6) % 7

  // 全運動データから日別カウント（表示月用）
  const monthExerciseCount = useMemo(() => {
    const map = new Map<string, number>()
    for (const exercise of exercises) {
      const key = format(new Date(exercise.recorded_at), 'yyyy-MM-dd')
      map.set(key, (map.get(key) || 0) + 1)
    }
    return map
  }, [exercises])

  // 選択日の運動
  const selectedDayExercises = useMemo(() => {
    return exercises
      .filter((e) => format(new Date(e.recorded_at), 'yyyy-MM-dd') === selectedDate)
      .sort((a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime())
  }, [exercises, selectedDate])

  const getDayColor = (count: number, day: Date) => {
    const key = format(day, 'yyyy-MM-dd')
    const isSelected = key === selectedDate
    if (isToday(day)) return `bg-blue-600 text-white ${isSelected ? 'ring-2 ring-blue-500' : ''}`
    if (isSelected) return 'ring-2 ring-blue-700 bg-blue-200 text-gray-800'
    if (count >= 3) return 'bg-blue-600 text-white'
    if (count === 2) return 'bg-blue-500 text-white'
    if (count === 1) return 'bg-blue-200 text-gray-700'
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
            const count = monthExerciseCount.get(key) || 0
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
          <span className="flex items-center gap-0.5"><span className="w-2.5 h-2.5 rounded-sm bg-blue-600 inline-block" /> 3+</span>
          <span className="flex items-center gap-0.5"><span className="w-2.5 h-2.5 rounded-sm bg-blue-500 inline-block" /> 2</span>
          <span className="flex items-center gap-0.5"><span className="w-2.5 h-2.5 rounded-sm bg-blue-200 inline-block" /> 1</span>
          <span className="flex items-center gap-0.5"><span className="w-2.5 h-2.5 rounded-sm bg-gray-200 inline-block" /> 0</span>
        </div>
      </div>

      {/* 右: 選択日の記録 */}
      <div className="flex-1 min-w-0">
        <h4 className="font-bold text-sm mb-2">{selectedLabel}の記録</h4>
        {selectedDayExercises.length > 0 ? (
          <div className="space-y-2 max-h-[320px] overflow-y-auto custom-scrollbar">
            {selectedDayExercises.map((record) => (
              <div key={record.id} className="rounded-lg bg-white shadow-sm border border-gray-100 p-3 flex gap-3">
                <div className="w-16 h-16 rounded-md bg-blue-50 flex items-center justify-center flex-shrink-0">
                  <span className="text-2xl">{EXERCISE_EMOJI[record.exercise_type]}</span>
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-xs text-gray-500">
                    {EXERCISE_TYPE_OPTIONS[record.exercise_type]} {format(new Date(record.recorded_at), 'H:mm')}
                  </p>
                  <div className="flex flex-wrap gap-2 text-xs text-gray-600 mt-1">
                    {record.duration !== null && (
                      <span>時間: {record.duration}分</span>
                    )}
                    {record.distance !== null && (
                      <span>距離: {record.distance}km</span>
                    )}
                    {record.calories !== null && (
                      <span className="text-orange-600 font-semibold">{record.calories}kcal</span>
                    )}
                  </div>
                  {record.memo && <p className="text-xs text-gray-700 mt-1 truncate">{record.memo}</p>}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-gray-400 mt-8">記録がありません</p>
        )}
      </div>
    </div>
  )
}
