import { supabase } from '@/lib/supabase'
import type { WorkoutAssignment } from '@/types/workout'

export async function getWeeklyAssignments(
  trainerId: string,
  clientId: string,
  weekStart: string,
  weekEnd: string
): Promise<WorkoutAssignment[]> {
  const { data, error } = await supabase
    .from('workout_assignments')
    .select(`
      *,
      plan:workout_plans (
        id,
        title,
        category
      )
    `)
    .eq('trainer_id', trainerId)
    .eq('client_id', clientId)
    .gte('assigned_date', weekStart)
    .lte('assigned_date', weekEnd)
    .order('assigned_date', { ascending: true })

  if (error) {
    console.error('週間アサインメント取得エラー:', error)
    throw error
  }

  return data || []
}
