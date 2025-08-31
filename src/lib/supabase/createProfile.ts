import { supabase } from '@/lib/supabase';

export async function createProfile(userId: string, name: string) {

const { data, error } = await supabase
    .from('profiles')
    .insert([{ id: userId, name }])

  if (error) throw error
  return data

}