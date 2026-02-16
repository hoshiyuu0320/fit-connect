import { supabase } from '../supabase'
import { Trainer } from '@/types/trainer'

export async function getTrainerDetail(userId: string): Promise<Trainer> {
  const { data, error } = await supabase
    .from('trainers')
    .select('*')
    .eq('id', userId)
    .single()

  if (error) throw error
  return data as Trainer
}
