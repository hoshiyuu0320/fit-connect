import { supabase } from '@/lib/supabase'
import type { WorkoutExercise } from '@/types/workout'

export async function getWorkoutExercises(planId: string): Promise<WorkoutExercise[]> {
  const { data, error } = await supabase
    .from('workout_exercises')
    .select('*')
    .eq('plan_id', planId)
    .order('order_index', { ascending: true })

  if (error) {
    console.error('ワークアウト種目取得エラー:', error)
    throw error
  }

  return data || []
}
