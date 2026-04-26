import { supabase } from '@/lib/supabase'

export type ClientListStats = {
  totalClients: number
  activeClients: number   // 直近7日間にweight/meal/exercise記録があるクライアント数
  todaySessions: number   // 本日のセッション数（sessionsテーブル）
  expiringTickets: number // 7日以内に期限切れになる有効チケット数
}

/**
 * クライアント一覧ページ上部の統計バー用データを取得する
 * @param trainerId - トレーナーのUUID
 */
export async function getClientListStats(trainerId: string): Promise<ClientListStats> {
  const now = new Date()

  // 日付文字列のユーティリティ
  const todayStart = new Date(now)
  todayStart.setHours(0, 0, 0, 0)
  const todayEnd = new Date(now)
  todayEnd.setHours(23, 59, 59, 999)

  const sevenDaysAgo = new Date(now)
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)

  const sevenDaysLater = new Date(now)
  sevenDaysLater.setDate(sevenDaysLater.getDate() + 7)

  try {
    // 1. 総クライアント数 + クライアントID一覧を取得
    const { data: clientsData, error: clientsError } = await supabase
      .from('clients')
      .select('client_id')
      .eq('trainer_id', trainerId)

    if (clientsError) {
      console.error('総クライアント数取得エラー:', clientsError)
      throw clientsError
    }

    const totalClients = clientsData?.length ?? 0
    const clientIds = clientsData?.map((c) => c.client_id) ?? []

    if (clientIds.length === 0) {
      return {
        totalClients: 0,
        activeClients: 0,
        todaySessions: 0,
        expiringTickets: 0,
      }
    }

    // 2. アクティブクライアント数（直近7日間にいずれかの記録があるクライアント）
    // weight_records, meal_records, exercise_records を並列で取得してユニークなクライアントIDを集計
    const [weightActive, mealActive, exerciseActive] = await Promise.all([
      supabase
        .from('weight_records')
        .select('client_id')
        .in('client_id', clientIds)
        .gte('recorded_at', sevenDaysAgo.toISOString()),
      supabase
        .from('meal_records')
        .select('client_id')
        .in('client_id', clientIds)
        .gte('recorded_at', sevenDaysAgo.toISOString()),
      supabase
        .from('exercise_records')
        .select('client_id')
        .in('client_id', clientIds)
        .gte('recorded_at', sevenDaysAgo.toISOString()),
    ])

    if (weightActive.error) {
      console.error('体重アクティブ取得エラー:', weightActive.error)
    }
    if (mealActive.error) {
      console.error('食事アクティブ取得エラー:', mealActive.error)
    }
    if (exerciseActive.error) {
      console.error('運動アクティブ取得エラー:', exerciseActive.error)
    }

    // 重複を除いてユニークなアクティブクライアントを集計
    const activeClientIdSet = new Set<string>()
    for (const row of weightActive.data ?? []) {
      activeClientIdSet.add(row.client_id)
    }
    for (const row of mealActive.data ?? []) {
      activeClientIdSet.add(row.client_id)
    }
    for (const row of exerciseActive.data ?? []) {
      activeClientIdSet.add(row.client_id)
    }
    const activeClients = activeClientIdSet.size

    // 3. 本日のセッション数（sessionsテーブル、trainer_idで絞り込み）
    const { data: sessionsData, error: sessionsError } = await supabase
      .from('sessions')
      .select('id')
      .eq('trainer_id', trainerId)
      .gte('session_date', todayStart.toISOString())
      .lte('session_date', todayEnd.toISOString())
      .neq('status', 'cancelled')

    if (sessionsError) {
      console.error('本日のセッション取得エラー:', sessionsError)
    }
    const todaySessions = sessionsData?.length ?? 0

    // 4. チケット期限切れ間近（7日以内に期限切れ、かつremaining_sessions > 0）
    const { data: ticketsData, error: ticketsError } = await supabase
      .from('tickets')
      .select('id')
      .in('client_id', clientIds)
      .gte('valid_until', now.toISOString())           // まだ有効（期限切れていない）
      .lte('valid_until', sevenDaysLater.toISOString()) // 7日以内に期限切れ
      .gt('remaining_sessions', 0)                     // 残回数あり

    if (ticketsError) {
      console.error('期限切れ間近チケット取得エラー:', ticketsError)
    }
    const expiringTickets = ticketsData?.length ?? 0

    return {
      totalClients,
      activeClients,
      todaySessions,
      expiringTickets,
    }
  } catch (error) {
    console.error('クライアント一覧統計取得エラー:', error)
    throw error
  }
}
