import { supabase } from '@/lib/supabase'
import type { TicketSubscription } from '@/types/client'

export const getTicketSubscriptions = async (trainerId: string): Promise<TicketSubscription[]> => {
  const { data, error } = await supabase
    .from('ticket_subscriptions')
    .select('*, ticket_templates!inner(*, trainer_id), clients!inner(name)')
    .eq('ticket_templates.trainer_id', trainerId)
    .order('created_at', { ascending: false })

  if (error) {
    throw error
  }

  // Map the response to include template and client_name
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const subscriptions: TicketSubscription[] = data.map((sub: any) => ({
    id: sub.id,
    template_id: sub.template_id,
    client_id: sub.client_id,
    status: sub.status,
    start_date: sub.start_date,
    next_issue_date: sub.next_issue_date,
    created_at: sub.created_at,
    template: {
      id: sub.ticket_templates.id,
      trainer_id: sub.ticket_templates.trainer_id,
      template_name: sub.ticket_templates.template_name,
      ticket_type: sub.ticket_templates.ticket_type,
      total_sessions: sub.ticket_templates.total_sessions,
      valid_months: sub.ticket_templates.valid_months,
      is_recurring: sub.ticket_templates.is_recurring,
      created_at: sub.ticket_templates.created_at,
      updated_at: sub.ticket_templates.updated_at,
    },
    client_name: sub.clients.name,
  }))

  return subscriptions
}
