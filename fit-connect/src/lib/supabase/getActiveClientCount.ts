import { supabase } from '@/lib/supabase'

/**
 * アクティブ顧客数を取得（30日以内に記録がある顧客）
 * @param trainerId - トレーナーID
 * @returns アクティブ顧客数
 */
export async function getActiveClientCount(trainerId: string): Promise<number> {
  // 30日前の日時を計算
  const thirtyDaysAgo = new Date()
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)
  const cutoffDate = thirtyDaysAgo.toISOString()

  // トレーナーの全顧客を取得
  const { data: clients, error: clientError } = await supabase
    .from('clients')
    .select('client_id')
    .eq('trainer_id', trainerId)

  if (clientError || !clients) {
    console.error('顧客取得エラー:', clientError)
    return 0
  }

  if (clients.length === 0) {
    return 0
  }

  const clientIds = clients.map((c) => c.client_id)

  // 各テーブルから30日以内の記録がある顧客IDを取得
  const [weightRecords, mealRecords, exerciseRecords] = await Promise.all([
    supabase
      .from('weight_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', cutoffDate),
    supabase
      .from('meal_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', cutoffDate),
    supabase
      .from('exercise_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', cutoffDate),
  ])

  // いずれかの記録があるユニークな顧客IDを集計
  const activeClientIds = new Set<string>()

  weightRecords.data?.forEach((r) => activeClientIds.add(r.client_id))
  mealRecords.data?.forEach((r) => activeClientIds.add(r.client_id))
  exerciseRecords.data?.forEach((r) => activeClientIds.add(r.client_id))

  return activeClientIds.size
}
