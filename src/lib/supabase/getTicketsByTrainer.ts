import { supabase } from '@/lib/supabase'
import type { TicketWithClient } from '@/types/client'

export const getTicketsByTrainer = async (trainerId: string): Promise<TicketWithClient[]> => {
  const { data, error } = await supabase
    .from('tickets')
    .select('*, clients!inner(name, trainer_id)')
    .eq('clients.trainer_id', trainerId)
    .order('created_at', { ascending: false })

  if (error) {
    throw error
  }

  // Map the response to include client_name
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const tickets: TicketWithClient[] = data.map((ticket: any) => ({
    id: ticket.id,
    client_id: ticket.client_id,
    ticket_name: ticket.ticket_name,
    ticket_type: ticket.ticket_type,
    total_sessions: ticket.total_sessions,
    remaining_sessions: ticket.remaining_sessions,
    valid_from: ticket.valid_from,
    valid_until: ticket.valid_until,
    created_at: ticket.created_at,
    client_name: ticket.clients.name,
  }))

  return tickets
}
