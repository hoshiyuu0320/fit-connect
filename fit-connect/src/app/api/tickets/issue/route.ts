import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

// POST: テンプレートから都度発行
export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { templateId, clientId } = body

    if (!templateId || !clientId) {
      return NextResponse.json(
        { error: 'templateId and clientId are required' },
        { status: 400 }
      )
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

    // 3. チケットを発行
    const { data, error } = await supabaseAdmin
      .from('tickets')
      .insert([
        {
          client_id: clientId,
          ticket_name: template.template_name,
          ticket_type: template.ticket_type,
          total_sessions: template.total_sessions,
          remaining_sessions: template.total_sessions,
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

    return NextResponse.json({ status: 'ok', data })
  } catch (error) {
    console.error('予期しないエラー:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
