import { supabase } from '@/lib/supabase'
import type { ClientNote } from '@/types/client'

export const getClientNotes = async (clientId: string): Promise<ClientNote[]> => {
  const { data, error } = await supabase
    .from('client_notes')
    .select('*')
    .eq('client_id', clientId)
    .order('created_at', { ascending: false })

  if (error) {
    console.error('カルテ取得エラー：', error)
    throw error
  }

  return data as ClientNote[]
}
