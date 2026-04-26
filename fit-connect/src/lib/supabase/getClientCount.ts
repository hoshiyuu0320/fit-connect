import { supabase } from '@/lib/supabase'

/**
 * トレーナーの担当顧客数を取得
 * @param trainerId - トレーナーID
 * @returns 顧客数
 */
export async function getClientCount(trainerId: string): Promise<number> {
  const { count, error } = await supabase
    .from('clients')
    .select('*', { count: 'exact', head: true })
    .eq('trainer_id', trainerId)

  if (error) {
    console.error('顧客数取得エラー:', error)
    return 0
  }

  return count ?? 0
}
