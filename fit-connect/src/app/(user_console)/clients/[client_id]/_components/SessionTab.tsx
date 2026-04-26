"use client"

import { useEffect, useState } from 'react'
import { format, addDays, subDays } from 'date-fns'
import { ja } from 'date-fns/locale'
import type { WorkoutAssignment, WorkoutAssignmentExercise, ActualSet } from '@/types/workout'
import { ASSIGNMENT_STATUS_COLORS, ASSIGNMENT_STATUS_OPTIONS } from '@/types/workout'
import { SetInputRow } from './SetInputRow'
import { SupersetBadge } from './SupersetBadge'
import { SessionTimerBar } from './SessionTimerBar'
import { SessionSummaryModal } from './SessionSummaryModal'

type SessionTabProps = {
  clientId: string
  trainerId: string
}

export function SessionTab({ clientId, trainerId }: SessionTabProps) {
  const [allAssignments, setAllAssignments] = useState<WorkoutAssignment[]>([])
  const [selectedDate, setSelectedDate] = useState(format(new Date(), 'yyyy-MM-dd'))
  const [loading, setLoading] = useState(true)
  const [savingExerciseId, setSavingExerciseId] = useState<string | null>(null)

  // サマリーモーダル関連
  const [summaryOpen, setSummaryOpen] = useState(false)
  const [summaryAssignment, setSummaryAssignment] = useState<WorkoutAssignment | null>(null)
  const [trainerNote, setTrainerNote] = useState('')
  const [clientFeedback, setClientFeedback] = useState('')
  const [savingSummary, setSavingSummary] = useState(false)
  const [saveToast, setSaveToast] = useState<string | null>(null)

  // 日付リスト（当日 -3 〜 +3）
  const dateRange = Array.from({ length: 7 }, (_, i) =>
    format(addDays(subDays(new Date(), 3), i), 'yyyy-MM-dd')
  )

  // 過去30日分も含めてアサインメントを取得
  useEffect(() => {
    const fetchAssignments = async () => {
      setLoading(true)
      const start = format(subDays(new Date(), 3), 'yyyy-MM-dd')
      const end = format(addDays(new Date(), 3), 'yyyy-MM-dd')

      try {
        const res = await fetch(
          `/api/workout-assignments?trainerId=${trainerId}&clientId=${clientId}&weekStart=${start}&weekEnd=${end}&includeHistory=true`
        )
        const result = await res.json()

        if (result.status === 'ok') {
          setAllAssignments(result.data)
        }
      } catch (error) {
        console.error('アサインメント取得エラー:', error)
      } finally {
        setLoading(false)
      }
    }
    fetchAssignments()
  }, [clientId, trainerId])

  // 表示用（選択日の前後3日のみ、セッションタイプのみ）
  const assignments = allAssignments.filter((a) => dateRange.includes(a.assigned_date) && a.plan?.plan_type === 'session')
  const todayAssignments = allAssignments.filter((a) => a.assigned_date === selectedDate && a.plan?.plan_type === 'session')

  // 前回のアサインメントを取得（同plan_idで直近のcompleted）
  const getPreviousAssignment = (assignment: WorkoutAssignment): WorkoutAssignment | null => {
    const previousCompleted = allAssignments
      .filter(
        (a) =>
          a.plan_id === assignment.plan_id &&
          a.status === 'completed' &&
          a.assigned_date < assignment.assigned_date
      )
      .sort((a, b) => b.assigned_date.localeCompare(a.assigned_date))
    return previousCompleted[0] ?? null
  }

  // 前回データを取得（exercise_name 一致 + setIndex）
  const getPreviousSet = (
    prevAssignment: WorkoutAssignment | null,
    exerciseName: string,
    setIndex: number
  ): ActualSet | null => {
    if (!prevAssignment?.exercises) return null
    const prevExercise = prevAssignment.exercises.find(
      (e) => e.exercise_name === exerciseName
    )
    if (!prevExercise?.actual_sets) return null
    return prevExercise.actual_sets[setIndex] ?? null
  }

  // セット更新ハンドラ
  const handleSetUpdate = async (
    exerciseId: string,
    sets: ActualSet[],
    isCompleted: boolean,
    assignmentId: string
  ) => {
    setSavingExerciseId(exerciseId)
    try {
      await fetch(`/api/workout-assignment-exercises/${exerciseId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ actualSets: sets, isCompleted }),
      })

      // ローカルステートを更新
      setAllAssignments((prev) =>
        prev.map((a) => {
          if (a.id !== assignmentId) return a
          return {
            ...a,
            exercises: a.exercises?.map((ex) => {
              if (ex.id !== exerciseId) return ex
              return { ...ex, actual_sets: sets, is_completed: isCompleted }
            }),
          }
        })
      )

      // アサインメントのステータスを自動更新
      const assignment = allAssignments.find((a) => a.id === assignmentId)
      if (assignment?.exercises) {
        const updatedExercises = assignment.exercises.map((ex) =>
          ex.id === exerciseId ? { ...ex, actual_sets: sets, is_completed: isCompleted } : ex
        )
        const allCompleted = updatedExercises.every((ex) => ex.is_completed)
        const anyCompleted = updatedExercises.some((ex) => ex.is_completed)
        const newStatus = allCompleted ? 'completed' : anyCompleted ? 'partial' : 'pending'

        await fetch(`/api/workout-assignments/${assignmentId}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ status: newStatus }),
        })

        setAllAssignments((prev) =>
          prev.map((a) =>
            a.id === assignmentId ? { ...a, status: newStatus as WorkoutAssignment['status'] } : a
          )
        )
      }

      // 保存完了トースト表示
      setSaveToast('保存しました')
      setTimeout(() => setSaveToast(null), 2000)
    } catch (error) {
      console.error('セット更新エラー:', error)
    } finally {
      setSavingExerciseId(null)
    }
  }

  // セット変更時のローカル更新
  const handleSetChange = (
    assignmentId: string,
    exerciseId: string,
    setIndex: number,
    updatedSet: ActualSet
  ) => {
    setAllAssignments((prev) =>
      prev.map((a) => {
        if (a.id !== assignmentId) return a
        return {
          ...a,
          exercises: a.exercises?.map((ex) => {
            if (ex.id !== exerciseId) return ex
            const currentSets = ex.actual_sets ?? buildInitialSets(ex)
            const newSets = currentSets.map((s, i) => (i === setIndex ? updatedSet : s))
            const isCompleted = newSets.every((s) => s.done)
            return { ...ex, actual_sets: newSets, is_completed: isCompleted }
          }),
        }
      })
    )
  }

  // 保存ボタン
  const handleSave = async (exercise: WorkoutAssignmentExercise, assignmentId: string) => {
    const sets = exercise.actual_sets ?? buildInitialSets(exercise)
    const isCompleted = sets.every((s) => s.done)
    await handleSetUpdate(exercise.id, sets, isCompleted, assignmentId)
  }

  // タイマー開始
  const handleTimerStart = async (assignmentId: string) => {
    const now = new Date().toISOString()
    try {
      await fetch(`/api/workout-assignments/${assignmentId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ startedAt: now }),
      })
      setAllAssignments((prev) =>
        prev.map((a) => (a.id === assignmentId ? { ...a, started_at: now } : a))
      )
    } catch (error) {
      console.error('タイマー開始エラー:', error)
    }
  }

  // タイマー終了
  const handleTimerFinish = async (assignmentId: string) => {
    const now = new Date().toISOString()
    try {
      await fetch(`/api/workout-assignments/${assignmentId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ finishedAt: now }),
      })
      setAllAssignments((prev) =>
        prev.map((a) => (a.id === assignmentId ? { ...a, finished_at: now } : a))
      )

      // サマリーモーダルを表示
      const assignment = allAssignments.find((a) => a.id === assignmentId)
      if (assignment) {
        setSummaryAssignment({ ...assignment, finished_at: now })
        setTrainerNote(assignment.trainer_note ?? '')
        setClientFeedback(assignment.client_feedback ?? '')
        setSummaryOpen(true)
      }
    } catch (error) {
      console.error('タイマー終了エラー:', error)
    }
  }

  // サマリー保存
  const handleSaveSummary = async () => {
    if (!summaryAssignment) return
    setSavingSummary(true)
    try {
      await fetch(`/api/workout-assignments/${summaryAssignment.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          trainerNote,
          clientFeedback,
          status: 'completed',
        }),
      })
      setAllAssignments((prev) =>
        prev.map((a) =>
          a.id === summaryAssignment.id
            ? {
                ...a,
                trainer_note: trainerNote,
                client_feedback: clientFeedback,
                status: 'completed' as const,
              }
            : a
        )
      )
      setSummaryOpen(false)
    } catch (error) {
      console.error('サマリー保存エラー:', error)
    } finally {
      setSavingSummary(false)
    }
  }

  // 種目メモ保存（onBlur）
  const handleMemoSave = async (exerciseId: string, memo: string) => {
    try {
      await fetch(`/api/workout-assignment-exercises/${exerciseId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ memo }),
      })
      setAllAssignments((prev) =>
        prev.map((a) => ({
          ...a,
          exercises: a.exercises?.map((ex) =>
            ex.id === exerciseId ? { ...ex, memo } : ex
          ),
        }))
      )
    } catch (error) {
      console.error('メモ保存エラー:', error)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-4 border-[#14B8A6] border-t-transparent"></div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* 日付ピッカー */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <h2 className="text-sm font-medium text-[#64748B] mb-3">日付を選択</h2>
        <div className="flex gap-2 overflow-x-auto pb-1">
          {dateRange.map((date) => {
            const dateObj = new Date(date + 'T00:00:00')
            const isToday = date === format(new Date(), 'yyyy-MM-dd')
            const isSelected = date === selectedDate
            const dayAssignments = assignments.filter((a) => a.assigned_date === date)

            return (
              <button
                key={date}
                onClick={() => setSelectedDate(date)}
                className={`flex flex-col items-center min-w-[60px] px-3 py-2 rounded-md border transition-colors ${
                  isSelected
                    ? 'bg-[#14B8A6] text-white border-[#14B8A6]'
                    : isToday
                    ? 'border-[#14B8A6] text-[#14B8A6]'
                    : 'border-[#E2E8F0] text-[#64748B] hover:border-[#CBD5E1]'
                }`}
              >
                <span className="text-xs">
                  {format(dateObj, 'E', { locale: ja })}
                </span>
                <span className="text-lg font-semibold">
                  {format(dateObj, 'd')}
                </span>
                {dayAssignments.length > 0 && (
                  <span
                    className={`w-1.5 h-1.5 rounded-full mt-0.5 ${
                      isSelected ? 'bg-white' : 'bg-[#14B8A6]'
                    }`}
                  />
                )}
              </button>
            )
          })}
        </div>
        <p className="text-xs text-[#94A3B8] mt-2">
          {format(new Date(selectedDate + 'T00:00:00'), 'yyyy年M月d日(E)', { locale: ja })}
        </p>
      </div>

      {/* アサインメント一覧 */}
      {todayAssignments.length === 0 ? (
        <div className="flex items-center justify-center h-48 bg-white border border-[#E2E8F0] rounded-md">
          <div className="text-center">
            <p className="text-[#94A3B8] mb-1">この日のワークアウトはありません</p>
            <p className="text-xs text-[#94A3B8]">カレンダーからプランを割り当ててください</p>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          {todayAssignments.map((assignment) => {
            const statusColor = ASSIGNMENT_STATUS_COLORS[assignment.status]
            const prevAssignment = getPreviousAssignment(assignment)

            return (
              <div key={assignment.id} className="bg-white border border-[#E2E8F0] rounded-md overflow-hidden">
                {/* アサインメントヘッダー */}
                <div className="flex items-center justify-between px-4 py-3 border-b border-[#E2E8F0]">
                  <div>
                    <h3 className="font-semibold text-[#0F172A]">
                      {assignment.plan?.title ?? 'ワークアウト'}
                    </h3>
                    {assignment.plan?.estimated_minutes && (
                      <p className="text-xs text-[#94A3B8] mt-0.5">
                        目安: {assignment.plan.estimated_minutes}分
                      </p>
                    )}
                  </div>
                  <span
                    className={`inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium ${statusColor.bg} ${statusColor.text}`}
                  >
                    <span className={`inline-block w-2 h-2 rounded-full ${statusColor.dot}`} /> {ASSIGNMENT_STATUS_OPTIONS[assignment.status]}
                  </span>
                </div>

                {/* セッションタイマーバー（sessionタイプのみ） */}
                {assignment.plan?.plan_type === 'session' && (
                  <div className="px-4 pt-3">
                    <SessionTimerBar
                      startedAt={assignment.started_at}
                      finishedAt={assignment.finished_at}
                      onStart={() => handleTimerStart(assignment.id)}
                      onFinish={() => handleTimerFinish(assignment.id)}
                    />
                  </div>
                )}

                {/* 種目一覧 */}
                <div className="px-4 py-3 space-y-4">
                  {assignment.exercises && assignment.exercises.length > 0 ? (
                    assignment.plan?.plan_type === 'self_guided' ? (
                      /* 宿題タイプ: 種目情報・ステータス・実績表示（読み取り専用） */
                      <div className="space-y-3">
                        {assignment.exercises
                          .slice()
                          .sort((a, b) => a.order_index - b.order_index)
                          .map((exercise) => (
                            <div
                              key={exercise.id}
                              className="rounded-md border border-[#E2E8F0] px-3 py-2"
                            >
                              <div className="flex items-center justify-between">
                                <div>
                                  <h4 className="font-medium text-[#0F172A] text-sm">
                                    {exercise.exercise_name}
                                  </h4>
                                  <p className="text-xs text-[#94A3B8]">
                                    目標: {exercise.target_sets}セット × {exercise.target_reps}回
                                    {exercise.target_weight && ` ${exercise.target_weight}kg`}
                                  </p>
                                </div>
                                {exercise.is_completed ? (
                                  <span className="text-xs font-medium text-[#16A34A] bg-[#F0FDF4] px-2 py-1 rounded-md">完了</span>
                                ) : (
                                  <span className="text-xs font-medium text-[#94A3B8] bg-[#F8FAFC] px-2 py-1 rounded-md">未実施</span>
                                )}
                              </div>
                              {/* セットごとの実績 */}
                              {exercise.actual_sets && exercise.actual_sets.length > 0 && (
                                <div className="mt-2 space-y-1">
                                  {exercise.actual_sets.map((set) => (
                                    <div
                                      key={set.set_number}
                                      className="flex items-center gap-3 text-xs text-[#64748B]"
                                    >
                                      <span className="text-[#94A3B8] w-4">{set.set_number}</span>
                                      <span>{set.weight ?? '-'}kg × {set.reps ?? '-'}回</span>
                                      {set.done && <span className="text-[#16A34A]">&#10003;</span>}
                                    </div>
                                  ))}
                                </div>
                              )}
                            </div>
                          ))}
                      </div>
                    ) : (
                      /* セッションタイプ: フル編集UI */
                      assignment.exercises
                        .slice()
                        .sort((a, b) => a.order_index - b.order_index)
                        .map((exercise, exerciseIndex) => {
                          const exercises = assignment.exercises!
                          const prevExercise = exercises[exerciseIndex - 1]
                          const isSuperset =
                            exercise.linked_exercise_id !== null ||
                            prevExercise?.linked_exercise_id === exercise.id

                          const initialSets = buildInitialSets(exercise)
                          const currentSets = exercise.actual_sets ?? initialSets

                          return (
                            <div key={exercise.id}>
                              {/* スーパーセットバッジ */}
                              {isSuperset && exerciseIndex > 0 && prevExercise?.linked_exercise_id && (
                                <SupersetBadge />
                              )}

                              <div
                                className={`rounded-md border p-3 ${
                                  isSuperset ? 'border-purple-200' : 'border-[#E2E8F0]'
                                }`}
                              >
                                {/* 種目ヘッダー */}
                                <div className="flex items-center justify-between mb-2">
                                  <div className="flex items-center gap-2">
                                    {isSuperset && (
                                      <span className="text-xs px-1.5 py-0.5 bg-purple-100 text-purple-700 rounded-md">
                                        SS
                                      </span>
                                    )}
                                    <h4 className="font-medium text-[#0F172A] text-sm">
                                      {exercise.exercise_name}
                                    </h4>
                                  </div>
                                  <div className="flex items-center gap-2">
                                    {exercise.is_completed && (
                                      <span className="text-xs text-[#16A34A] font-medium">完了</span>
                                    )}
                                    <button
                                      onClick={() => handleSave(exercise, assignment.id)}
                                      disabled={savingExerciseId === exercise.id}
                                      className="text-sm px-5 py-2 bg-[#14B8A6] text-white rounded-md hover:bg-[#0D9488] disabled:opacity-50 font-medium"
                                    >
                                      {savingExerciseId === exercise.id ? '保存中...' : '保存'}
                                    </button>
                                  </div>
                                </div>

                                {/* 目標表示 */}
                                <p className="text-xs text-[#94A3B8] mb-2">
                                  目標: {exercise.target_sets}セット ×{' '}
                                  {exercise.target_reps}回
                                  {exercise.target_weight && ` ${exercise.target_weight}kg`}
                                </p>

                                {/* セット入力行 */}
                                <div>
                                  {currentSets.map((set, setIndex) => (
                                    <SetInputRow
                                      key={set.set_number}
                                      setNumber={set.set_number}
                                      targetWeight={exercise.target_weight}
                                      targetReps={exercise.target_reps}
                                      actualSet={set}
                                      previousSet={getPreviousSet(
                                        prevAssignment,
                                        exercise.exercise_name,
                                        setIndex
                                      )}
                                      onChange={(updatedSet) =>
                                        handleSetChange(assignment.id, exercise.id, setIndex, updatedSet)
                                      }
                                    />
                                  ))}
                                </div>

                                {/* メモ入力 */}
                                <textarea
                                  defaultValue={exercise.memo ?? ''}
                                  placeholder="メモを入力..."
                                  rows={2}
                                  onBlur={(e) => handleMemoSave(exercise.id, e.target.value)}
                                  className="w-full mt-2 text-xs rounded-md border border-[#E2E8F0] px-2 py-1.5 focus:outline-none focus:ring-1 focus:ring-[#14B8A6] resize-none bg-[#F8FAFC]"
                                />
                              </div>
                            </div>
                          )
                        })
                    )
                  ) : (
                    <p className="text-sm text-[#94A3B8] py-2">種目が登録されていません</p>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* セッションサマリーモーダル */}
      {summaryAssignment && (
        <SessionSummaryModal
          open={summaryOpen}
          onOpenChange={setSummaryOpen}
          exercises={summaryAssignment.exercises ?? []}
          startedAt={summaryAssignment.started_at}
          finishedAt={summaryAssignment.finished_at}
          trainerNote={trainerNote}
          clientFeedback={clientFeedback}
          onTrainerNoteChange={setTrainerNote}
          onClientFeedbackChange={setClientFeedback}
          onSave={handleSaveSummary}
          saving={savingSummary}
        />
      )}

      {/* 保存完了トースト */}
      {saveToast && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 animate-fade-in">
          <div className="flex items-center gap-2 bg-[#0F172A] text-white text-sm px-4 py-2.5 rounded-md">
            <span className="text-[#14B8A6]">&#10003;</span>
            {saveToast}
          </div>
        </div>
      )}
    </div>
  )
}

// 初期セット配列を生成
function buildInitialSets(exercise: WorkoutAssignmentExercise): ActualSet[] {
  return Array.from({ length: exercise.target_sets }, (_, i) => ({
    set_number: i + 1,
    weight: exercise.target_weight,
    reps: exercise.target_reps,
    done: false,
  }))
}
