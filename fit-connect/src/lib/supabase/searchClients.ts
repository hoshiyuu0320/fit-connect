import { supabase } from '@/lib/supabase'
import type { SearchClientsParams, Client } from '@/types/client'

export const searchClients = async ({
  trainerId,
  searchQuery,
  gender,
  ageRange,
  purpose,
}: SearchClientsParams): Promise<Client[]> => {
  let query = supabase
    .from('clients')
    .select('*')
    .eq('trainer_id', trainerId)
    .order('name', { ascending: true })

  if (searchQuery) {
    query = query.ilike('name', `%${searchQuery}%`)
  }

  if (gender) {
    query = query.eq('gender', gender)
  }

  if (ageRange) {
    query = query.gte('age', ageRange.min).lte('age', ageRange.max)
  }

  if (purpose) {
    query = query.eq('purpose', purpose)
  }

  const { data, error } = await query

  if (error) {
    console.error('クライアント検索エラー：', error)
    throw error
  }

  return data as Client[]
}
