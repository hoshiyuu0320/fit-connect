import { supabase } from '@/lib/supabase';

export const deleteSession = async (id: string) => {
  const { error } = await supabase
    .from('sessions')
    .delete()
    .eq('id', id);

  if (error) {
    console.error('Error deleting session:', error);
    throw error;
  }

  return true;
};
