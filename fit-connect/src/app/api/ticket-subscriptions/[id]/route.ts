import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

// PUT: ステータス変更
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  try {
    const body = await request.json()
    const { status } = body

    if (!status || !['active', 'paused', 'cancelled'].includes(status)) {
      return NextResponse.json(
        { error: 'Valid status is required (active, paused, or cancelled)' },
        { status: 400 }
      )
    }

    const { data, error } = await supabaseAdmin
      .from('ticket_subscriptions')
      .update({ status })
      .eq('id', id)
      .select()
      .single()

    if (error) {
      console.error('ステータス更新エラー:', error)
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

// DELETE: 契約削除
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  try {
    const { error } = await supabaseAdmin
      .from('ticket_subscriptions')
      .delete()
      .eq('id', id)

    if (error) {
      console.error('契約削除エラー:', error)
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
