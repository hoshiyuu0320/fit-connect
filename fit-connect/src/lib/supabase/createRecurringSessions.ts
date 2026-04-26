import { supabase } from '@/lib/supabase';

interface CreateRecurringSessionsParams {
  trainer_id: string;
  client_id: string;
  base_date: Date;
  duration_minutes: number;
  pattern: 'weekly' | 'biweekly' | 'monthly';
  end_type: 'date' | 'count';
  end_date?: Date;
  count?: number;
  status?: 'scheduled' | 'confirmed' | 'completed' | 'cancelled';
  session_type?: string;
  memo?: string;
  ticket_id?: string;
}

export const createRecurringSessions = async (params: CreateRecurringSessionsParams) => {
  const recurrence_group_id = crypto.randomUUID();

  const dates: Date[] = [];
  let current = new Date(params.base_date);

  const advanceDate = (d: Date): Date => {
    const next = new Date(d);
    if (params.pattern === 'monthly') {
      next.setMonth(next.getMonth() + 1);
    } else {
      const interval = params.pattern === 'weekly' ? 7 : 14;
      next.setDate(next.getDate() + interval);
    }
    return next;
  };

  if (params.end_type === 'count') {
    const count = Math.min(params.count || 1, 52);
    for (let i = 0; i < count; i++) {
      dates.push(new Date(current));
      current = advanceDate(current);
    }
  } else if (params.end_type === 'date' && params.end_date) {
    while (current <= params.end_date && dates.length < 52) {
      dates.push(new Date(current));
      current = advanceDate(current);
    }
  }

  const rows = dates.map(date => ({
    trainer_id: params.trainer_id,
    client_id: params.client_id,
    session_date: date.toISOString(),
    duration_minutes: params.duration_minutes,
    status: params.status || 'scheduled',
    session_type: params.session_type,
    memo: params.memo,
    ticket_id: params.ticket_id,
    recurrence_group_id,
  }));

  const { data, error } = await supabase
    .from('sessions')
    .insert(rows)
    .select();

  if (error) {
    console.error('Error creating recurring sessions:', error);
    throw error;
  }

  return data;
};
