'use client'

import { useState, useMemo, useRef, useCallback } from 'react'
import { startOfDay, startOfWeek, endOfWeek, startOfMonth, endOfMonth, format, isToday, isYesterday, eachDayOfInterval, isBefore } from 'date-fns'
import { ja } from 'date-fns/locale'
import { EXERCISE_TYPE_OPTIONS } from '@/types/client'
import type { ExerciseRecord } from '@/types/client'
import type { WorkoutAssignment } from '@/types/workout'
import { WORKOUT_CATEGORY_OPTIONS, ASSIGNMENT_STATUS_OPTIONS, ASSIGNMENT_STATUS_COLORS } from '@/types/workout'

type ExercisePeriod = 'today' | 'week' | 'month'

type MergedExerciseItem =
  | { type: 'workout'; date: string; data: WorkoutAssignment }
  | { type: 'exercise'; date: string; data: ExerciseRecord }

const EXERCISE_PERIOD_BUTTONS: { label: string; value: ExercisePeriod }[] = [
  { label: '本日', value: 'today' },
  { label: '今週', value: 'week' },
  { label: '今月', value: 'month' },
]

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

  // 本日のサマリー（本日のみ表示）
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

      {/* 本日のサマリー */}
      {summary && (
        <div className="rounded-xl bg-gray-50 border border-gray-100 p-4 mb-4">
          <h4 className="font-bold text-sm mb-3">本日のサマリー</h4>
          <div className="grid grid-cols-3 text-center">
            <div>
              <div className="w-12 h-12 rounded-xl bg-blue-50 flex items-center justify-center mx-auto mb-1">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-blue-500">
                  <rect x="2" y="9" width="4" height="6" rx="1" />
                  <rect x="18" y="9" width="4" height="6" rx="1" />
                  <rect x="6" y="7" width="4" height="10" rx="1" />
                  <rect x="14" y="7" width="4" height="10" rx="1" />
                  <line x1="10" y1="12" x2="14" y2="12" />
                </svg>
              </div>
              <p className="text-lg font-bold">{summary.totalExercises}</p>
              <p className="text-xs text-gray-500">運動数</p>
            </div>
            <div>
              <div className="w-12 h-12 rounded-xl bg-green-50 flex items-center justify-center mx-auto mb-1">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-green-500">
                  <circle cx="12" cy="12" r="10" />
                  <polyline points="12 6 12 12 16 14" />
                </svg>
              </div>
              <p className="text-lg font-bold">{summary.totalDuration}</p>
              <p className="text-xs text-gray-500">運動時間(分)</p>
            </div>
            <div>
              <div className="w-12 h-12 rounded-xl bg-orange-50 flex items-center justify-center mx-auto mb-1">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-orange-500">
                  <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                </svg>
              </div>
              <p className="text-lg font-bold">{summary.totalCalories}</p>
              <p className="text-xs text-gray-500">消費カロリー(kcal)</p>
            </div>
          </div>
        </div>
      )}

      {/* 週カレンダー */}
      {period === 'week' && <WeekCalendar exercises={exerciseRecords} workoutAssignments={workoutAssignments} />}

      {/* 月カレンダー */}
      {period === 'month' && <MonthCalendar exercises={exerciseRecords} workoutAssignments={workoutAssignments} displayMonth={displayMonth} setDisplayMonth={setDisplayMonth} />}

      {/* 統合運動一覧（週・月カレンダー表示時は非表示） */}
      {period !== 'week' && period !== 'month' && (
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
                              <div className="mt-3 bg-gray-100 rounded-lg px-3 py-2 flex items-center gap-2">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400 flex-shrink-0">
                                  <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                                </svg>
                                <p className="text-sm text-gray-700 whitespace-pre-wrap leading-tight">{assignment.client_feedback}</p>
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
                          className="rounded-xl bg-white shadow-sm border border-gray-100 p-4"
                        >
                          {/* 上段: 種別名と時刻 */}
                          <div className="flex items-center justify-between">
                            <span className="font-bold text-sm">{EXERCISE_TYPE_OPTIONS[record.exercise_type]}</span>
                            <span className="text-xs text-gray-500">
                              {format(new Date(record.recorded_at), 'H:mm')}
                            </span>
                          </div>

                          {/* メタ情報: 時間・距離 */}
                          <div className="flex flex-wrap gap-3 text-sm text-gray-600 mt-1">
                            {record.duration !== null && (
                              <span>時間: {record.duration}分</span>
                            )}
                            {record.distance !== null && (
                              <span>距離: {record.distance}km</span>
                            )}
                          </div>

                          {/* カロリー */}
                          {record.calories !== null && (
                            <div className="flex items-center gap-1 mt-1">
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-orange-500">
                                <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                              </svg>
                              <span className="text-sm text-orange-600 font-semibold">{record.calories}kcal</span>
                            </div>
                          )}

                          {/* メモ */}
                          {record.memo && (
                            <>
                              <div className="border-t border-dashed border-gray-200 mt-2" />
                              <div className="mt-2 bg-gray-100 rounded-lg px-3 py-2 flex items-center gap-2">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400 flex-shrink-0">
                                  <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                                </svg>
                                <p className="text-sm text-gray-700 whitespace-pre-wrap leading-tight">{record.memo}</p>
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
          ) : (
            <p className="text-gray-500">
              {workoutAssignments.length === 0 && exerciseRecords.length === 0
                ? 'まだ運動記録がありません'
                : '選択した期間にデータがありません'}
            </p>
          )}
        </div>
      )}
    </div>
  )
}

