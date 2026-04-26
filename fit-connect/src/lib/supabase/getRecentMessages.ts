import { supabase } from '@/lib/supabase'

export type RecentMessage = {
  id: string
  message: string
  timestamp: string
  sender_id: string
  sender_name: string
  client_id: string
}

/**
 * トレーナーが受信した最近のメッセージを取得（顧客名含む）
 * @param trainerId - トレーナーID
 * @param limit - 取得件数（デフォルト: 5）
 * @returns 最近のメッセージリスト
 */
export async function getRecentMessages(
  trainerId: string,
  limit: number = 5
): Promise<RecentMessage[]> {
  const { data, error } = await supabase
    .from('messages')
    .select(`
      id,
      content,
      created_at,
      sender_id,
      sender_type
    `)
    .eq('receiver_id', trainerId)
    .eq('receiver_type', 'trainer')
    .order('created_at', { ascending: false })
    .limit(limit)

  if (error) {
    console.error('最近のメッセージ取得エラー:', error)
    return []
  }

  if (!data || data.length === 0) {
    return []
  }

  // 顧客名を取得するため、sender_idのリストを作成
  const clientIds = data
    .filter((msg) => msg.sender_type === 'client')
    .map((msg) => msg.sender_id)

  // 顧客情報を一括取得
  const { data: clients, error: clientError } = await supabase
    .from('clients')
    .select('client_id, name')
    .in('client_id', clientIds)

  if (clientError) {
    console.error('顧客情報取得エラー:', clientError)
  }

  // 顧客IDから名前へのマップを作成
  const clientNameMap = new Map(
    clients?.map((c) => [c.client_id, c.name]) ?? []
  )

  // メッセージに顧客名を追加
  return data.map((msg) => ({
    id: msg.id,
    message: msg.content,
    timestamp: msg.created_at,
    sender_id: msg.sender_id,
    sender_name: clientNameMap.get(msg.sender_id) ?? '不明',
    client_id: msg.sender_id,
  }))
}
