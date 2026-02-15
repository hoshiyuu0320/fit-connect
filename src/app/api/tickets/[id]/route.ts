import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function PUT(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const body = await req.json()
  const { ticketName, ticketType, totalSessions, remainingSessions, validFrom, validUntil } = body

  if (!id) {
    return NextResponse.json({ error: 'Missing ticket ID' }, { status: 400 })
  }

  const updateData: Record<string, unknown> = {}

  if (ticketName !== undefined) updateData.ticket_name = ticketName
  if (ticketType !== undefined) updateData.ticket_type = ticketType
  if (totalSessions !== undefined) updateData.total_sessions = totalSessions
  if (remainingSessions !== undefined) updateData.remaining_sessions = remainingSessions
  if (validFrom !== undefined) updateData.valid_from = validFrom
  if (validUntil !== undefined) updateData.valid_until = validUntil

  const { data, error } = await supabaseAdmin
    .from('tickets')
    .update(updateData)
    .eq('id', id)
    .select()
    .single()

  if (error) {
    console.error('チケット更新エラー:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ status: 'ok', data })
}

export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  if (!id) {
    return NextResponse.json({ error: 'Missing ticket ID' }, { status: 400 })
  }

  const { error } = await supabaseAdmin
    .from('tickets')
    .delete()
    .eq('id', id)

  if (error) {
    console.error('チケット削除エラー:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ status: 'ok' })
}