// --- 週カレンダー（7カラムレイアウト） ---
function WeekCalendar({ exercises, workoutAssignments }: { exercises: ExerciseRecord[]; workoutAssignments: WorkoutAssignment[] }) {
  const now = new Date()
  const weekStart = startOfWeek(now, { weekStartsOn: 1 })
  const weekEnd = endOfWeek(now, { weekStartsOn: 1 })
  const days = eachDayOfInterval({ start: weekStart, end: weekEnd })
  const rangeLabel = `${format(weekStart, 'M月d日')}〜${format(weekEnd, 'M月d日')}`

  type HoveredItem =
    | { type: 'workout'; data: WorkoutAssignment }
    | { type: 'exercise'; data: ExerciseRecord }
  const [hoveredItem, setHoveredItem] = useState<HoveredItem | null>(null)
  const [hoverPos, setHoverPos] = useState<{ x: number; y: number }>({ x: 0, y: 0 })
  const hoverTimeout = useRef<NodeJS.Timeout | null>(null)

  const scheduleClosePopup = useCallback(() => {
    hoverTimeout.current = setTimeout(() => setHoveredItem(null), 150)
  }, [])
  const cancelClosePopup = useCallback(() => {
    if (hoverTimeout.current) {
      clearTimeout(hoverTimeout.current)
      hoverTimeout.current = null
    }
  }, [])

  const handleMouseEnter = (item: HoveredItem, e: React.MouseEvent) => {
    cancelClosePopup()
    const rect = e.currentTarget.getBoundingClientRect()
    setHoverPos({ x: rect.left + rect.width / 2, y: rect.top })
    setHoveredItem(item)
  }

  // 日別にグループ（運動記録）
  const exercisesByDay = useMemo(() => {
    const map = new Map<string, ExerciseRecord[]>()
    for (const day of days) {
      map.set(format(day, 'yyyy-MM-dd'), [])
    }
    for (const exercise of exercises) {
      const key = format(new Date(exercise.recorded_at), 'yyyy-MM-dd')
      if (map.has(key)) map.get(key)!.push(exercise)
    }
    for (const [, dayExercises] of map) {
      dayExercises.sort((a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime())
    }
    return map
  }, [exercises, days])

  // 日別にグループ（ワークアウト）
  const assignmentsByDay = useMemo(() => {
    const map = new Map<string, WorkoutAssignment[]>()
    for (const day of days) {
      map.set(format(day, 'yyyy-MM-dd'), [])
    }
    for (const a of workoutAssignments) {
      if (map.has(a.assigned_date)) map.get(a.assigned_date)!.push(a)
    }
    return map
  }, [workoutAssignments, days])

  return (
    <div className="mb-4">
      <h4 className="font-bold text-sm mb-3">{rangeLabel}</h4>
      <div className="grid grid-cols-7 gap-px bg-gray-200 rounded-xl overflow-hidden border border-gray-200 relative">
        {days.map((day, i) => {
          const key = format(day, 'yyyy-MM-dd')
          const dayExercises = exercisesByDay.get(key) || []
          const dayAssignments = assignmentsByDay.get(key) || []
          const hasItems = dayExercises.length > 0 || dayAssignments.length > 0
          const today = isToday(day)
          return (
            <div key={key} className="bg-white flex flex-col min-h-[200px]">
              {/* 日付ヘッダー */}
              <div className={`text-center py-1.5 text-xs font-bold border-b ${today ? 'bg-blue-600 text-white' : 'bg-gray-50 text-gray-700'}`}>
                {format(day, 'M/d')} {WEEKDAY_LABELS_SHORT[i]}
              </div>
              {/* カード */}
              <div className="flex-1 p-1 space-y-1 overflow-y-auto custom-scrollbar">
                {/* ワークアウト */}
                {dayAssignments.map((a) => {
                  const statusColor = ASSIGNMENT_STATUS_COLORS[a.status]
                  const sortedEx = a.exercises
                    ? [...a.exercises].sort((x, y) => x.order_index - y.order_index)
                    : []
                  return (
                    <div
                      key={`w-${a.id}`}
                      className={`rounded-md border p-2 cursor-pointer hover:shadow-md transition-shadow ${today ? 'border-blue-300' : 'border-gray-100'}`}
                      onMouseEnter={(e) => handleMouseEnter({ type: 'workout', data: a }, e)}
                      onMouseLeave={scheduleClosePopup}
                    >
                      <p className="text-[10px] text-gray-700 font-medium truncate">
                        {a.plan?.title ?? 'ワークアウト'}
                      </p>
                      <div className="flex items-center gap-1 mt-0.5">
                        <span className={`inline-block px-1 py-0.5 rounded text-[9px] font-medium ${statusColor.bg} ${statusColor.text}`}>
                          {statusColor.icon} {ASSIGNMENT_STATUS_OPTIONS[a.status]}
                        </span>
                        {a.plan?.estimated_minutes && (
                          <span className="text-[9px] text-gray-400">{a.plan.estimated_minutes}分</span>
                        )}
                      </div>
                      {sortedEx.length > 0 && (
                        <div className="mt-1 space-y-1 border-t border-gray-100 pt-1">
                          {sortedEx.map((ex) => (
                            <div key={ex.id}>
                              <p className={`text-[9px] leading-tight ${ex.is_completed ? 'text-green-600 font-medium' : 'text-gray-600'}`}>
                                {ex.is_completed ? '✓ ' : '・'}{ex.exercise_name}
                              </p>
                              <p className="text-[8px] text-gray-400 ml-2">
                                {ex.target_sets}×{ex.target_reps}回{ex.target_weight !== null ? ` ${ex.target_weight}kg` : ''}
                              </p>
                            </div>
                          ))}
                        </div>
                      )}
                      {a.client_feedback && (
                        <p className="text-[9px] text-gray-500 mt-1 border-t border-gray-100 pt-1 line-clamp-2">
                          💬 {a.client_feedback}
                        </p>
                      )}
                    </div>
                  )
                })}
                {/* 運動記録 */}
                {dayExercises.map((exercise) => (
                  <div
                    key={exercise.id}
                    className={`rounded-md border p-2 cursor-pointer hover:shadow-md transition-shadow ${today ? 'border-blue-300' : 'border-gray-100'}`}
                    onMouseEnter={(e) => handleMouseEnter({ type: 'exercise', data: exercise }, e)}
                    onMouseLeave={scheduleClosePopup}
                  >
                    <p className="text-[10px] text-gray-700 font-medium truncate">
                      {EXERCISE_TYPE_OPTIONS[exercise.exercise_type]}
                    </p>
                    <p className="text-[10px] text-gray-500">
                      {format(new Date(exercise.recorded_at), 'H:mm')}
                    </p>
                    {exercise.duration !== null && (
                      <p className="text-[10px] text-gray-600">{exercise.duration}分</p>
                    )}
                    {exercise.distance !== null && (
                      <p className="text-[10px] text-gray-600">{exercise.distance}km</p>
                    )}
                    {exercise.calories !== null && (
                      <p className="text-[10px] text-orange-500 font-medium">{exercise.calories}kcal</p>
                    )}
                    {exercise.memo && (
                      <p className="text-[9px] text-gray-500 mt-1 border-t border-gray-100 pt-1 line-clamp-2">{exercise.memo}</p>
                    )}
                  </div>
                ))}
                {!hasItems && (
                  <p className="text-[10px] text-gray-400 text-center mt-8">記録が<br />ありません</p>
                )}
              </div>
            </div>
          )
        })}
      </div>

      {/* ホバーポップアップ */}
      {hoveredItem && (
        <div
          className="fixed z-50 bg-white rounded-xl shadow-xl border border-gray-200 p-4 w-80 max-h-[400px] overflow-y-auto"
          style={{ left: Math.min(hoverPos.x - 160, window.innerWidth - 340), top: hoverPos.y - 10, transform: 'translateY(-100%)' }}
          onMouseEnter={cancelClosePopup}
          onMouseLeave={scheduleClosePopup}
        >
          {hoveredItem.type === 'workout' ? (() => {
            const a = hoveredItem.data
            const statusColor = ASSIGNMENT_STATUS_COLORS[a.status]
            const sortedEx = a.exercises
              ? [...a.exercises].sort((x, y) => x.order_index - y.order_index)
              : []
            return (
              <>
                {/* ヘッダー */}
                <div className="flex items-start justify-between mb-2">
                  <span className="font-bold text-sm text-gray-800">{a.plan?.title ?? 'ワークアウト'}</span>
                  <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${statusColor.bg} ${statusColor.text}`}>
                    <span>{statusColor.icon}</span>
                    {ASSIGNMENT_STATUS_OPTIONS[a.status]}
                  </span>
                </div>
                {/* カテゴリ・目安時間 */}
                <div className="flex items-center gap-3 text-xs text-gray-500 mb-3">
                  {a.plan?.category && (
                    <span>カテゴリ: {WORKOUT_CATEGORY_OPTIONS[a.plan.category as keyof typeof WORKOUT_CATEGORY_OPTIONS] ?? a.plan.category}</span>
                  )}
                  {a.plan?.estimated_minutes && (
                    <span>目安: {a.plan.estimated_minutes}分</span>
                  )}
                </div>
                {/* 種目リスト */}
                {sortedEx.length > 0 && (
                  <div className="space-y-2 mb-2">
                    {sortedEx.map((ex) => {
                      const actualSets = ex.actual_sets ?? []
                      return (
                        <div key={ex.id} className="rounded-lg border border-gray-100 bg-gray-50 p-2.5">
                          <div className="flex items-center justify-between mb-1">
                            <span className="font-medium text-xs text-gray-800">{ex.exercise_name}</span>
                            <span className={`text-[10px] font-medium ${ex.is_completed ? 'text-green-600' : 'text-gray-400'}`}>
                              {ex.is_completed ? '✅ 完了' : '未完了'}
                            </span>
                          </div>
                          <p className="text-[10px] text-gray-500 mb-1">
                            目標: {ex.target_sets}セット × {ex.target_reps}回{ex.target_weight !== null ? ` × ${ex.target_weight}kg` : ''}
                          </p>
                          {actualSets.length > 0 && (
                            <div className="space-y-0.5 border-t border-gray-200 pt-1">
                              {actualSets.map((set) => (
                                <div key={set.set_number} className="flex items-center gap-2 text-[10px] text-gray-600">
                                  <span className="w-8 font-medium text-gray-500">Set {set.set_number}:</span>
                                  <span>{set.weight !== null ? `${set.weight}kg` : '-'} × {set.reps !== null ? `${set.reps}回` : '-'}</span>
                                  {set.done && <span className="text-green-500 font-bold">✓</span>}
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                )}
                {/* フィードバック */}
                {a.client_feedback && (
                  <div className="bg-gray-100 rounded-lg px-3 py-2 flex items-start gap-2">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400 flex-shrink-0 mt-0.5">
                      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                    </svg>
                    <p className="text-sm text-gray-700 whitespace-pre-wrap leading-tight">{a.client_feedback}</p>
                  </div>
                )}
              </>
            )
          })() : (() => {
            const r = hoveredItem.data
            return (
              <>
                <div className="flex items-center justify-between mb-1">
                  <span className="font-bold text-sm">{EXERCISE_TYPE_OPTIONS[r.exercise_type]}</span>
                  <span className="text-xs text-gray-500">{format(new Date(r.recorded_at), 'H:mm')}</span>
                </div>
                <div className="flex flex-wrap gap-3 text-sm text-gray-600 mt-1">
                  {r.duration !== null && <span>時間: {r.duration}分</span>}
                  {r.distance !== null && <span>距離: {r.distance}km</span>}
                </div>
                {r.calories !== null && (
                  <div className="flex items-center gap-1 mt-1">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-orange-500">
                      <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                    </svg>
                    <span className="text-sm text-orange-600 font-semibold">{r.calories}kcal</span>
                  </div>
                )}
                {r.memo && (
                  <div className="mt-2 bg-gray-100 rounded-lg px-3 py-2 flex items-start gap-2">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400 flex-shrink-0 mt-0.5">
                      <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                    </svg>
                    <p className="text-sm text-gray-700 whitespace-pre-wrap leading-tight">{r.memo}</p>
                  </div>
                )}
              </>
            )
          })()}
        </div>
      )}
    </div>
  )
}

// --- 月カレンダー（カレンダー上、リスト下の縦配置） ---
function MonthCalendar({ exercises, workoutAssignments, displayMonth, setDisplayMonth }: { exercises: ExerciseRecord[]; workoutAssignments: WorkoutAssignment[]; displayMonth: Date; setDisplayMonth: (d: Date | ((prev: Date) => Date)) => void }) {
  const now = new Date()
  const [selectedDate, setSelectedDate] = useState<string>(format(now, 'yyyy-MM-dd'))

  const monthStart = startOfMonth(displayMonth)
  const monthEnd = endOfMonth(displayMonth)
  const days = eachDayOfInterval({ start: monthStart, end: monthEnd })
  const firstDayOfWeek = (monthStart.getDay() + 6) % 7

  // 全運動データから日別カウント（表示月用 - 運動記録+ワークアウト）
  const monthExerciseCount = useMemo(() => {
    const map = new Map<string, number>()
    for (const exercise of exercises) {
      const key = format(new Date(exercise.recorded_at), 'yyyy-MM-dd')
      map.set(key, (map.get(key) || 0) + 1)
    }
    for (const a of workoutAssignments) {
      map.set(a.assigned_date, (map.get(a.assigned_date) || 0) + 1)
    }
    return map
  }, [exercises, workoutAssignments])

  // 選択日の運動
  const selectedDayExercises = useMemo(() => {
    return exercises
      .filter((e) => format(new Date(e.recorded_at), 'yyyy-MM-dd') === selectedDate)
      .sort((a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime())
  }, [exercises, selectedDate])

  // 選択日のワークアウト
  const selectedDayAssignments = useMemo(() => {
    return workoutAssignments.filter((a) => a.assigned_date === selectedDate)
  }, [workoutAssignments, selectedDate])

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
    <div className="space-y-4 mb-4">
      {/* 上段: カレンダー（全幅） */}
      <div className="rounded-xl bg-gray-50 border border-gray-100 p-4">
        {/* ヘッダー */}
        <div className="flex justify-between items-center mb-3">
          <button onClick={prevMonth} className="text-gray-500 hover:text-gray-800 px-2 py-1">‹</button>
          <h4 className="font-bold text-sm">{format(displayMonth, 'yyyy年M月')}</h4>
          <button onClick={nextMonth} className="text-gray-500 hover:text-gray-800 px-2 py-1">›</button>
        </div>
        {/* 曜日 */}
        <div className="grid grid-cols-7 text-center mb-1">
          {WEEKDAY_LABELS_SHORT.map((label, i) => (
            <span key={i} className="text-xs text-gray-400 font-medium">{label}</span>
          ))}
        </div>
        {/* 日付グリッド */}
        <div className="grid grid-cols-7 gap-1">
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
                className={`rounded-lg flex flex-col items-center justify-center p-1 cursor-pointer transition-all min-h-[60px] ${getDayColor(count, day)}`}
              >
                <span className="text-xs font-medium">{format(day, 'd')}</span>
                {count > 0 && (
                  <span className="text-[10px] mt-0.5 opacity-75">{count}回</span>
                )}
              </button>
            )
          })}
        </div>
        {/* 凡例 */}
        <div className="flex justify-end items-center gap-3 mt-3 text-xs text-gray-500">
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-blue-600 inline-block" /> 3+</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-blue-500 inline-block" /> 2</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-blue-200 inline-block" /> 1</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-gray-200 inline-block" /> 0</span>
        </div>
      </div>

      {/* 下段: 選択日の記録リスト */}
      <div>
        <h4 className="font-bold text-base mb-3">{selectedLabel}の記録</h4>
        {selectedDayAssignments.length > 0 || selectedDayExercises.length > 0 ? (
          <div className="space-y-3 max-h-[400px] overflow-y-auto custom-scrollbar">
            {/* ワークアウト */}
            {selectedDayAssignments.map((assignment) => {
              const statusColor = ASSIGNMENT_STATUS_COLORS[assignment.status]
              const sortedExercises = assignment.exercises
                ? [...assignment.exercises].sort((a, b) => a.order_index - b.order_index)
                : []
              return (
                <div key={`w-${assignment.id}`} className="rounded-xl bg-white shadow-sm border border-gray-100 p-4">
                  <div className="flex items-start justify-between mb-2">
                    <span className="font-bold text-sm text-gray-800">
                      {assignment.plan?.title ?? 'ワークアウト'}
                    </span>
                    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${statusColor.bg} ${statusColor.text}`}>
                      <span>{statusColor.icon}</span>
                      {ASSIGNMENT_STATUS_OPTIONS[assignment.status]}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 text-xs text-gray-500 mb-3">
                    {assignment.plan?.category && (
                      <span>カテゴリ: {WORKOUT_CATEGORY_OPTIONS[assignment.plan.category as keyof typeof WORKOUT_CATEGORY_OPTIONS] ?? assignment.plan.category}</span>
                    )}
                    {assignment.plan?.estimated_minutes && (
                      <span>目安: {assignment.plan.estimated_minutes}分</span>
                    )}
                  </div>
                  {sortedExercises.length > 0 && (
                    <div className="space-y-2">
                      {sortedExercises.map((exercise) => {
                        const actualSets = exercise.actual_sets ?? []
                        return (
                          <div key={exercise.id} className="rounded-lg border border-gray-100 bg-gray-50 p-3">
                            <div className="flex items-center justify-between mb-1">
                              <span className="font-medium text-sm text-gray-800">{exercise.exercise_name}</span>
                              <span className={`text-xs font-medium ${exercise.is_completed ? 'text-green-600' : 'text-gray-400'}`}>
                                {exercise.is_completed ? '✅ 完了' : '未完了'}
                              </span>
                            </div>
                            <p className="text-xs text-gray-500 mb-2">
                              目標: {exercise.target_sets}セット × {exercise.target_reps}回
                              {exercise.target_weight !== null && ` × ${exercise.target_weight}kg`}
                            </p>
                            {actualSets.length > 0 ? (
                              <div className="space-y-1">
                                <div className="border-t border-gray-200 pt-1" />
                                {actualSets.map((set) => (
                                  <div key={set.set_number} className="flex items-center gap-2 text-xs text-gray-600">
                                    <span className="w-10 font-medium text-gray-500">Set {set.set_number}:</span>
                                    <span>
                                      {set.weight !== null ? `${set.weight}kg` : '-'} × {set.reps !== null ? `${set.reps}回` : '-'}
                                    </span>
                                    {set.done && <span className="text-green-500 font-bold">✓</span>}
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
                  {assignment.client_feedback && (
                    <div className="mt-3 bg-gray-100 rounded-lg px-3 py-2 flex items-center gap-2">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400 flex-shrink-0">
                        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                      </svg>
                      <p className="text-sm text-gray-700 whitespace-pre-wrap leading-tight">{assignment.client_feedback}</p>
                    </div>
                  )}
                </div>
              )
            })}
            {/* 運動記録 */}
            {selectedDayExercises.map((record) => (
              <div key={record.id} className="rounded-xl bg-white shadow-sm border border-gray-100 p-4">
                {/* 上段: 種別名と時刻 */}
                <div className="flex items-center justify-between">
                  <span className="font-bold text-sm">{EXERCISE_TYPE_OPTIONS[record.exercise_type]}</span>
                  <span className="text-xs text-gray-500">
                    {format(new Date(record.recorded_at), 'H:mm')}
                  </span>
                </div>

                {/* メタ情報: 時間・距離 */}
                <div className="flex flex-wrap gap-3 text-sm text-gray-600 mt-1">
                  {record.duration !== null && (
                    <span>時間: {record.duration}分</span>
                  )}
                  {record.distance !== null && (
                    <span>距離: {record.distance}km</span>
                  )}
                </div>

                {/* カロリー */}
                {record.calories !== null && (
                  <div className="flex items-center gap-1 mt-1">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-orange-500">
                      <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                    </svg>
                    <span className="text-sm text-orange-600 font-semibold">{record.calories}kcal</span>
                  </div>
                )}

                {/* メモ */}
                {record.memo && (
                  <>
                    <div className="border-t border-dashed border-gray-200 mt-2" />
                    <div className="mt-2 bg-gray-100 rounded-lg px-3 py-2 flex items-center gap-2">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400 flex-shrink-0">
                        <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                      </svg>
                      <p className="text-sm text-gray-700 whitespace-pre-wrap leading-tight">{record.memo}</p>
                    </div>
                  </>
                )}
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-gray-400">記録がありません</p>
        )}
      </div>
    </div>
  )
}
