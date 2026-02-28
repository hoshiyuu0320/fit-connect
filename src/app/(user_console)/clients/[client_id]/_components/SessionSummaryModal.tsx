"use client"

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import type { WorkoutAssignmentExercise, ActualSet } from '@/types/workout'

type SessionSummaryModalProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  exercises: WorkoutAssignmentExercise[]
  startedAt: string | null
  finishedAt: string | null
  trainerNote: string
  clientFeedback: string
  onTrainerNoteChange: (note: string) => void
  onClientFeedbackChange: (feedback: string) => void
  onSave: () => void
  saving: boolean
}

function calcDuration(startedAt: string | null, finishedAt: string | null): string {
  if (!startedAt || !finishedAt) return '-'
  const diffMs = new Date(finishedAt).getTime() - new Date(startedAt).getTime()
  if (diffMs <= 0) return '-'
  const totalSeconds = Math.floor(diffMs / 1000)
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${minutes}分${seconds}秒`
}

function buildInitialSets(exercise: WorkoutAssignmentExercise): ActualSet[] {
  return Array.from({ length: exercise.target_sets }, (_, i) => ({
    set_number: i + 1,
    weight: exercise.target_weight,
    reps: exercise.target_reps,
    done: false,
  }))
}

export function SessionSummaryModal({
  open,
  onOpenChange,
  exercises,
  startedAt,
  finishedAt,
  trainerNote,
  clientFeedback,
  onTrainerNoteChange,
  onClientFeedbackChange,
  onSave,
  saving,
}: SessionSummaryModalProps) {
  const duration = calcDuration(startedAt, finishedAt)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>セッションサマリー</DialogTitle>
        </DialogHeader>

        <div className="max-h-[70vh] overflow-y-auto px-1 space-y-5">
          {/* 所要時間 */}
          <div className="flex items-center gap-2 text-sm text-gray-700">
            <span className="font-medium">所要時間:</span>
            <span className="text-gray-900 font-semibold">{duration}</span>
          </div>

          {/* 種目実績 */}
          <div>
            <h3 className="text-sm font-semibold text-gray-800 mb-2">種目実績</h3>
            <div className="border border-gray-200 rounded-lg divide-y divide-gray-100">
              {exercises.length === 0 ? (
                <p className="text-sm text-gray-500 p-3">種目がありません</p>
              ) : (
                exercises
                  .slice()
                  .sort((a, b) => a.order_index - b.order_index)
                  .map((exercise) => {
                    const sets = exercise.actual_sets ?? buildInitialSets(exercise)

                    return (
                      <div key={exercise.id} className="p-3">
                        {/* 種目名 + 完了アイコン */}
                        <div className="flex items-center gap-2 mb-1">
                          <span className="flex-shrink-0">
                            {exercise.is_completed ? (
                              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" className="text-green-500" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                                <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                                <polyline points="22 4 12 14.01 9 11.01" />
                              </svg>
                            ) : (
                              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" className="text-gray-300" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                                <rect x="3" y="3" width="18" height="18" rx="4" />
                              </svg>
                            )}
                          </span>
                          <span className="text-sm font-medium text-gray-900">
                            {exercise.exercise_name}
                          </span>
                        </div>

                        {/* セット実績 */}
                        <div className="ml-6 space-y-0.5">
                          {sets.map((set) => (
                            <p
                              key={set.set_number}
                              className={`text-xs ${set.done ? 'text-gray-700' : 'text-gray-400'}`}
                            >
                              Set{set.set_number}:{' '}
                              {set.weight != null ? `${set.weight}kg` : '-'}{' '}
                              &times;{' '}
                              {set.reps != null ? `${set.reps}回` : '-'}
                            </p>
                          ))}
                        </div>
                      </div>
                    )
                  })
              )}
            </div>
          </div>

          {/* トレーナーノート */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              トレーナーノート
            </label>
            <textarea
              value={trainerNote}
              onChange={(e) => onTrainerNoteChange(e.target.value)}
              placeholder="セッションの所見やアドバイスを記録..."
              rows={3}
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
              disabled={saving}
            />
          </div>

          {/* クライアントフィードバック */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              クライアントフィードバック
            </label>
            <textarea
              value={clientFeedback}
              onChange={(e) => onClientFeedbackChange(e.target.value)}
              placeholder="クライアントからのフィードバック..."
              rows={3}
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
              disabled={saving}
            />
          </div>

          {/* 保存ボタン */}
          <div className="flex justify-center pt-1">
            <button
              type="button"
              onClick={onSave}
              disabled={saving}
              className="px-6 py-2.5 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {saving ? '保存中...' : '完了として保存'}
            </button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
