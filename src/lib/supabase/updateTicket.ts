import { supabase } from '@/lib/supabase';

interface UpdateTicketParams {
  id: string;
  remaining_sessions: number;
}

export const updateTicket = async (params: UpdateTicketParams) => {
  const { data, error } = await supabase
    .from('tickets')
    .update({
      remaining_sessions: params.remaining_sessions,
    })
    .eq('id', params.id)
    .select()
    .single();

  if (error) {
    console.error('Error updating ticket:', error);
    throw error;
  }

  return data;
};
