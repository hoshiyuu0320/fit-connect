import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { upsertTrainerSchedules } from '@/lib/supabase/upsertTrainerSchedules'
import { requireTrainer } from '@/lib/api/guards'

export async function GET() {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const { data, error } = await supabaseAdmin
      .from('trainer_schedules')
      .select('*')
      .eq('trainer_id', trainerId)
      .order('day_of_week', { ascending: true })

    if (error) throw error
    return NextResponse.json({ data: data ?? [] })
  } catch {
    return NextResponse.json(
      { error: 'Failed to fetch schedules' },
      { status: 500 }
    )
  }
}

export async function PUT(request: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  const body = await request.json()
  const { schedules } = body

  if (!schedules) {
    return NextResponse.json(
      { error: 'schedules is required' },
      { status: 400 }
    )
  }

  try {
    const data = await upsertTrainerSchedules(trainerId, schedules)
    return NextResponse.json({ status: 'ok', data })
  } catch {
    return NextResponse.json(
      { error: 'Failed to update schedules' },
      { status: 500 }
    )
  }
}
