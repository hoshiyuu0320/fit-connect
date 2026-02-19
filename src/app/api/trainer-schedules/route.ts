import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { upsertTrainerSchedules } from '@/lib/supabase/upsertTrainerSchedules'

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  const trainerId = searchParams.get('trainerId')

  if (!trainerId) {
    return NextResponse.json(
      { error: 'trainerId is required' },
      { status: 400 }
    )
  }

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
  const body = await request.json()
  const { trainerId, schedules } = body

  if (!trainerId || !schedules) {
    return NextResponse.json(
      { error: 'trainerId and schedules are required' },
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
