import { supabaseAdmin } from '../supabaseAdmin'
import type { UpsertScheduleItem } from '@/types/schedule'

export async function upsertTrainerSchedules(
  trainerId: string,
  schedules: UpsertScheduleItem[]
) {
  const rows = schedules.map((s) => ({
    trainer_id: trainerId,
    day_of_week: s.day_of_week,
    start_time: s.start_time,
    end_time: s.end_time,
    is_available: s.is_available,
  }))

  const { data, error } = await supabaseAdmin
    .from('trainer_schedules')
    .upsert(rows, { onConflict: 'trainer_id,day_of_week' })
    .select()

  if (error) throw error
  return data
}
