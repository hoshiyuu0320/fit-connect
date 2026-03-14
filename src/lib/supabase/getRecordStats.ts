import { supabase } from '@/lib/supabase'

export interface RecordStats {
  mealCount: number
  mealCountLastWeek: number
  weightCount: number
  weightCountLastWeek: number
  exerciseCount: number
  exerciseCountLastWeek: number
  activeRecordingClients: number // 今週記録を送った顧客数
  totalActiveClients: number // アクティブ顧客数（記録率計算用）
}

/**
 * トレーナーの全顧客の今週・先週の記録件数を種別ごとに集計する
 * @param trainerId - トレーナーID
 * @returns RecordStats - 各記録種別のカウントと記録中顧客数
 */
export async function getRecordStats(trainerId: string): Promise<RecordStats> {
  // 今週と先週の日付範囲を計算（月曜日始まり）
  const now = new Date()
  const dayOfWeek = now.getDay() // 0=Sun
  const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek

  const thisWeekStart = new Date(now)
  thisWeekStart.setDate(now.getDate() + mondayOffset)
  thisWeekStart.setHours(0, 0, 0, 0)

  const lastWeekStart = new Date(thisWeekStart)
  lastWeekStart.setDate(thisWeekStart.getDate() - 7)

  const thisWeekStartStr = thisWeekStart.toISOString()
  const lastWeekStartStr = lastWeekStart.toISOString()
  const nowStr = now.toISOString()

  // トレーナーの全クライアントIDを取得
  const { data: clients, error: clientsError } = await supabase
    .from('clients')
    .select('client_id')
    .eq('trainer_id', trainerId)

  if (clientsError) {
    console.error('クライアント取得エラー:', clientsError)
  }

  if (!clients || clients.length === 0) {
    return {
      mealCount: 0,
      mealCountLastWeek: 0,
      weightCount: 0,
      weightCountLastWeek: 0,
      exerciseCount: 0,
      exerciseCountLastWeek: 0,
      activeRecordingClients: 0,
      totalActiveClients: 0,
    }
  }

  const clientIds = clients.map((c) => c.client_id)

  // 並列で全カウントを取得
  const [
    mealThisWeek,
    mealLastWeek,
    weightThisWeek,
    weightLastWeek,
    exerciseThisWeek,
    exerciseLastWeek,
  ] = await Promise.all([
    // 食事: 今週
    supabase
      .from('meal_records')
      .select('id', { count: 'exact', head: true })
      .in('client_id', clientIds)
      .gte('recorded_at', thisWeekStartStr)
      .lte('recorded_at', nowStr),
    // 食事: 先週
    supabase
      .from('meal_records')
      .select('id', { count: 'exact', head: true })
      .in('client_id', clientIds)
      .gte('recorded_at', lastWeekStartStr)
      .lt('recorded_at', thisWeekStartStr),
    // 体重: 今週
    supabase
      .from('weight_records')
      .select('id', { count: 'exact', head: true })
      .in('client_id', clientIds)
      .gte('recorded_at', thisWeekStartStr)
      .lte('recorded_at', nowStr),
    // 体重: 先週
    supabase
      .from('weight_records')
      .select('id', { count: 'exact', head: true })
      .in('client_id', clientIds)
      .gte('recorded_at', lastWeekStartStr)
      .lt('recorded_at', thisWeekStartStr),
    // 運動: 今週
    supabase
      .from('exercise_records')
      .select('id', { count: 'exact', head: true })
      .in('client_id', clientIds)
      .gte('recorded_at', thisWeekStartStr)
      .lte('recorded_at', nowStr),
    // 運動: 先週
    supabase
      .from('exercise_records')
      .select('id', { count: 'exact', head: true })
      .in('client_id', clientIds)
      .gte('recorded_at', lastWeekStartStr)
      .lt('recorded_at', thisWeekStartStr),
  ])

  // 今週記録を送った顧客数を計算（ユニーク）
  const [mealClients, weightClients, exerciseClients] = await Promise.all([
    supabase
      .from('meal_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', thisWeekStartStr),
    supabase
      .from('weight_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', thisWeekStartStr),
    supabase
      .from('exercise_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', thisWeekStartStr),
  ])

  const recordingClientIds = new Set<string>()
  mealClients.data?.forEach((r) => recordingClientIds.add(r.client_id))
  weightClients.data?.forEach((r) => recordingClientIds.add(r.client_id))
  exerciseClients.data?.forEach((r) => recordingClientIds.add(r.client_id))

  return {
    mealCount: mealThisWeek.count ?? 0,
    mealCountLastWeek: mealLastWeek.count ?? 0,
    weightCount: weightThisWeek.count ?? 0,
    weightCountLastWeek: weightLastWeek.count ?? 0,
    exerciseCount: exerciseThisWeek.count ?? 0,
    exerciseCountLastWeek: exerciseLastWeek.count ?? 0,
    activeRecordingClients: recordingClientIds.size,
    totalActiveClients: clientIds.length,
  }
}
