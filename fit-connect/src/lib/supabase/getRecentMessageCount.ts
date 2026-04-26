import { supabase } from '@/lib/supabase'

/**
 * トレーナーが受信した今週のメッセージ数を取得
 * @param trainerId - トレーナーID
 * @returns 今週のメッセージ数
 */
export async function getRecentMessageCount(trainerId: string): Promise<number> {
  // 7日前の日時を計算
  const sevenDaysAgo = new Date()
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)

  const { count, error } = await supabase
    .from('messages')
    .select('*', { count: 'exact', head: true })
    .eq('receiver_id', trainerId)
    .eq('receiver_type', 'trainer')
    .gte('created_at', sevenDaysAgo.toISOString())

  if (error) {
    console.error('メッセージ数取得エラー:', error)
    return 0
  }

  return count ?? 0
}
