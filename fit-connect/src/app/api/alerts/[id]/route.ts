import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { requireTrainer, notFoundResponse, trainerOwnsClient } from '@/lib/api/guards'
import { isUuid, parseAlertPatchBody } from '@/lib/alerts/validation'

/**
 * PATCH /api/alerts/[id]
 * Body: { action: 'acknowledge' | 'reopen' }
 * - acknowledge: open → acknowledged（「対応済み」。acknowledged_at を入れる）
 * - reopen: acknowledged → open（トーストの「元に戻す」。resolved になる前だけ。acknowledged_at を消す）
 *
 * - trainer_id はセッションから取る。本人の行でない・今の担当顧客でない・存在しないはどれも 404
 * - 状態は条件付き UPDATE で遷移させる（検知の本実行と同時に走っても片方しか通らない）。
 *   条件に合わず0行なら、今の status をそのまま 200 で返す（冪等）
 * 返却: { status: 'ok', alert: { id, status } }
 */
export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const auth = await requireTrainer()
    if (auth.response) return auth.response
    const trainerId = auth.user.id

    const { id } = await params

    // リクエストボディ検証（純関数）
    let body: unknown
    try {
      body = await req.json()
    } catch {
      return NextResponse.json({ error: 'INVALID_BODY' }, { status: 400 })
    }
    const parsed = parseAlertPatchBody(body)
    if (!parsed.ok) {
      return NextResponse.json({ error: parsed.error }, { status: 400 })
    }

    // uuid の形でない id は、存在しない id と同じ 404（DB の型エラーで 500 にしない）
    if (!isUuid(id)) {
      return notFoundResponse()
    }

    // 本人の行で、顧客が今も本人の担当か（担当替え後は前のトレーナーから操作させない）
    const { data: alert, error: fetchError } = await supabaseAdmin
      .from('alerts')
      .select('id, trainer_id, client_id')
      .eq('id', id)
      .maybeSingle()
    if (fetchError) {
      console.error('alerts PATCH: 取得エラー:', fetchError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }
    if (!alert || alert.trainer_id !== trainerId) {
      return notFoundResponse()
    }
    if (!(await trainerOwnsClient(trainerId, alert.client_id))) {
      return notFoundResponse()
    }

    const { action } = parsed.value
    const update =
      action === 'acknowledge'
        ? supabaseAdmin
            .from('alerts')
            .update({ status: 'acknowledged', acknowledged_at: new Date().toISOString() })
            .eq('id', id)
            .eq('trainer_id', trainerId)
            .eq('status', 'open')
        : supabaseAdmin
            .from('alerts')
            .update({ status: 'open', acknowledged_at: null })
            .eq('id', id)
            .eq('trainer_id', trainerId)
            .eq('status', 'acknowledged')
            .is('resolved_at', null)

    const { data: updated, error: updateError } = await update
      .select('id, status')
      .maybeSingle()
    if (updateError) {
      console.error('alerts PATCH: UPDATE エラー:', updateError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }
    if (updated) {
      return NextResponse.json({ status: 'ok', alert: { id: updated.id, status: updated.status } })
    }

    // 条件に合わず0行（二度押し・検知の本実行が先に resolved にした等）: 今の status をそのまま返す
    const { data: current, error: currentError } = await supabaseAdmin
      .from('alerts')
      .select('id, status')
      .eq('id', id)
      .maybeSingle()
    if (currentError) {
      console.error('alerts PATCH: 再取得エラー:', currentError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }
    if (!current) {
      // 間に顧客の退会（CASCADE）で消えた
      return notFoundResponse()
    }
    return NextResponse.json({ status: 'ok', alert: { id: current.id, status: current.status } })
  } catch (error) {
    console.error('alerts PATCH: 予期しないエラー:', error)
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
  }
}
