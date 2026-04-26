export type TrainerSchedule = {
  id: string
  trainer_id: string
  day_of_week: number    // 0=日, 1=月, ..., 6=土
  start_time: string     // "HH:mm:ss"
  end_time: string       // "HH:mm:ss"
  is_available: boolean
  created_at: string
  updated_at: string
}

export type UpsertScheduleItem = {
  day_of_week: number
  start_time: string
  end_time: string
  is_available: boolean
}

export type ScheduleFormItem = {
  dayOfWeek: number
  label: string
  isAvailable: boolean
  startTime: string
  endTime: string
}
