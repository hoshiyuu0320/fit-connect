import { supabase } from '@/lib/supabase';

export async function createProfile(userId: string, name: string) {

  console.log('Creating profile for:', userId, name)
  const { data, error } = await supabase
    .from('profiles')
    .insert([{ id: userId, name }])

  if (error) {
    console.error('Error creating profile:', error)
    throw error
  }
  console.log('Profile created successfully:', data)
  return data

}