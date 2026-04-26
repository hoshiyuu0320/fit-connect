import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

// GET: 月契約一覧
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
      .from('ticket_subscriptions')
      .select('*, ticket_templates!inner(*, trainer_id), clients!inner(name)')
      .eq('ticket_templates.trainer_id', trainerId)
      .order('created_at', { ascending: false })

    if (error) {
      console.error('月契約一覧取得エラー:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    // Map the response
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const subscriptions = data.map((sub: any) => ({
      id: sub.id,
      template_id: sub.template_id,
      client_id: sub.client_id,
      status: sub.status,
      start_date: sub.start_date,
      next_issue_date: sub.next_issue_date,
      created_at: sub.created_at,
      template: {
        id: sub.ticket_templates.id,
        trainer_id: sub.ticket_templates.trainer_id,
        template_name: sub.ticket_templates.template_name,
        ticket_type: sub.ticket_templates.ticket_type,
        total_sessions: sub.ticket_templates.total_sessions,
        valid_months: sub.ticket_templates.valid_months,
        is_recurring: sub.ticket_templates.is_recurring,
        created_at: sub.ticket_templates.created_at,
        updated_at: sub.ticket_templates.updated_at,
      },
      client_name: sub.clients.name,
    }))

    return NextResponse.json({ status: 'ok', data: subscriptions })
  } catch (error) {
    console.error('予期しないエラー:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}

// POST: 月契約作成 + 初回チケット即発行
export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { templateId, clientId, startDate } = body

    if (!templateId || !clientId || !startDate) {
      return NextResponse.json(
        { error: 'templateId, clientId, and startDate are required' },
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

    // 2. 月契約を作成（next_issue_date は後で更新）
    const { data: subscription, error: subscriptionError } = await supabaseAdmin
      .from('ticket_subscriptions')
      .insert([
        {
          template_id: templateId,
          client_id: clientId,
          status: 'active',
          start_date: startDate,
          next_issue_date: startDate, // 仮設定
        },
      ])
      .select()
      .single()

    if (subscriptionError || !subscription) {
      console.error('月契約作成エラー:', subscriptionError)
      return NextResponse.json(
        { error: subscriptionError?.message || 'Failed to create subscription' },
        { status: 500 }
      )
    }

    // 3. 初回チケットを発行
    const validFrom = new Date(startDate)
    const validUntil = new Date(validFrom)
    if (template.valid_months) {
      validUntil.setMonth(validUntil.getMonth() + template.valid_months)
    }

    const { data: ticket, error: ticketError } = await supabaseAdmin
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

    if (ticketError) {
      console.error('初回チケット発行エラー:', ticketError)
      // ロールバック処理（月契約を削除）
      await supabaseAdmin
        .from('ticket_subscriptions')
        .delete()
        .eq('id', subscription.id)

      return NextResponse.json(
        { error: 'Failed to issue initial ticket' },
        { status: 500 }
      )
    }

    // 4. 次回発行日を更新
    const nextIssueDate = new Date(validFrom)
    if (template.valid_months) {
      nextIssueDate.setMonth(nextIssueDate.getMonth() + template.valid_months)
    }

    const { error: updateError } = await supabaseAdmin
      .from('ticket_subscriptions')
      .update({ next_issue_date: nextIssueDate.toISOString() })
      .eq('id', subscription.id)

    if (updateError) {
      console.error('次回発行日更新エラー:', updateError)
      // エラーでも継続（重大ではない）
    }

    return NextResponse.json({
      status: 'ok',
      data: {
        subscription: {
          ...subscription,
          next_issue_date: nextIssueDate.toISOString(),
        },
        ticket,
      },
    })
  } catch (error) {
    console.error('予期しないエラー:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
