import { supabase } from '@/lib/supabase'
import type { WorkoutPlan } from '@/types/workout'

export async function getWorkoutPlans(trainerId: string): Promise<WorkoutPlan[]> {
  const { data, error } = await supabase
    .from('workout_plans')
    .select('*, workout_exercises(count)')
    .eq('trainer_id', trainerId)
    .order('created_at', { ascending: false })

  if (error) {
    console.error('ワークアウトプラン取得エラー:', error)
    throw error
  }

  return (data || []).map((plan) => ({
    ...plan,
    exercise_count: plan.workout_exercises?.[0]?.count || 0,
  }))
}
