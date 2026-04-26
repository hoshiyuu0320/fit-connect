import { supabase } from '@/lib/supabase'
import type { GetMealRecordsParams, GetMealRecordsResult } from '@/types/client'

export const getMealRecords = async ({
  clientId,
  mealType,
  limit = 20,
  offset = 0,
}: GetMealRecordsParams): Promise<GetMealRecordsResult> => {
  let query = supabase
    .from('meal_records')
    .select('*', { count: 'exact' })
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: false })
    .range(offset, offset + limit - 1)

  if (mealType) {
    query = query.eq('meal_type', mealType)
  }

  const { data, error, count } = await query

  if (error) {
    console.error('食事記録取得エラー：', error)
    throw error
  }

  return {
    data: data || [],
    count: count || 0,
  }
}
