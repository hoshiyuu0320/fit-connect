import { supabase } from '@/lib/supabase';

export interface Session {
  id: string;
  trainer_id: string;
  client_id: string;
  session_date: string;
  duration_minutes: number;
  status: 'scheduled' | 'confirmed' | 'completed' | 'cancelled';
  session_type: string | null;
  memo: string | null;
  created_at: string;
  updated_at: string;
  ticket_id?: string | null;
  clients?: {
    name: string;
  };
}

export const getSessions = async (startDate: Date, endDate: Date) => {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not authenticated')
  console.log('Current User ID:', user.id)
  const { data, error } = await supabase
    .from('sessions')
    .select(`
      *,
      clients (
        name
      )
    `)
    .gte('session_date', startDate.toISOString())
    .lte('session_date', endDate.toISOString())
    .order('session_date', { ascending: true });

  if (error) {
    console.error('Error fetching sessions:', error);
    throw error;
  }

  return data as Session[];
};
