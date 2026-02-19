import { supabase } from '../supabase'
import type { TrainerSchedule } from '@/types/schedule'

export async function getTrainerSchedules(
  trainerId: string
): Promise<TrainerSchedule[]> {
  const { data, error } = await supabase
    .from('trainer_schedules')
    .select('*')
    .eq('trainer_id', trainerId)
    .order('day_of_week', { ascending: true })

  if (error) throw error
  return data ?? []
}
