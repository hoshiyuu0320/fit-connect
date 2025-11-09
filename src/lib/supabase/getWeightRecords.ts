import { supabase } from '@/lib/supabase'
import type { WeightRecord } from '@/types/client'

export const getWeightRecords = async (clientId: string): Promise<WeightRecord[]> => {
  const { data, error } = await supabase
    .from('weight_records')
    .select('*')
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: true })

  if (error) {
    console.error('体重記録取得エラー：', error)
    throw error
  }

  return data as WeightRecord[]
}
