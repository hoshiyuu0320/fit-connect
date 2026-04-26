import { supabase } from '../supabase'

export async function getTrainer(userId: string) {
  const { data, error } = await supabase
    .from('trainers')
    .select('name')
    .eq('id', userId)
    .single()

  if (error) throw error
  return data
}
