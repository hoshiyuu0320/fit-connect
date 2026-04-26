import { supabase } from '@/lib/supabase'

export interface ClientActivityRank {
  clientId: string
  clientName: string
  mealCount: number
  weightCount: number
  exerciseCount: number
  totalCount: number
}

/**
 * 今週の記録件数TOP Nの顧客ランキングを取得する
 * @param trainerId - トレーナーID
 * @param limit - 取得件数（デフォルト: 5）
 * @returns ClientActivityRank[] - 記録件数でソートされた顧客ランキング
 */
export async function getClientActivityRanking(
  trainerId: string,
  limit: number = 5
): Promise<ClientActivityRank[]> {
  // 1. トレーナーの全クライアントを取得
  const { data: clients, error: clientsError } = await supabase
    .from('clients')
    .select('client_id, name')
    .eq('trainer_id', trainerId)

  if (clientsError) throw clientsError
  if (!clients || clients.length === 0) return []

  const clientIds = clients.map((c) => c.client_id)
  const clientMap = new Map(clients.map((c) => [c.client_id, c.name as string]))

  // 2. 今週の開始日（月曜日 0:00）を計算
  const now = new Date()
  const dayOfWeek = now.getDay() // 0=Sun
  const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek
  const weekStart = new Date(now)
  weekStart.setDate(now.getDate() + mondayOffset)
  weekStart.setHours(0, 0, 0, 0)
  const sinceStr = weekStart.toISOString()

  // 3. 3テーブルから今週のレコードを並列取得
  const [mealRes, weightRes, exerciseRes] = await Promise.all([
    supabase
      .from('meal_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', sinceStr),
    supabase
      .from('weight_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', sinceStr),
    supabase
      .from('exercise_records')
      .select('client_id')
      .in('client_id', clientIds)
      .gte('recorded_at', sinceStr),
  ])

  if (mealRes.error) throw mealRes.error
  if (weightRes.error) throw weightRes.error
  if (exerciseRes.error) throw exerciseRes.error

  // 4. クライアントごとにカウント
  const countMap = new Map<string, { meal: number; weight: number; exercise: number }>()
  clientIds.forEach((id) => countMap.set(id, { meal: 0, weight: 0, exercise: 0 }))

  mealRes.data?.forEach((r) => {
    const c = countMap.get(r.client_id)
    if (c) c.meal++
  })
  weightRes.data?.forEach((r) => {
    const c = countMap.get(r.client_id)
    if (c) c.weight++
  })
  exerciseRes.data?.forEach((r) => {
    const c = countMap.get(r.client_id)
    if (c) c.exercise++
  })

  // 5. 合計でソートしてtop N を返す
  const ranking: ClientActivityRank[] = []
  countMap.forEach((counts, clientId) => {
    const total = counts.meal + counts.weight + counts.exercise
    if (total > 0) {
      ranking.push({
        clientId,
        clientName: clientMap.get(clientId) ?? '不明',
        mealCount: counts.meal,
        weightCount: counts.weight,
        exerciseCount: counts.exercise,
        totalCount: total,
      })
    }
  })

  ranking.sort((a, b) => b.totalCount - a.totalCount)
  return ranking.slice(0, limit)
}
