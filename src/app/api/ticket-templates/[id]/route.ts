import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

// PUT: テンプレート更新
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  try {
    const body = await request.json()
    const { templateName, ticketType, totalSessions, validMonths, isRecurring } = body

    // 更新データを構築（undefined でないフィールドのみ）
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const updateData: any = {
      updated_at: new Date().toISOString(),
    }

    if (templateName !== undefined) updateData.template_name = templateName
    if (ticketType !== undefined) updateData.ticket_type = ticketType
    if (totalSessions !== undefined) updateData.total_sessions = totalSessions
    if (validMonths !== undefined) updateData.valid_months = validMonths
    if (isRecurring !== undefined) updateData.is_recurring = isRecurring

    const { data, error } = await supabaseAdmin
      .from('ticket_templates')
      .update(updateData)
      .eq('id', id)
      .select()
      .single()

    if (error) {
      console.error('テンプレート更新エラー:', error)
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

// DELETE: テンプレート削除
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  try {
    const { error } = await supabaseAdmin
      .from('ticket_templates')
      .delete()
      .eq('id', id)

    if (error) {
      console.error('テンプレート削除エラー:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({ status: 'ok' })
  } catch (error) {
    console.error('予期しないエラー:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
