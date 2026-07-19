import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { isPriceYenInput } from '@/lib/payments/validation'

// GET: トレーナーのテンプレート一覧取得
export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams
  const trainerId = searchParams.get('trainerId')

  if (!trainerId) {
    return NextResponse.json(
      { error: 'trainerId is required' },
      { status: 400 }
    )
  }

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
  try {
    const body = await request.json()
    const { trainerId, templateName, ticketType, totalSessions, validMonths, isRecurring, priceYen } = body

    if (!trainerId || !templateName || !ticketType || !totalSessions) {
      return NextResponse.json(
        { error: 'trainerId, templateName, ticketType, totalSessions are required' },
        { status: 400 }
      )
    }

    // priceYen は任意入力（0以上の整数 or null）
    if (priceYen !== undefined && !isPriceYenInput(priceYen)) {
      return NextResponse.json(
        { error: 'priceYen must be a non-negative integer or null' },
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
          price_yen: priceYen ?? null,
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
