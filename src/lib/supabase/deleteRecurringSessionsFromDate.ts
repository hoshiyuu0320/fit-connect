import { supabase } from '@/lib/supabase';

export const deleteRecurringSessionsFromDate = async (
  recurrenceGroupId: string,
  fromDate: string
) => {
  const { error } = await supabase
    .from('sessions')
    .delete()
    .eq('recurrence_group_id', recurrenceGroupId)
    .gte('session_date', fromDate);

  if (error) {
    console.error('Error deleting recurring sessions:', error);
    throw error;
  }

  return true;
};
