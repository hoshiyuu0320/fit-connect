import { supabase } from '@/lib/supabase'
import type { SleepRecord } from '@/types/client'

export const getSleepRecords = async (clientId: string): Promise<SleepRecord[]> => {
  const { data, error } = await supabase
    .from('sleep_records')
    .select('*')
    .eq('client_id', clientId)
    .order('recorded_date', { ascending: false })
    .limit(180)

  if (error) {
    console.error('睡眠記録取得エラー:', error)
    throw error
  }

  return (data ?? []) as SleepRecord[]
}
