import { supabase } from '@/lib/supabase'

export type ExpiringTicket = {
  id: string
  client_id: string
  client_name: string
  ticket_name: string
  remaining_sessions: number
  valid_until: string
  days_until_expiry: number
}

/**
 * 期限切れ間近のチケットを取得（残回数3回以下 & 期限14日以内）
 * @param trainerId - トレーナーID
 * @returns 期限切れ間近のチケットリスト
 */
export async function getExpiringTickets(trainerId: string): Promise<ExpiringTicket[]> {
  // 14日後の日時を計算
  const fourteenDaysLater = new Date()
  fourteenDaysLater.setDate(fourteenDaysLater.getDate() + 14)
  const cutoffDate = fourteenDaysLater.toISOString()

  const now = new Date().toISOString()

  // トレーナーの顧客を取得
  const { data: clients, error: clientError } = await supabase
    .from('clients')
    .select('client_id, name')
    .eq('trainer_id', trainerId)

  if (clientError || !clients) {
    console.error('顧客取得エラー:', clientError)
    return []
  }

  const clientIds = clients.map((c) => c.client_id)

  // 条件に合うチケットを取得
  const { data: tickets, error: ticketError } = await supabase
    .from('tickets')
    .select('id, client_id, ticket_name, remaining_sessions, valid_until')
    .in('client_id', clientIds)
    .lte('remaining_sessions', 3)
    .gte('valid_until', now) // まだ有効
    .lte('valid_until', cutoffDate) // 14日以内に期限切れ

  if (ticketError || !tickets) {
    console.error('チケット取得エラー:', ticketError)
    return []
  }

  // 顧客名のマップを作成
  const clientMap = new Map(clients.map((c) => [c.client_id, c.name]))

  // 期限までの日数を計算
  const now_date = new Date()
  return tickets.map((ticket) => {
    const expiryDate = new Date(ticket.valid_until)
    const daysUntilExpiry = Math.ceil(
      (expiryDate.getTime() - now_date.getTime()) / (1000 * 60 * 60 * 24)
    )

    return {
      id: ticket.id,
      client_id: ticket.client_id,
      client_name: clientMap.get(ticket.client_id) ?? '不明',
      ticket_name: ticket.ticket_name,
      remaining_sessions: ticket.remaining_sessions,
      valid_until: ticket.valid_until,
      days_until_expiry: daysUntilExpiry,
    }
  })
}
