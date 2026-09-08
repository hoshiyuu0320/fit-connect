import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import {
  requireTrainer,
  notFoundResponse,
  trainerOwnsClient,
  trainerOwnsSession,
} from '@/lib/api/guards'

export async function POST(req: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  const body = await req.json()
  const { clientId, title, content, fileUrls, isShared, sessionId } = body

  if (!clientId || !title) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 })
  }

  if (!(await trainerOwnsClient(trainerId, clientId))) {
    return notFoundResponse()
  }

  // 対象セッションは任意。指定された場合のみ所有検証を通す（リクエスト由来の値は信用しない）
  const linkedSessionId = typeof sessionId === 'string' && sessionId ? sessionId : null
  if (linkedSessionId && !(await trainerOwnsSession(trainerId, linkedSessionId))) {
    return notFoundResponse()
  }

  const { data, error } = await supabaseAdmin
    .from('client_notes')
    .insert([
      {
        trainer_id: trainerId,
        client_id: clientId,
        title,
        content: content || '',
        file_urls: fileUrls || [],
        is_shared: isShared || false,
        ...(isShared && { shared_at: new Date().toISOString() }),
        ...(sessionId !== undefined && { session_id: linkedSessionId }),
      },
    ])
    .select()
    .single()

  if (error) {
    console.error('カルテ作成エラー:', error)
    // 別顧客・別トレーナーのセッション指定は DB トリガーが弾く（通常フローでは起きない）
    if (error.message === 'NOTE_SESSION_MISMATCH') {
      return NextResponse.json({ error: 'NOTE_SESSION_MISMATCH' }, { status: 400 })
    }
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ status: 'ok', data })
}
