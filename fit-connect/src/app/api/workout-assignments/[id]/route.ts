import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  if (!id) {
    return NextResponse.json({ error: 'Missing assignment ID' }, { status: 400 })
  }

  try {
    const body = await request.json()
    const { assignedDate, status, trainerNote, clientFeedback, startedAt, finishedAt } = body

    const updateData: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    }
    if (assignedDate !== undefined) updateData.assigned_date = assignedDate
    if (status !== undefined) updateData.status = status
    if (trainerNote !== undefined) updateData.trainer_note = trainerNote
    if (clientFeedback !== undefined) updateData.client_feedback = clientFeedback
    if (startedAt !== undefined) updateData.started_at = startedAt
    if (finishedAt !== undefined) updateData.finished_at = finishedAt

    const { data, error } = await supabaseAdmin
      .from('workout_assignments')
      .update(updateData)
      .eq('id', id)
      .select()
      .single()

    if (error) throw error

    return NextResponse.json({ status: 'ok', data })
  } catch (error) {
    console.error('アサインメント更新エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  if (!id) {
    return NextResponse.json({ error: 'Missing assignment ID' }, { status: 400 })
  }

  try {
    const { error } = await supabaseAdmin
      .from('workout_assignments')
      .delete()
      .eq('id', id)

    if (error) throw error

    return NextResponse.json({ status: 'ok' })
  } catch (error) {
    console.error('アサインメント削除エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}
