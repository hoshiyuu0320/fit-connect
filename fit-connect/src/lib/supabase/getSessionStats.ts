import { supabase } from '@/lib/supabase'

export interface SessionStats {
  completed: number       // status='completed' の件数
  scheduled: number       // status='scheduled' または 'confirmed' の件数
  cancelled: number       // status='cancelled' の件数
  total: number           // completed + scheduled + cancelled
  completionRate: number  // completed / (total - cancelled) * 100, 小数1桁
}

/**
 * 今月のセッション消化率を計算する
 * @param trainerId - トレーナーID
 * @returns SessionStats - 今月のセッション統計
 */
export async function getSessionStats(trainerId: string): Promise<SessionStats> {
  const now = new Date()
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59).toISOString()

  const { data, error } = await supabase
    .from('sessions')
    .select('status')
    .eq('trainer_id', trainerId)
    .gte('session_date', monthStart)
    .lte('session_date', monthEnd)

  if (error) throw error

  const completed = data?.filter(s => s.status === 'completed').length ?? 0
  const scheduled = data?.filter(s => s.status === 'scheduled' || s.status === 'confirmed').length ?? 0
  const cancelled = data?.filter(s => s.status === 'cancelled').length ?? 0
  const total = completed + scheduled + cancelled
  const base = total - cancelled
  const completionRate = base > 0 ? Math.round(completed / base * 1000) / 10 : 0

  return { completed, scheduled, cancelled, total, completionRate }
}
