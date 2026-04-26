import { supabase } from '@/lib/supabase'

export type InactiveClient = {
  client_id: string
  client_name: string
  days_inactive: number
  last_activity_date: string | null
}

/**
 * 非アクティブな顧客を取得（7日以上記録がない）
 * @param trainerId - トレーナーID
 * @returns 非アクティブな顧客リスト
 */
export async function getInactiveClients(trainerId: string): Promise<InactiveClient[]> {
  // 7日前の日時を計算
  const sevenDaysAgo = new Date()
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)
  const cutoffDate = sevenDaysAgo.toISOString()

  // トレーナーの全顧客を取得
  const { data: clients, error: clientError } = await supabase
    .from('clients')
    .select('client_id, name')
    .eq('trainer_id', trainerId)

  if (clientError || !clients) {
    console.error('顧客取得エラー:', clientError)
    return []
  }

  if (clients.length === 0) {
    return []
  }

  const clientIds = clients.map((c) => c.client_id)

  // 各テーブルから7日以内の記録がある顧客IDを取得
  let weightRecords: { data: { client_id: string }[] | null } = { data: [] };
  let mealRecords: { data: { client_id: string }[] | null } = { data: [] };
  let exerciseRecords: { data: { client_id: string }[] | null } = { data: [] };

  try {
    const results = await Promise.all([
      supabase
        .from('weight_records')
        .select('client_id, recorded_at')
        .in('client_id', clientIds)
        .gte('recorded_at', cutoffDate),
      supabase
        .from('meal_records')
        .select('client_id, recorded_at')
        .in('client_id', clientIds)
        .gte('recorded_at', cutoffDate),
      supabase
        .from('exercise_records')
        .select('client_id, recorded_at')
        .in('client_id', clientIds)
        .gte('recorded_at', cutoffDate),
    ]);
    weightRecords = results[0];
    mealRecords = results[1];
    exerciseRecords = results[2];
  } catch (error) {
    console.error('記録取得エラー:', error);
  }

  // 7日以内に記録があるクライアントIDのセット
  const activeClientIds = new Set<string>()

  weightRecords.data?.forEach((r) => activeClientIds.add(r.client_id))
  mealRecords.data?.forEach((r) => activeClientIds.add(r.client_id))
  exerciseRecords.data?.forEach((r) => activeClientIds.add(r.client_id))

  // 非アクティブな顧客（7日以内に記録がない）
  const inactiveClients = clients.filter(
    (client) => !activeClientIds.has(client.client_id)
  )

  // 各顧客の最終活動日を取得
  const inactiveClientsWithActivity = await Promise.all(
    inactiveClients.map(async (client) => {
      // 全テーブルから最新の記録を取得
      let latestWeight: { data: { recorded_at: string } | null } = { data: null };
      let latestMeal: { data: { recorded_at: string } | null } = { data: null };
      let latestExercise: { data: { recorded_at: string } | null } = { data: null };

      try {
        const results = await Promise.all([
          supabase
            .from('weight_records')
            .select('recorded_at')
            .eq('client_id', client.client_id)
            .order('recorded_at', { ascending: false })
            .limit(1)
            .single(),
          supabase
            .from('meal_records')
            .select('recorded_at')
            .eq('client_id', client.client_id)
            .order('recorded_at', { ascending: false })
            .limit(1)
            .single(),
          supabase
            .from('exercise_records')
            .select('recorded_at')
            .eq('client_id', client.client_id)
            .order('recorded_at', { ascending: false })
            .limit(1)
            .single(),
        ]);
        latestWeight = results[0];
        latestMeal = results[1];
        latestExercise = results[2];
      } catch (error) {
        console.error('最新記録取得エラー:', error);
      }

      // 最も新しい記録日を取得
      const dates = [
        latestWeight.data?.recorded_at,
        latestMeal.data?.recorded_at,
        latestExercise.data?.recorded_at,
      ].filter((d) => d !== null && d !== undefined) as string[]

      const lastActivityDate = dates.length > 0 ? dates.sort().reverse()[0] : null

      // 非アクティブ日数を計算
      const daysInactive = lastActivityDate
        ? Math.floor(
            (new Date().getTime() - new Date(lastActivityDate).getTime()) /
              (1000 * 60 * 60 * 24)
          )
        : 999 // 記録が一度もない場合は999日

      return {
        client_id: client.client_id,
        client_name: client.name,
        days_inactive: daysInactive,
        last_activity_date: lastActivityDate,
      }
    })
  )

  // 非アクティブ日数でソート（長い順）
  return inactiveClientsWithActivity.sort((a, b) => b.days_inactive - a.days_inactive)
}
