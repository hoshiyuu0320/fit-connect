import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { toJstDateString } from '@/lib/payments/jstDate'
import {
  requireTrainer,
  notFoundResponse,
  trainerOwnsClient,
  trainerOwnsTemplate,
} from '@/lib/api/guards'

// POST: テンプレートから都度発行
export async function POST(request: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const body = await request.json()
    const { templateId, clientId } = body

    if (!templateId || !clientId) {
      return NextResponse.json(
        { error: 'templateId and clientId are required' },
        { status: 400 }
      )
    }

    if (!(await trainerOwnsTemplate(trainerId, templateId))) {
      return notFoundResponse()
    }
    if (!(await trainerOwnsClient(trainerId, clientId))) {
      return notFoundResponse()
    }

    // 1. テンプレート情報を取得
    const { data: template, error: templateError } = await supabaseAdmin
      .from('ticket_templates')
      .select('*')
      .eq('id', templateId)
      .single()

    if (templateError || !template) {
      console.error('テンプレート取得エラー:', templateError)
      return NextResponse.json(
        { error: 'Template not found' },
        { status: 404 }
      )
    }

    // 2. 有効期限を計算
    const validFrom = new Date()
    const validUntil = new Date(validFrom)
    if (template.valid_months) {
      validUntil.setMonth(validUntil.getMonth() + template.valid_months)
    }

    // 3. チケットを発行（テンプレートの価格をスナップショット）
    const { data, error } = await supabaseAdmin
      .from('tickets')
      .insert([
        {
          client_id: clientId,
          ticket_name: template.template_name,
          ticket_type: template.ticket_type,
          total_sessions: template.total_sessions,
          remaining_sessions: template.total_sessions,
          price_yen: template.price_yen ?? null,
          valid_from: validFrom.toISOString(),
          valid_until: validUntil.toISOString(),
        },
      ])
      .select()
      .single()

    if (error) {
      console.error('チケット発行エラー:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    // 4. 価格が設定されていれば未払いの支払記録を自動生成
    //    trainer_id は body を信頼せず clients テーブルの逆引きでサーバー側解決する
    if (template.price_yen != null) {
      const { data: client, error: clientError } = await supabaseAdmin
        .from('clients')
        .select('trainer_id')
        .eq('client_id', clientId)
        .maybeSingle()

      if (clientError || !client) {
        console.error(
          'チケット発行: clients 逆引きに失敗したため支払記録は未作成:',
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
              amount_yen: template.price_yen,
              status: 'unpaid',
              due_date: toJstDateString(validFrom),
            },
          ])
        if (paymentError) {
          console.error('チケット発行: 支払記録の自動生成エラー:', paymentError)
        }
      }
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
