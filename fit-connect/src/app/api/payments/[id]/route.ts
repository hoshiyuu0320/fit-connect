import { NextRequest, NextResponse } from 'next/server'
import { getAuthenticatedUser } from '@/lib/supabase/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { parsePaymentPatchBody } from '@/lib/payments/validation'

/**
 * 対象 payment が認証トレーナーの所有かを検証する。
 * 不存在・他人の所有はいずれも false（レスポンスは 404 に統一し、存在を漏らさない）。
 */
async function isOwnedPayment(paymentId: string, trainerId: string): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('payments')
    .select('id, trainer_id')
    .eq('id', paymentId)
    .maybeSingle()
  if (error) {
    throw error
  }
  return data !== null && data.trainer_id === trainerId
}

/**
 * PATCH /api/payments/[id]
 * Body（いずれか）:
 * - { action: 'mark_paid', method: PaymentMethod, paidAt?: string(ISO), receiptNumber?: string }
 * - { action: 'mark_unpaid' }
 * - { action: 'update', note?: string, dueDate?: string | null, amountYen?: number }
 */
export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    // 認証必須
    const user = await getAuthenticatedUser()
    if (!user) {
      return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 })
    }
    const { id } = await params

    // リクエストボディ検証（純関数）
    let body: unknown
    try {
      body = await req.json()
    } catch {
      return NextResponse.json({ error: 'INVALID_BODY' }, { status: 400 })
    }
    const parsed = parsePaymentPatchBody(body)
    if (!parsed.ok) {
      return NextResponse.json({ error: parsed.error }, { status: 400 })
    }

    // 本人所有検証（不存在・不一致は 404）
    if (!(await isOwnedPayment(id, user.id))) {
      return NextResponse.json({ error: 'NOT_FOUND' }, { status: 404 })
    }

    const action = parsed.value
    const updateData: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    }
    if (action.action === 'mark_paid') {
      updateData.status = 'paid'
      updateData.method = action.method
      updateData.paid_at = action.paidAt ?? new Date().toISOString()
      updateData.receipt_number = action.receiptNumber
    } else if (action.action === 'mark_unpaid') {
      updateData.status = 'unpaid'
      updateData.method = null
      updateData.paid_at = null
    } else {
      if (action.note !== undefined) updateData.note = action.note
      if (action.dueDate !== undefined) updateData.due_date = action.dueDate
      if (action.amountYen !== undefined) updateData.amount_yen = action.amountYen
    }

    const { data: payment, error: updateError } = await supabaseAdmin
      .from('payments')
      .update(updateData)
      .eq('id', id)
      .select()
      .single()
    if (updateError) {
      console.error('payments PATCH: UPDATE エラー:', updateError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }

    return NextResponse.json({ payment })
  } catch (error) {
    console.error('payments PATCH: 予期しないエラー:', error)
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
  }
}

/**
 * DELETE /api/payments/[id]
 * 本人所有の支払記録を削除する。
 */
export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    // 認証必須
    const user = await getAuthenticatedUser()
    if (!user) {
      return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 })
    }
    const { id } = await params

    // 本人所有検証（不存在・不一致は 404）
    if (!(await isOwnedPayment(id, user.id))) {
      return NextResponse.json({ error: 'NOT_FOUND' }, { status: 404 })
    }

    const { error: deleteError } = await supabaseAdmin
      .from('payments')
      .delete()
      .eq('id', id)
    if (deleteError) {
      console.error('payments DELETE: 削除エラー:', deleteError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }

    return NextResponse.json({ status: 'ok' })
  } catch (error) {
    console.error('payments DELETE: 予期しないエラー:', error)
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
  }
}
