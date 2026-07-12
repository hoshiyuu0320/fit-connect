import { NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { requireTrainer } from '@/lib/api/guards'

// GET: トレーナーの全顧客チケット一覧
export async function GET() {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const { data, error } = await supabaseAdmin
      .from('tickets')
      .select('*, clients!inner(name, trainer_id)')
      .eq('clients.trainer_id', trainerId)
      .order('created_at', { ascending: false })

    if (error) {
      console.error('チケット一覧取得エラー:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    // 顧客名を付加してレスポンス
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const tickets = data.map((ticket: any) => ({
      id: ticket.id,
      client_id: ticket.client_id,
      ticket_name: ticket.ticket_name,
      ticket_type: ticket.ticket_type,
      total_sessions: ticket.total_sessions,
      remaining_sessions: ticket.remaining_sessions,
      price_yen: ticket.price_yen ?? null,
      valid_from: ticket.valid_from,
      valid_until: ticket.valid_until,
      created_at: ticket.created_at,
      client_name: ticket.clients.name,
    }))

    return NextResponse.json({ status: 'ok', data: tickets })
  } catch (error) {
    console.error('予期しないエラー:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
