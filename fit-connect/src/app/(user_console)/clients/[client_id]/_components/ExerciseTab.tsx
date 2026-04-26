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

  // サマリー計算（全期間で表示）
  const summary = useMemo(() => {
    const totalExercises = filteredExercises.length + filteredAssignments.length
    const totalDuration = filteredExercises.reduce((sum, e) => sum + (e.duration || 0), 0)
    const totalCalories =
      filteredExercises.reduce((sum, e) => sum + (e.calories || 0), 0) +
      filteredAssignments.reduce((sum, a) => sum + (a.calories || 0), 0)
    const completedAssignments = filteredAssignments.filter((a) => a.status === 'completed').length
    const completionRate =
      filteredAssignments.length > 0
        ? Math.round((completedAssignments / filteredAssignments.length) * 100)
        : null
    return { totalExercises, totalDuration, totalCalories, completionRate }
  }, [filteredExercises, filteredAssignments])

  return (
    <div>
      {/* 期間フィルター */}
      <div className="flex justify-end mb-4">
        <div className="flex space-x-1.5">
          {EXERCISE_PERIOD_BUTTONS.map((btn) => (
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
      </div>

      {/* サマリーバー（全期間で表示） */}
      <div className="grid grid-cols-4 gap-3 mb-4">
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
          <p className="text-lg font-bold text-[#0F172A]">{summary.totalExercises}</p>
          <p className="text-[11px] text-[#94A3B8]">運動数</p>
        </div>
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
          <p className="text-lg font-bold text-[#0F172A]">
            {summary.totalDuration}
            <span className="text-xs text-[#94A3B8] ml-0.5">分</span>
          </p>
          <p className="text-[11px] text-[#94A3B8]">合計時間</p>
        </div>
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
          <p className="text-lg font-bold text-[#0F172A]">
            {summary.totalCalories}
            <span className="text-xs text-[#94A3B8] ml-0.5">kcal</span>
          </p>
          <p className="text-[11px] text-[#94A3B8]">消費カロリー</p>
        </div>
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
          <p className="text-lg font-bold text-[#0F172A]">
            {summary.completionRate !== null ? `${summary.completionRate}%` : '--'}
          </p>
          <p className="text-[11px] text-[#94A3B8]">完了率</p>
        </div>
      </div>

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
                    <h4 className="font-semibold text-sm text-[#0F172A]">{group.label}</h4>
                    <div className="border-b border-[#E2E8F0] mt-1" />
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
                            className="bg-white border border-[#E2E8F0] rounded-md overflow-hidden"
                          >
                            <div className="flex">
                              {/* 左アクセントバー */}
                              <div className="w-1 bg-[#14B8A6] flex-shrink-0" />
                              <div className="flex-1 p-4">
                                {/* カードヘッダー */}
                                <div className="flex items-start justify-between mb-2">
                                  <div className="flex items-center gap-2">
                                    <span className="text-sm">🏋️</span>
                                    <span className="inline-flex px-1.5 py-0.5 text-[10px] font-medium bg-[#F0FDFA] text-[#14B8A6] border border-[#CCFBF1] rounded">プラン</span>
                                    <span className="font-semibold text-sm text-[#0F172A]">
                                      {assignment.plan?.title ?? 'ワークアウト'}
                                    </span>
                                  </div>
                                  <span
                                    className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-medium ${statusColor.bg} ${statusColor.text}`}
                                  >
                                    <span className={`inline-block w-1.5 h-1.5 rounded-sm ${statusColor.dot}`} />
                                    {ASSIGNMENT_STATUS_OPTIONS[assignment.status]}
                                  </span>
                                </div>

                                {/* カテゴリ・目安時間 */}
                                <div className="flex items-center gap-3 text-xs text-[#94A3B8] mb-1">
                                  {assignment.plan?.category && (
                                    <span>
                                      カテゴリ: {WORKOUT_CATEGORY_OPTIONS[assignment.plan.category as keyof typeof WORKOUT_CATEGORY_OPTIONS] ?? assignment.plan.category}
                                    </span>
                                  )}
                                  {assignment.plan?.estimated_minutes && (
                                    <span>目安: {assignment.plan.estimated_minutes}分</span>
                                  )}
                                </div>

                                {/* カロリー */}
                                {assignment.calories != null && (
                                  <div className="flex items-center gap-1 mb-3">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#F59E0B]">
                                      <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                                    </svg>
                                    <span className="text-xs text-[#F59E0B] font-semibold">{assignment.calories}kcal</span>
                                  </div>
                                )}
                                {assignment.calories == null && <div className="mb-2" />}

                                {/* 種目リスト */}
                                {sortedExercises.length > 0 && (
                                  <div className="space-y-2 mb-3">
                                    {sortedExercises.map((exercise) => {
                                      const actualSets = exercise.actual_sets ?? []
                                      const isCompleted = exercise.is_completed

                                      return (
                                        <div
                                          key={exercise.id}
                                          className="rounded-md border border-[#E2E8F0] bg-[#F8FAFC] p-3"
                                        >
                                          {/* 種目名 */}
                                          <div className="flex items-center justify-between mb-1">
                                            <span className="font-medium text-sm text-[#0F172A]">
                                              {exercise.exercise_name}
                                            </span>
                                            <span className={`text-xs font-medium ${isCompleted ? 'text-[#16A34A]' : 'text-[#94A3B8]'}`}>
                                              {isCompleted ? (
                                                <>
                                                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" className="inline text-[#16A34A]" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                                                    <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                                                    <polyline points="22 4 12 14.01 9 11.01" />
                                                  </svg>
                                                  {' '}完了
                                                </>
                                              ) : '未完了'}
                                            </span>
                                          </div>

                                          {/* 目標 */}
                                          <p className="text-xs text-[#94A3B8] mb-2">
                                            目標: {exercise.target_sets}セット × {exercise.target_reps}回
                                            {exercise.target_weight !== null && ` × ${exercise.target_weight}kg`}
                                          </p>

                                          {/* 実際のセット記録（2列グリッド） */}
                                          {actualSets.length > 0 ? (
                                            <div className="grid grid-cols-2 gap-1 mt-2 pt-2 border-t border-[#E2E8F0]">
                                              {actualSets.map((set) => (
                                                <div key={set.set_number} className="flex items-center gap-1.5 text-xs text-[#64748B] py-0.5">
                                                  <span className="text-[#94A3B8] font-medium w-8">S{set.set_number}</span>
                                                  <span>{set.weight ?? '-'}kg × {set.reps ?? '-'}回</span>
                                                  {set.done && <span className="text-[#16A34A] font-bold">✓</span>}
                                                </div>
                                              ))}
                                            </div>
                                          ) : (
                                            <p className="text-xs text-[#94A3B8] pt-1 border-t border-[#E2E8F0]">実績なし</p>
                                          )}

                                          {/* 種目メモ */}
                                          {exercise.memo && (
                                            <div className="flex items-start gap-1 mt-1.5 pt-1.5 border-t border-[#E2E8F0]">
                                              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0 mt-0.5">
                                                <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                                              </svg>
                                              <p className="text-xs text-[#64748B] whitespace-pre-wrap">{exercise.memo}</p>
                                            </div>
                                          )}
                                        </div>
                                      )
                                    })}
                                  </div>
                                )}

                                {/* トレーナーノート */}
                                {assignment.trainer_note && (
                                  <div className="mt-3 bg-[#F0FDFA] border border-[#CCFBF1] rounded-md px-3 py-2 flex items-start gap-2">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#14B8A6] flex-shrink-0 mt-0.5">
                                      <path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z" />
                                      <polyline points="14 2 14 8 20 8" />
                                      <line x1="16" y1="13" x2="8" y2="13" />
                                      <line x1="16" y1="17" x2="8" y2="17" />
                                      <line x1="10" y1="9" x2="8" y2="9" />
                                    </svg>
                                    <p className="text-sm text-[#14B8A6] whitespace-pre-wrap leading-tight">{assignment.trainer_note}</p>
                                  </div>
                                )}

                                {/* クライアントフィードバック */}
                                {assignment.client_feedback && (
                                  <div className="mt-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-start gap-2">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0 mt-0.5">
                                      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                                    </svg>
                                    <p className="text-sm text-[#64748B] whitespace-pre-wrap leading-tight">{assignment.client_feedback}</p>
                                  </div>
                                )}
                              </div>
                            </div>
                          </div>
                        )
                      }

                      // item.type === 'exercise'
                      const record = item.data
                      return (
                        <div
                          key={`exercise-${record.id}`}
                          className="bg-white border border-[#E2E8F0] rounded-md overflow-hidden"
                        >
                          <div className="flex">
                            {/* 左アクセントバー（グレー） */}
                            <div className="w-1 bg-[#E2E8F0] flex-shrink-0" />
                            <div className="flex-1 p-4">
                              <div className="flex items-center gap-2 mb-1">
                                <span className="inline-flex px-1.5 py-0.5 text-[10px] font-medium bg-[#F8FAFC] text-[#64748B] border border-[#E2E8F0] rounded">自由記録</span>
                                <span className="font-semibold text-sm text-[#0F172A]">{EXERCISE_TYPE_OPTIONS[record.exercise_type]}</span>
                                <span className="text-xs text-[#94A3B8] ml-auto">{format(new Date(record.recorded_at), 'H:mm')}</span>
                              </div>
                              <div className="flex items-center gap-4 text-xs text-[#64748B]">
                                {record.duration !== null && <span>⏱ {record.duration}分</span>}
                                {record.distance !== null && <span>📏 {record.distance}km</span>}
                                {record.calories !== null && (
                                  <span className="text-[#F59E0B] font-medium">🔥 {record.calories}kcal</span>
                                )}
                              </div>

                              {/* メモ */}
                              {record.memo && (
                                <div className="mt-2 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-center gap-2">
                                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0">
                                    <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                                  </svg>
                                  <p className="text-sm text-[#64748B] whitespace-pre-wrap leading-tight">{record.memo}</p>
                                </div>
                              )}
                            </div>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-[#94A3B8] text-sm">
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
      <h4 className="font-semibold text-sm text-[#0F172A] mb-3">{rangeLabel}</h4>
      <div className="grid grid-cols-7 gap-px bg-[#E2E8F0] rounded-md overflow-hidden border border-[#E2E8F0] relative">
        {days.map((day, i) => {
          const key = format(day, 'yyyy-MM-dd')
          const dayExercises = exercisesByDay.get(key) || []
          const dayAssignments = assignmentsByDay.get(key) || []
          const hasItems = dayExercises.length > 0 || dayAssignments.length > 0
          const today = isToday(day)
          return (
            <div key={key} className="bg-white flex flex-col min-h-[200px]">
              {/* 日付ヘッダー */}
              <div className={`text-center py-1.5 text-xs font-bold border-b ${today ? 'bg-[#14B8A6] text-white' : 'bg-[#F8FAFC] text-[#64748B]'}`}>
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
                      className={`rounded-md border p-2 cursor-pointer transition-colors ${today ? 'border-[#CCFBF1]' : 'border-[#E2E8F0]'} hover:border-[#14B8A6]`}
                      onMouseEnter={(e) => handleMouseEnter({ type: 'workout', data: a }, e)}
                      onMouseLeave={scheduleClosePopup}
                    >
                      <p className="text-[10px] text-[#0F172A] font-medium truncate">
                        {a.plan?.title ?? 'ワークアウト'}
                      </p>
                      <div className="flex items-center gap-1 mt-0.5">
                        <span className={`inline-flex items-center gap-0.5 px-1 py-0.5 rounded text-[9px] font-medium ${statusColor.bg} ${statusColor.text}`}>
                          <span className={`inline-block w-1.5 h-1.5 rounded-sm ${statusColor.dot}`} /> {ASSIGNMENT_STATUS_OPTIONS[a.status]}
                        </span>
                        {a.plan?.estimated_minutes && (
                          <span className="text-[9px] text-[#94A3B8]">{a.plan.estimated_minutes}分</span>
                        )}
                      </div>
                      {sortedEx.length > 0 && (
                        <div className="mt-1 space-y-1 border-t border-[#E2E8F0] pt-1">
                          {sortedEx.map((ex) => (
                            <div key={ex.id}>
                              <p className={`text-[9px] leading-tight ${ex.is_completed ? 'text-[#16A34A] font-medium' : 'text-[#64748B]'}`}>
                                {ex.is_completed ? '✓ ' : '・'}{ex.exercise_name}
                              </p>
                              <p className="text-[8px] text-[#94A3B8] ml-2">
                                {ex.target_sets}×{ex.target_reps}回{ex.target_weight !== null ? ` ${ex.target_weight}kg` : ''}
                              </p>
                            </div>
                          ))}
                        </div>
                      )}
                      {a.calories != null && (
                        <div className="flex items-center gap-0.5 mt-1">
                          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="text-[#F59E0B]">
                            <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                          </svg>
                          <span className="text-[9px] text-[#F59E0B] font-medium">{a.calories}kcal</span>
                        </div>
                      )}
                      {a.client_feedback && (
                        <div className="flex items-start gap-0.5 mt-1 border-t border-[#E2E8F0] pt-1">
                          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0 mt-px">
                            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                          </svg>
                          <p className="text-[9px] text-[#64748B] line-clamp-2">{a.client_feedback}</p>
                        </div>
                      )}
                    </div>
                  )
                })}
                {/* 運動記録 */}
                {dayExercises.map((exercise) => (
                  <div
                    key={exercise.id}
                    className={`rounded-md border p-2 cursor-pointer transition-colors ${today ? 'border-[#E2E8F0]' : 'border-[#E2E8F0]'} hover:border-[#14B8A6]`}
                    onMouseEnter={(e) => handleMouseEnter({ type: 'exercise', data: exercise }, e)}
                    onMouseLeave={scheduleClosePopup}
                  >
                    <p className="text-[10px] text-[#0F172A] font-medium truncate">
                      {EXERCISE_TYPE_OPTIONS[exercise.exercise_type]}
                    </p>
                    <p className="text-[10px] text-[#94A3B8]">
                      {format(new Date(exercise.recorded_at), 'H:mm')}
                    </p>
                    {exercise.duration !== null && (
                      <p className="text-[10px] text-[#64748B]">{exercise.duration}分</p>
                    )}
                    {exercise.distance !== null && (
                      <p className="text-[10px] text-[#64748B]">{exercise.distance}km</p>
                    )}
                    {exercise.memo && (
                      <p className="text-[9px] text-[#94A3B8] mt-1 border-t border-[#E2E8F0] pt-1 line-clamp-2">{exercise.memo}</p>
                    )}
                    {exercise.calories !== null && (
                      <div className="flex items-center gap-0.5 mt-1">
                        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="text-[#F59E0B]">
                          <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                        </svg>
                        <span className="text-[9px] text-[#F59E0B] font-medium">{exercise.calories}kcal</span>
                      </div>
                    )}
                  </div>
                ))}
                {!hasItems && (
                  <p className="text-[10px] text-[#94A3B8] text-center mt-8">記録が<br />ありません</p>
                )}
              </div>
            </div>
          )
        })}
      </div>

      {/* ホバーポップアップ */}
      {hoveredItem && (
        <div
          className="fixed z-50 bg-white rounded-md border border-[#E2E8F0] p-4 w-80 max-h-[400px] overflow-y-auto"
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
                  <span className="font-semibold text-sm text-[#0F172A]">{a.plan?.title ?? 'ワークアウト'}</span>
                  <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-medium ${statusColor.bg} ${statusColor.text}`}>
                    <span className={`inline-block w-1.5 h-1.5 rounded-sm ${statusColor.dot}`} />
                    {ASSIGNMENT_STATUS_OPTIONS[a.status]}
                  </span>
                </div>
                {/* カテゴリ・目安時間 */}
                <div className="flex items-center gap-3 text-xs text-[#94A3B8] mb-1">
                  {a.plan?.category && (
                    <span>カテゴリ: {WORKOUT_CATEGORY_OPTIONS[a.plan.category as keyof typeof WORKOUT_CATEGORY_OPTIONS] ?? a.plan.category}</span>
                  )}
                  {a.plan?.estimated_minutes && (
                    <span>目安: {a.plan.estimated_minutes}分</span>
                  )}
                </div>
                {/* カロリー */}
                {a.calories != null && (
                  <div className="flex items-center gap-1 mb-2">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#F59E0B]">
                      <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                    </svg>
                    <span className="text-xs text-[#F59E0B] font-semibold">{a.calories}kcal</span>
                  </div>
                )}
                {a.calories == null && <div className="mb-2" />}
                {/* 種目リスト */}
                {sortedEx.length > 0 && (
                  <div className="space-y-2 mb-2">
                    {sortedEx.map((ex) => {
                      const actualSets = ex.actual_sets ?? []
                      return (
                        <div key={ex.id} className="rounded-md border border-[#E2E8F0] bg-[#F8FAFC] p-2.5">
                          <div className="flex items-center justify-between mb-1">
                            <span className="font-medium text-xs text-[#0F172A]">{ex.exercise_name}</span>
                            <span className={`text-[10px] font-medium ${ex.is_completed ? 'text-[#16A34A]' : 'text-[#94A3B8]'}`}>
                              {ex.is_completed ? (
                                <>
                                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" className="inline text-[#16A34A]" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                                    <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                                    <polyline points="22 4 12 14.01 9 11.01" />
                                  </svg>
                                  {' '}完了
                                </>
                              ) : '未完了'}
                            </span>
                          </div>
                          <p className="text-[10px] text-[#94A3B8] mb-1">
                            目標: {ex.target_sets}セット × {ex.target_reps}回{ex.target_weight !== null ? ` × ${ex.target_weight}kg` : ''}
                          </p>
                          {actualSets.length > 0 && (
                            <div className="grid grid-cols-2 gap-1 border-t border-[#E2E8F0] pt-1">
                              {actualSets.map((set) => (
                                <div key={set.set_number} className="flex items-center gap-1.5 text-[10px] text-[#64748B]">
                                  <span className="text-[#94A3B8] font-medium w-6">S{set.set_number}</span>
                                  <span>{set.weight ?? '-'}kg × {set.reps ?? '-'}回</span>
                                  {set.done && <span className="text-[#16A34A] font-bold">✓</span>}
                                </div>
                              ))}
                            </div>
                          )}
                          {ex.memo && (
                            <div className="flex items-start gap-1 mt-1 pt-1 border-t border-[#E2E8F0]">
                              <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0 mt-0.5">
                                <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                              </svg>
                              <p className="text-[10px] text-[#64748B] whitespace-pre-wrap">{ex.memo}</p>
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                )}
                {/* トレーナーノート */}
                {a.trainer_note && (
                  <div className="bg-[#F0FDFA] border border-[#CCFBF1] rounded-md px-3 py-2 flex items-start gap-2 mb-1">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#14B8A6] flex-shrink-0 mt-0.5">
                      <path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z" />
                      <polyline points="14 2 14 8 20 8" />
                      <line x1="16" y1="13" x2="8" y2="13" />
                      <line x1="16" y1="17" x2="8" y2="17" />
                      <line x1="10" y1="9" x2="8" y2="9" />
                    </svg>
                    <p className="text-sm text-[#14B8A6] whitespace-pre-wrap leading-tight">{a.trainer_note}</p>
                  </div>
                )}
                {/* フィードバック */}
                {a.client_feedback && (
                  <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-start gap-2">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0 mt-0.5">
                      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                    </svg>
                    <p className="text-sm text-[#64748B] whitespace-pre-wrap leading-tight">{a.client_feedback}</p>
                  </div>
                )}
              </>
            )
          })() : (() => {
            const r = hoveredItem.data
            return (
              <>
                <div className="flex items-center justify-between mb-1">
                  <span className="font-semibold text-sm text-[#0F172A]">{EXERCISE_TYPE_OPTIONS[r.exercise_type]}</span>
                  <span className="text-xs text-[#94A3B8]">{format(new Date(r.recorded_at), 'H:mm')}</span>
                </div>
                <div className="flex flex-wrap gap-3 text-sm text-[#64748B] mt-1">
                  {r.duration !== null && <span>時間: {r.duration}分</span>}
                  {r.distance !== null && <span>距離: {r.distance}km</span>}
                </div>
                {r.calories !== null && (
                  <div className="flex items-center gap-1 mt-1">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#F59E0B]">
                      <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                    </svg>
                    <span className="text-sm text-[#F59E0B] font-semibold">{r.calories}kcal</span>
                  </div>
                )}
                {r.memo && (
                  <div className="mt-2 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-start gap-2">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0 mt-0.5">
                      <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                    </svg>
                    <p className="text-sm text-[#64748B] whitespace-pre-wrap leading-tight">{r.memo}</p>
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
    if (isToday(day)) return `bg-[#14B8A6] text-white ${isSelected ? 'ring-2 ring-[#0D9488]' : ''}`
    if (isSelected) return 'ring-2 ring-[#14B8A6] bg-[#CCFBF1] text-[#0F172A]'
    if (count >= 3) return 'bg-[#14B8A6] text-white'
    if (count === 2) return 'bg-[#2DD4BF] text-white'
    if (count === 1) return 'bg-[#CCFBF1] text-[#0F172A]'
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
            const count = monthExerciseCount.get(key) || 0
            return (
              <button
                key={key}
                onClick={() => setSelectedDate(key)}
                className={`rounded-md flex flex-col items-center justify-center p-1 cursor-pointer transition-all min-h-[60px] ${getDayColor(count, day)}`}
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
        <div className="flex justify-end items-center gap-3 mt-3 text-xs text-[#94A3B8]">
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-[#14B8A6] inline-block" /> 3+</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-[#2DD4BF] inline-block" /> 2</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-[#CCFBF1] inline-block" /> 1</span>
          <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-sm bg-[#F1F5F9] inline-block" /> 0</span>
        </div>
      </div>

      {/* 下段: 選択日の記録リスト */}
      <div>
        <h4 className="font-semibold text-sm text-[#0F172A] mb-3">{selectedLabel}の記録</h4>
        {selectedDayAssignments.length > 0 || selectedDayExercises.length > 0 ? (
          <div className="space-y-3 max-h-[400px] overflow-y-auto custom-scrollbar">
            {/* ワークアウト */}
            {selectedDayAssignments.map((assignment) => {
              const statusColor = ASSIGNMENT_STATUS_COLORS[assignment.status]
              const sortedExercises = assignment.exercises
                ? [...assignment.exercises].sort((a, b) => a.order_index - b.order_index)
                : []
              return (
                <div key={`w-${assignment.id}`} className="bg-white border border-[#E2E8F0] rounded-md overflow-hidden">
                  <div className="flex">
                    <div className="w-1 bg-[#14B8A6] flex-shrink-0" />
                    <div className="flex-1 p-4">
                      <div className="flex items-start justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <span className="text-sm">🏋️</span>
                          <span className="inline-flex px-1.5 py-0.5 text-[10px] font-medium bg-[#F0FDFA] text-[#14B8A6] border border-[#CCFBF1] rounded">プラン</span>
                          <span className="font-semibold text-sm text-[#0F172A]">
                            {assignment.plan?.title ?? 'ワークアウト'}
                          </span>
                        </div>
                        <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-medium ${statusColor.bg} ${statusColor.text}`}>
                          <span className={`inline-block w-1.5 h-1.5 rounded-sm ${statusColor.dot}`} />
                          {ASSIGNMENT_STATUS_OPTIONS[assignment.status]}
                        </span>
                      </div>
                      <div className="flex items-center gap-3 text-xs text-[#94A3B8] mb-1">
                        {assignment.plan?.category && (
                          <span>カテゴリ: {WORKOUT_CATEGORY_OPTIONS[assignment.plan.category as keyof typeof WORKOUT_CATEGORY_OPTIONS] ?? assignment.plan.category}</span>
                        )}
                        {assignment.plan?.estimated_minutes && (
                          <span>目安: {assignment.plan.estimated_minutes}分</span>
                        )}
                      </div>
                      {/* カロリー */}
                      {assignment.calories != null && (
                        <div className="flex items-center gap-1 mb-3">
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#F59E0B]">
                            <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z" />
                          </svg>
                          <span className="text-xs text-[#F59E0B] font-semibold">{assignment.calories}kcal</span>
                        </div>
                      )}
                      {assignment.calories == null && <div className="mb-2" />}
                      {sortedExercises.length > 0 && (
                        <div className="space-y-2">
                          {sortedExercises.map((exercise) => {
                            const actualSets = exercise.actual_sets ?? []
                            return (
                              <div key={exercise.id} className="rounded-md border border-[#E2E8F0] bg-[#F8FAFC] p-3">
                                <div className="flex items-center justify-between mb-1">
                                  <span className="font-medium text-sm text-[#0F172A]">{exercise.exercise_name}</span>
                                  <span className={`text-xs font-medium flex items-center gap-0.5 ${exercise.is_completed ? 'text-[#16A34A]' : 'text-[#94A3B8]'}`}>
                                    {exercise.is_completed ? (
                                      <>
                                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" className="text-[#16A34A]" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                                          <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                                          <polyline points="22 4 12 14.01 9 11.01" />
                                        </svg>
                                        {' '}完了
                                      </>
                                    ) : '未完了'}
                                  </span>
                                </div>
                                <p className="text-xs text-[#94A3B8] mb-2">
                                  目標: {exercise.target_sets}セット × {exercise.target_reps}回
                                  {exercise.target_weight !== null && ` × ${exercise.target_weight}kg`}
                                </p>
                                {actualSets.length > 0 ? (
                                  <div className="grid grid-cols-2 gap-1 mt-2 pt-2 border-t border-[#E2E8F0]">
                                    {actualSets.map((set) => (
                                      <div key={set.set_number} className="flex items-center gap-1.5 text-xs text-[#64748B] py-0.5">
                                        <span className="text-[#94A3B8] font-medium w-8">S{set.set_number}</span>
                                        <span>{set.weight ?? '-'}kg × {set.reps ?? '-'}回</span>
                                        {set.done && <span className="text-[#16A34A] font-bold">✓</span>}
                                      </div>
                                    ))}
                                  </div>
                                ) : (
                                  <p className="text-xs text-[#94A3B8] pt-1 border-t border-[#E2E8F0]">実績なし</p>
                                )}
                                {exercise.memo && (
                                  <div className="flex items-start gap-1 mt-1.5 pt-1.5 border-t border-[#E2E8F0]">
                                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0 mt-0.5">
                                      <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                                    </svg>
                                    <p className="text-xs text-[#64748B] whitespace-pre-wrap">{exercise.memo}</p>
                                  </div>
                                )}
                              </div>
                            )
                          })}
                        </div>
                      )}
                      {assignment.trainer_note && (
                        <div className="mt-3 bg-[#F0FDFA] border border-[#CCFBF1] rounded-md px-3 py-2 flex items-start gap-2">
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#14B8A6] flex-shrink-0 mt-0.5">
                            <path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z" />
                            <polyline points="14 2 14 8 20 8" />
                            <line x1="16" y1="13" x2="8" y2="13" />
                            <line x1="16" y1="17" x2="8" y2="17" />
                            <line x1="10" y1="9" x2="8" y2="9" />
                          </svg>
                          <p className="text-sm text-[#14B8A6] whitespace-pre-wrap leading-tight">{assignment.trainer_note}</p>
                        </div>
                      )}
                      {assignment.client_feedback && (
                        <div className="mt-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-start gap-2">
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0 mt-0.5">
                            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                          </svg>
                          <p className="text-sm text-[#64748B] whitespace-pre-wrap leading-tight">{assignment.client_feedback}</p>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              )
            })}
            {/* 運動記録 */}
            {selectedDayExercises.map((record) => (
              <div key={record.id} className="bg-white border border-[#E2E8F0] rounded-md overflow-hidden">
                <div className="flex">
                  <div className="w-1 bg-[#E2E8F0] flex-shrink-0" />
                  <div className="flex-1 p-4">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="inline-flex px-1.5 py-0.5 text-[10px] font-medium bg-[#F8FAFC] text-[#64748B] border border-[#E2E8F0] rounded">自由記録</span>
                      <span className="font-semibold text-sm text-[#0F172A]">{EXERCISE_TYPE_OPTIONS[record.exercise_type]}</span>
                      <span className="text-xs text-[#94A3B8] ml-auto">{format(new Date(record.recorded_at), 'H:mm')}</span>
                    </div>
                    <div className="flex items-center gap-4 text-xs text-[#64748B]">
                      {record.duration !== null && <span>⏱ {record.duration}分</span>}
                      {record.distance !== null && <span>📏 {record.distance}km</span>}
                      {record.calories !== null && (
                        <span className="text-[#F59E0B] font-medium">🔥 {record.calories}kcal</span>
                      )}
                    </div>

                    {/* メモ */}
                    {record.memo && (
                      <div className="mt-2 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-center gap-2">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#94A3B8] flex-shrink-0">
                          <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                        </svg>
                        <p className="text-sm text-[#64748B] whitespace-pre-wrap leading-tight">{record.memo}</p>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-[#94A3B8]">記録がありません</p>
        )}
      </div>
    </div>
  )
}
