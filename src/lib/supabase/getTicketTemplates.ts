import { supabase } from '@/lib/supabase'
import type { TicketTemplate } from '@/types/client'

export const getTicketTemplates = async (trainerId: string): Promise<TicketTemplate[]> => {
  const { data, error } = await supabase
    .from('ticket_templates')
    .select('*')
    .eq('trainer_id', trainerId)
    .order('created_at', { ascending: false })

  if (error) {
    throw error
  }

  return data as TicketTemplate[]
}
