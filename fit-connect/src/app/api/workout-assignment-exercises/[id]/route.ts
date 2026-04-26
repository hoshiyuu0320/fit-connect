import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  if (!id) {
    return NextResponse.json({ error: 'Missing exercise ID' }, { status: 400 })
  }

  try {
    const body = await request.json()
    const { actualSets, isCompleted, memo } = body

    const updateData: Record<string, unknown> = {}
    if (actualSets !== undefined) updateData.actual_sets = actualSets
    if (isCompleted !== undefined) updateData.is_completed = isCompleted
    if (memo !== undefined) updateData.memo = memo

    const { data, error } = await supabaseAdmin
      .from('workout_assignment_exercises')
      .update(updateData)
      .eq('id', id)
      .select()
      .single()

    if (error) throw error

    return NextResponse.json({ status: 'ok', data })
  } catch (error) {
    console.error('アサインメント種目更新エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}
