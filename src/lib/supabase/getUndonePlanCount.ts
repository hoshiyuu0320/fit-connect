import { supabase } from '@/lib/supabase'
import { startOfWeek, endOfWeek, format } from 'date-fns'

export async function getUndonePlanCount(trainerId: string): Promise<number> {
  const now = new Date()
  const weekStart = format(startOfWeek(now, { weekStartsOn: 1 }), 'yyyy-MM-dd')
  const weekEnd = format(endOfWeek(now, { weekStartsOn: 1 }), 'yyyy-MM-dd')

  const { count, error } = await supabase
    .from('workout_assignments')
    .select('*', { count: 'exact', head: true })
    .eq('trainer_id', trainerId)
    .eq('status', 'pending')
    .gte('assigned_date', weekStart)
    .lte('assigned_date', weekEnd)

  if (error) {
    console.error('未実施プランカウントエラー:', error)
    throw error
  }

  return count || 0
}
