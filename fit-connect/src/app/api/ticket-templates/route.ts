import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { requireTrainer } from '@/lib/api/guards'

// GET: トレーナーのテンプレート一覧取得
export async function GET() {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const { data, error } = await supabaseAdmin
      .from('ticket_templates')
      .select('*')
      .eq('trainer_id', trainerId)
      .order('created_at', { ascending: false })

    if (error) {
      console.error('テンプレート取得エラー:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({ status: 'ok', data })
  } catch (error) {
    console.error('予期しないエラー:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}

// POST: テンプレート作成
export async function POST(request: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const body = await request.json()
    const { templateName, ticketType, totalSessions, validMonths, isRecurring } = body

    if (!templateName || !ticketType || !totalSessions) {
      return NextResponse.json(
        { error: 'templateName, ticketType, totalSessions are required' },
        { status: 400 }
      )
    }

    const { data, error } = await supabaseAdmin
      .from('ticket_templates')
      .insert([
        {
          trainer_id: trainerId,
          template_name: templateName,
          ticket_type: ticketType,
          total_sessions: totalSessions,
          valid_months: validMonths || null,
          is_recurring: isRecurring || false,
        },
      ])
      .select()
      .single()

    if (error) {
      console.error('テンプレート作成エラー:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({ status: 'ok', data })
  } catch (error) {
    console.error('予期しないエラー:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
