import { supabase } from '@/lib/supabase'
import type { WorkoutAssignment } from '@/types/workout'

export async function getClientAssignments(clientId: string): Promise<WorkoutAssignment[]> {
  const thirtyDaysAgo = new Date()
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)
  const fromDate = thirtyDaysAgo.toISOString().split('T')[0]

  const { data, error } = await supabase
    .from('workout_assignments')
    .select(`
      *,
      plan:workout_plans (
        id,
        title,
        category,
        estimated_minutes
      ),
      exercises:workout_assignment_exercises (
        *
      )
    `)
    .eq('client_id', clientId)
    .gte('assigned_date', fromDate)
    .order('assigned_date', { ascending: false })

  if (error) {
    console.error('クライアントアサインメント取得エラー:', error)
    throw error
  }

  return data || []
}
