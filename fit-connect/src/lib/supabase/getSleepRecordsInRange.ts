import { supabase } from '@/lib/supabase'
import type { SleepRecord } from '@/types/client'

/**
 * recorded_date が from〜to（両端含む、'yyyy-MM-dd'）の睡眠記録を新しい順で返す。
 * 閲覧可否は RLS（sleep_records_trainer_select）に委任。recorded_date は date 列なので
 * 素の日付で .lte しても終了日は漏れない。
 */
export const getSleepRecordsInRange = async (
  clientId: string,
  from: string,
  to: string
): Promise<SleepRecord[]> => {
  const { data, error } = await supabase
    .from('sleep_records')
    .select('*')
    .eq('client_id', clientId)
    .gte('recorded_date', from)
    .lte('recorded_date', to)
    .order('recorded_date', { ascending: false })

  if (error) {
    console.error('睡眠記録（範囲）取得エラー:', error)
    throw error
  }

  return (data ?? []) as SleepRecord[]
}
