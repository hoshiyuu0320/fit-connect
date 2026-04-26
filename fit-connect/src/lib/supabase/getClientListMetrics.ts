import { supabase } from '@/lib/supabase'

export type ClientMetrics = {
  clientId: string
  latestWeight: number | null          // 最新体重（weight_recordsの最新レコード）
  remainingTickets: number             // 有効チケットのremaining_sessionsの合計
  monthlyWeightChange: number | null   // 月間体重変動（最新体重 - 30日前の体重）、正: 増量、負: 減量
  todayWorkoutDone: boolean            // 今日のワークアウトが完了済みか（workout_assignmentsのstatus）
}

/**
 * 複数クライアントのカードメトリクスをバッチで取得する
 * N+1クエリを避けるため、全クライアントIDをまとめてクエリする
 * @param clientIds - クライアントUUIDの配列
 */
export async function getClientListMetrics(clientIds: string[]): Promise<ClientMetrics[]> {
  if (clientIds.length === 0) return []

  const now = new Date()
  const todayStr = now.toISOString().split('T')[0] // "YYYY-MM-DD"

  const thirtyDaysAgo = new Date(now)
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)

  try {
    // 1. 全クライアントの体重記録を取得（最新 + 30日前の比較用）
    // recorded_at降順で取得し、アプリ側でクライアントごとの最新を抽出する
    const { data: weightData, error: weightError } = await supabase
      .from('weight_records')
      .select('client_id, weight, recorded_at')
      .in('client_id', clientIds)
      .order('recorded_at', { ascending: false })

    if (weightError) {
      console.error('体重記録バッチ取得エラー:', weightError)
      throw weightError
    }

    // 2. 全クライアントの有効チケットを取得（remaining_sessions合計用）
    const { data: ticketData, error: ticketError } = await supabase
      .from('tickets')
      .select('client_id, remaining_sessions, valid_until')
      .in('client_id', clientIds)
      .gt('remaining_sessions', 0)
      .gte('valid_until', now.toISOString()) // 有効期限内のみ

    if (ticketError) {
      console.error('チケットバッチ取得エラー:', ticketError)
      throw ticketError
    }

    // 3. 今日のワークアウトアサインメントを取得
    // status が 'completed' または 'partial' であれば実施済みと判定する
    const { data: workoutData, error: workoutError } = await supabase
      .from('workout_assignments')
      .select('client_id, status')
      .in('client_id', clientIds)
      .eq('assigned_date', todayStr)

    if (workoutError) {
      console.error('ワークアウトアサインメントバッチ取得エラー:', workoutError)
      // ワークアウト情報が取得できなくてもメトリクス全体は返す（フォールバック）
    }

    // クライアントIDをキーにしてデータを整理するマップを構築
    const weightByClient = new Map<string, { weight: number; recorded_at: string }[]>()
    for (const row of weightData ?? []) {
      if (!weightByClient.has(row.client_id)) {
        weightByClient.set(row.client_id, [])
      }
      weightByClient.get(row.client_id)!.push({
        weight: row.weight,
        recorded_at: row.recorded_at,
      })
    }

    const ticketSumByClient = new Map<string, number>()
    for (const row of ticketData ?? []) {
      const current = ticketSumByClient.get(row.client_id) ?? 0
      ticketSumByClient.set(row.client_id, current + row.remaining_sessions)
    }

    // 今日のワークアウト完了状況をクライアントIDでマップ化
    // 同日に複数アサインがある場合、1つでも completed/partial があれば true
    const workoutDoneByClient = new Map<string, boolean>()
    for (const row of workoutData ?? []) {
      if (row.status === 'completed' || row.status === 'partial') {
        workoutDoneByClient.set(row.client_id, true)
      } else if (!workoutDoneByClient.has(row.client_id)) {
        // pending/skipped のみの場合は false（上書きしない）
        workoutDoneByClient.set(row.client_id, false)
      }
    }

    // 各クライアントのメトリクスを計算して返す
    return clientIds.map((clientId) => {
      const records = weightByClient.get(clientId) ?? []

      // 最新体重（recorded_at降順で取得しているので先頭が最新）
      const latestWeight = records.length > 0 ? records[0].weight : null

      // 月間体重変動: 最新体重 - 30日以前の最も近い体重記録
      let monthlyWeightChange: number | null = null
      if (latestWeight !== null && records.length > 1) {
        // 30日前より古い記録の中で最も新しいもの（30日前に最も近い）を探す
        const thirtyDaysAgoIso = thirtyDaysAgo.toISOString()
        const oldRecord = records.find((r) => r.recorded_at <= thirtyDaysAgoIso)
        if (oldRecord) {
          // 小数第1位で四捨五入
          monthlyWeightChange = Math.round((latestWeight - oldRecord.weight) * 10) / 10
        }
      }

      // 残チケット数合計
      const remainingTickets = ticketSumByClient.get(clientId) ?? 0

      // 今日のワークアウト完了フラグ
      // アサインメントが存在しない場合は false
      const todayWorkoutDone = workoutDoneByClient.get(clientId) ?? false

      return {
        clientId,
        latestWeight,
        remainingTickets,
        monthlyWeightChange,
        todayWorkoutDone,
      }
    })
  } catch (error) {
    console.error('クライアントメトリクスバッチ取得エラー:', error)
    throw error
  }
}
