import { supabase } from '@/lib/supabase'
import type { WeightRecord } from '@/types/client'

export const getWeightRecords = async (clientId: string): Promise<WeightRecord[]> => {
  const { data, error } = await supabase
    .from('weight_records')
    .select('id, client_id, weight, notes, recorded_at, messages(image_urls)')
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: true })

  if (error) {
    console.error('体重記録取得エラー：', error)
    throw error
  }

  // messages JOIN結果をフラットに変換
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (data ?? []).map((row: any) => ({
    id: row.id,
    client_id: row.client_id,
    weight: row.weight,
    notes: row.notes,
    recorded_at: row.recorded_at,
    image_urls: row.messages?.image_urls ?? null,
  }))
}
