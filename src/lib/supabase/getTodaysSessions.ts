import { supabase } from '@/lib/supabase'

export type TodaysSession = {
  id: string
  client_id: string
  client_name: string
  session_date: string
  duration_minutes: number
  status: 'scheduled' | 'confirmed' | 'completed' | 'cancelled'
  session_type: string | null
  memo: string | null
}

/**
 * 本日のセッション予定を取得
 * @param trainerId - トレーナーID
 * @returns 本日のセッションリスト（時間順）
 */
export async function getTodaysSessions(trainerId: string): Promise<TodaysSession[]> {
  // 今日の開始時刻（00:00:00）
  const todayStart = new Date()
  todayStart.setHours(0, 0, 0, 0)

  // 今日の終了時刻（23:59:59）
  const todayEnd = new Date()
  todayEnd.setHours(23, 59, 59, 999)

  // セッションと顧客情報を結合して取得
  const { data, error } = await supabase
    .from('sessions')
    .select(`
      id,
      client_id,
      session_date,
      duration_minutes,
      status,
      session_type,
      memo,
      clients!inner (
        name
      )
    `)
    .eq('trainer_id', trainerId)
    .gte('session_date', todayStart.toISOString())
    .lte('session_date', todayEnd.toISOString())
    .order('session_date', { ascending: true })

  if (error) {
    console.error('本日のセッション取得エラー:', error)
    return []
  }

  if (!data) {
    return []
  }

  // データを整形
  return data.map((session) => ({
    id: session.id,
    client_id: session.client_id,
    client_name: (session.clients as { name: string }).name,
    session_date: session.session_date,
    duration_minutes: session.duration_minutes,
    status: session.status as 'scheduled' | 'confirmed' | 'completed' | 'cancelled',
    session_type: session.session_type,
    memo: session.memo,
  }))
}
