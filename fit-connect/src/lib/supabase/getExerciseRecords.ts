import { supabase } from '@/lib/supabase'
import type { GetExerciseRecordsParams, GetExerciseRecordsResult } from '@/types/client'

export const getExerciseRecords = async ({
  clientId,
  limit = 20,
  offset = 0,
}: GetExerciseRecordsParams): Promise<GetExerciseRecordsResult> => {
  const { data, error, count } = await supabase
    .from('exercise_records')
    .select('*', { count: 'exact' })
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: false })
    .range(offset, offset + limit - 1)

  if (error) {
    console.error('運動記録取得エラー：', error)
    throw error
  }

  return {
    data: data || [],
    count: count || 0,
  }
}
