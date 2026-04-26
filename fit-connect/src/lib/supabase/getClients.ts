import { supabase } from '@/lib/supabase'
import type { Client } from '@/types/client'

export const getClients = async (trainerId: string): Promise<Client[]> => {
  const { data, error } = await supabase
    .from('clients')
    .select('*')
    .eq('trainer_id', trainerId)
    .order('name', { ascending: true })

  if (error) {
    console.error('クライアント取得エラー：', error)
    throw error
  }

  return data as Client[]
}