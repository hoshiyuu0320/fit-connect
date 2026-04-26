import { supabase } from '@/lib/supabase';

interface CreateSessionParams {
  trainer_id: string;
  client_id: string;
  session_date: Date;
  duration_minutes: number;
  status?: 'scheduled' | 'confirmed' | 'completed' | 'cancelled';
  session_type?: string;
  memo?: string;
  ticket_id?: string;
}

export const createSession = async (params: CreateSessionParams) => {
  const { data, error } = await supabase
    .from('sessions')
    .insert({
      trainer_id: params.trainer_id,
      client_id: params.client_id,
      session_date: params.session_date.toISOString(),
      duration_minutes: params.duration_minutes,
      status: params.status || 'scheduled',
      session_type: params.session_type,
      memo: params.memo,
      ticket_id: params.ticket_id,
    })
    .select()
    .single();

  if (error) {
    console.error('Error creating session:', error);
    throw error;
  }

  return data;
};
