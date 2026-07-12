import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { isPriceYenInput } from '@/lib/payments/validation'
import { extractDateOnly } from '@/lib/payments/jstDate'
import { requireTrainer, notFoundResponse, trainerOwnsClient } from '@/lib/api/guards'

export async function POST(req: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  const body = await req.json()
  const { clientId, ticketName, ticketType, totalSessions, validFrom, validUntil, priceYen } = body

  if (!clientId || !ticketName || !ticketType || !totalSessions) {
    return NextResponse.json({ error: 'Missing required parameters' }, { status: 400 })
  }

  if (!(await trainerOwnsClient(trainerId, clientId))) {
    return notFoundResponse()
  }

  // priceYen は任意入力（0以上の整数 or null）
  if (priceYen !== undefined && !isPriceYenInput(priceYen)) {
    return NextResponse.json(
      { error: 'priceYen must be a non-negative integer or null' },
      { status: 400 }
    )
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
        price_yen: priceYen ?? null,
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

  // 価格が設定されていれば未払いの支払記録を自動生成
  // trainer_id は body を信頼せず clients テーブルの逆引きでサーバー側解決する
  if (priceYen != null) {
    const { data: client, error: clientError } = await supabaseAdmin
      .from('clients')
      .select('trainer_id')
      .eq('client_id', clientId)
      .maybeSingle()

    if (clientError || !client) {
      console.error(
        'チケット作成: clients 逆引きに失敗したため支払記録は未作成:',
        clientError
      )
    } else {
      const { error: paymentError } = await supabaseAdmin
        .from('payments')
        .insert([
          {
            trainer_id: client.trainer_id,
            client_id: clientId,
            ticket_id: data.id,
            amount_yen: priceYen,
            status: 'unpaid',
            due_date:
              typeof validFrom === 'string' && validFrom
                ? extractDateOnly(validFrom)
                : null,
          },
        ])
      if (paymentError) {
        console.error('チケット作成: 支払記録の自動生成エラー:', paymentError)
      }
    }
  }

  return NextResponse.json({ status: 'ok', data })
}
