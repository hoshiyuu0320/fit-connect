import { supabase } from '@/lib/supabase'
import type { Ticket } from '@/types/client'

export const getTickets = async (clientId: string): Promise<Ticket[]> => {
  const { data, error } = await supabase
    .from('tickets')
    .select('*')
    .eq('client_id', clientId)
    .order('valid_until', { ascending: false })

  if (error) {
    console.error('チケット取得エラー：', error)
    throw error
  }

  return data as Ticket[]
}
