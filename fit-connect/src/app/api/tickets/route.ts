import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function POST(req: NextRequest) {
  const body = await req.json()
  const { clientId, ticketName, ticketType, totalSessions, validFrom, validUntil } = body

  if (!clientId || !ticketName || !ticketType || !totalSessions) {
    return NextResponse.json({ error: 'Missing required parameters' }, { status: 400 })
  }

  const { data, error } = await supabaseAdmin
    .from('tickets')
    .insert([
      {
        client_id: clientId,
        ticket_name: ticketName,
        ticket_type: ticketType,
        total_sessions: totalSessions,
        remaining_sessions: totalSessions, // 初期値は totalSessions と同じ
        valid_from: validFrom || null,
        valid_until: validUntil || null,
      },
    ])
    .select()
    .single()

  if (error) {
    console.error('チケット作成エラー:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ status: 'ok', data })
}
