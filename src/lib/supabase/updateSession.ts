import { supabase } from '@/lib/supabase';

interface UpdateSessionParams {
  id: string;
  session_date?: Date;
  duration_minutes?: number;
  status?: 'scheduled' | 'confirmed' | 'completed' | 'cancelled';
  session_type?: string;
  memo?: string;
  ticket_id?: string;
}

export const updateSession = async (params: UpdateSessionParams) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const updates: any = {
    updated_at: new Date().toISOString(),
  };

  if (params.session_date) updates.session_date = params.session_date.toISOString();
  if (params.duration_minutes) updates.duration_minutes = params.duration_minutes;
  if (params.status) updates.status = params.status;
  if (params.session_type !== undefined) updates.session_type = params.session_type;
  if (params.memo !== undefined) updates.memo = params.memo;
  if (params.ticket_id !== undefined) updates.ticket_id = params.ticket_id;

  const { data, error } = await supabase
    .from('sessions')
    .update(updates)
    .eq('id', params.id)
    .select()
    .single();

  if (error) {
    console.error('Error updating session:', error);
    throw error;
  }

  return data;
};
