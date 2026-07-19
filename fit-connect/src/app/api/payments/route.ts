import { NextRequest, NextResponse } from 'next/server'
import { getAuthenticatedUser } from '@/lib/supabase/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { isNonNegativeInteger, isDateOnlyString } from '@/lib/payments/validation'

/**
 * POST /api/payments
 * Body: { clientId: string, amountYen: number, dueDate?: 'YYYY-MM-DD', note?: string }
 *
 * 手動の支払記録（status='unpaid'）を作成する。
 * trainer_id は認証ユーザーから導出する（body の値は一切信頼しない）。
 */
export async function POST(req: NextRequest) {
  try {
    // 認証必須
    const user = await getAuthenticatedUser()
    if (!user) {
      return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 })
    }

    // リクエストボディ検証
    let body: Record<string, unknown>
    try {
      body = await req.json()
    } catch {
      return NextResponse.json({ error: 'INVALID_BODY' }, { status: 400 })
    }
    const clientId = body?.clientId
    const amountYen = body?.amountYen
    const dueDate = body?.dueDate
    const note = body?.note

    if (typeof clientId !== 'string' || clientId.length === 0) {
      return NextResponse.json({ error: 'INVALID_CLIENT_ID' }, { status: 400 })
    }
    if (!isNonNegativeInteger(amountYen)) {
      return NextResponse.json({ error: 'INVALID_AMOUNT' }, { status: 400 })
    }
    if (dueDate !== undefined && !isDateOnlyString(dueDate)) {
      return NextResponse.json({ error: 'INVALID_DUE_DATE' }, { status: 400 })
    }
    if (note !== undefined && typeof note !== 'string') {
      return NextResponse.json({ error: 'INVALID_NOTE' }, { status: 400 })
    }

    // clientId が認証トレーナー自身の顧客であることを検証
    const { data: client, error: clientError } = await supabaseAdmin
      .from('clients')
      .select('client_id, trainer_id')
      .eq('client_id', clientId)
      .maybeSingle()
    if (clientError) {
      console.error('payments POST: clients 取得エラー:', clientError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }
    if (!client || client.trainer_id !== user.id) {
      return NextResponse.json({ error: 'CLIENT_NOT_FOUND' }, { status: 404 })
    }

    const { data: payment, error: insertError } = await supabaseAdmin
      .from('payments')
      .insert({
        trainer_id: user.id,
        client_id: clientId,
        amount_yen: amountYen,
        status: 'unpaid',
        due_date: dueDate ?? null,
        note: note ?? null,
      })
      .select()
      .single()
    if (insertError) {
      console.error('payments POST: INSERT エラー:', insertError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }

    return NextResponse.json({ payment }, { status: 201 })
  } catch (error) {
    console.error('payments POST: 予期しないエラー:', error)
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
  }
}
