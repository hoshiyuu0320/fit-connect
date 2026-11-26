import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { requireTrainer, notFoundResponse, trainerOwnsClient } from '@/lib/api/guards'

export async function POST(req: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  const body = await req.json()
  // 画面は sessionNumber も送るが、client_notes に session_number 列は無い（develop の migration で削除済み）ので DB へは送らない
  const { clientId, title, content, fileUrls, isShared } = body

  if (!clientId || !title) {
    return NextResponse.json({ error: 'Missing parameters' }, { status: 400 })
  }

  if (!(await trainerOwnsClient(trainerId, clientId))) {
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
      },
    ])
    .select()
    .single()

  if (error) {
    console.error('カルテ作成エラー:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ status: 'ok', data })
}
