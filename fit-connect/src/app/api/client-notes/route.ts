import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { requireTrainer, notFoundResponse, trainerOwnsClient } from '@/lib/api/guards'

export async function POST(req: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  const body = await req.json()
  const { clientId, title, content, fileUrls, isShared, sessionNumber } = body

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
        ...(sessionNumber !== undefined && { session_number: sessionNumber }),
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
