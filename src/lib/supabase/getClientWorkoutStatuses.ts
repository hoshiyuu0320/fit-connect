import { supabase } from '@/lib/supabase'
import { startOfWeek, endOfWeek, format } from 'date-fns'

type WorkoutStatus = 'completed' | 'partial' | 'pending' | null

export async function getClientWorkoutStatuses(
  trainerId: string
): Promise<Record<string, WorkoutStatus>> {
  const now = new Date()
  const weekStart = format(startOfWeek(now, { weekStartsOn: 1 }), 'yyyy-MM-dd')
  const weekEnd = format(endOfWeek(now, { weekStartsOn: 1 }), 'yyyy-MM-dd')

  const { data, error } = await supabase
    .from('workout_assignments')
    .select('client_id, status')
    .eq('trainer_id', trainerId)
    .gte('assigned_date', weekStart)
    .lte('assigned_date', weekEnd)

  if (error) {
    console.error('クライアントワークアウトステータス取得エラー:', error)
    throw error
  }

  const statuses: Record<string, WorkoutStatus> = {}

  if (!data || data.length === 0) return statuses

  // clientId ごとにグループ化
  const grouped: Record<string, string[]> = {}
  for (const row of data) {
    if (!grouped[row.client_id]) {
      grouped[row.client_id] = []
    }
    grouped[row.client_id].push(row.status)
  }

  // ステータス判定
  for (const [clientId, assignmentStatuses] of Object.entries(grouped)) {
    const allCompleted = assignmentStatuses.every((s) => s === 'completed')
    const allPending = assignmentStatuses.every((s) => s === 'pending')

    if (allCompleted) {
      statuses[clientId] = 'completed'
    } else if (allPending) {
      statuses[clientId] = 'pending'
    } else {
      statuses[clientId] = 'partial'
    }
  }

  return statuses
}
