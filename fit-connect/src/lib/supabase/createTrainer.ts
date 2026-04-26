import { supabase } from '@/lib/supabase';

export async function createTrainer(userId: string, name: string, email: string) {

  console.log('Creating trainer for:', userId, name)
  const { data, error } = await supabase
    .from('trainers')
    .insert([{ id: userId, name, email }])

  if (error) {
    console.error('Error creating trainer:', error)
    throw error
  }
  console.log('Trainer created successfully:', data)
  return data

}
