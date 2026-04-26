"use client"

import { useEffect, useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { WORKOUT_CATEGORY_OPTIONS, type WorkoutExercise, type WorkoutPlan } from '@/types/workout'

interface ExerciseListModalProps {
  open: boolean
  onClose: () => void
  plan: WorkoutPlan | null
}

export function ExerciseListModal({ open, onClose, plan }: ExerciseListModalProps) {
  const [exercises, setExercises] = useState<WorkoutExercise[]>([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (!open || !plan) return

    if (plan.exercises && plan.exercises.length > 0) {
      setExercises(plan.exercises)
      return
    }

    const fetchExercises = async () => {
      setLoading(true)
      try {
        const res = await fetch(
          `/api/workout-plans/${plan.id}/exercises`
        )
        if (res.ok) {
          const json = await res.json()
          setExercises(json.data || [])
        }
      } catch (error) {
        console.error('種目取得エラー:', error)
      } finally {
        setLoading(false)
      }
    }
    fetchExercises()
  }, [open, plan])

  const categoryLabel =
    plan?.category && plan.category in WORKOUT_CATEGORY_OPTIONS
      ? WORKOUT_CATEGORY_OPTIONS[plan.category as keyof typeof WORKOUT_CATEGORY_OPTIONS]
      : plan?.category ?? ''

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{plan?.title ?? ''} の種目一覧</DialogTitle>
        </DialogHeader>

        {plan && (
          <div className="mb-3 flex gap-3 text-sm text-gray-500">
            <span className="bg-gray-100 px-2 py-0.5 rounded">{categoryLabel}</span>
            {plan.estimated_minutes && (
              <span>約 {plan.estimated_minutes} 分</span>
            )}
          </div>
        )}

        {loading ? (
          <div className="flex justify-center py-8">
            <div className="animate-spin rounded-full h-8 w-8 border-4 border-blue-600 border-t-transparent" />
          </div>
        ) : exercises.length === 0 ? (
          <p className="text-sm text-gray-500 py-4">種目が登録されていません</p>
        ) : (
          <div className="space-y-3">
            {exercises.map((ex, index) => (
              <div
                key={ex.id}
                className="flex items-start gap-3 p-3 bg-gray-50 rounded-lg"
              >
                <span className="text-xs text-gray-400 mt-0.5 w-5 text-right">
                  {index + 1}.
                </span>
                <div className="flex-1">
                  <p className="font-medium text-gray-800 text-sm">{ex.name}</p>
                  <div className="flex gap-3 mt-1 text-xs text-gray-500">
                    <span>{ex.sets} セット</span>
                    {ex.reps && <span>{ex.reps} 回</span>}
                    {ex.weight && <span>{ex.weight} kg</span>}
                  </div>
                  {ex.memo && (
                    <p className="text-xs text-gray-400 mt-1">{ex.memo}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
