import { NextRequest, NextResponse } from 'next/server'
import { updateClient } from '@/lib/supabase/updateClient'
import { requireTrainer, notFoundResponse, trainerOwnsClient } from '@/lib/api/guards'

export async function PUT(
  req: NextRequest,
  { params }: { params: Promise<{ client_id: string }> }
) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  const { client_id } = await params
  const body = await req.json()

  if (!client_id) {
    return NextResponse.json({ error: 'Missing client ID' }, { status: 400 })
  }

  if (!(await trainerOwnsClient(trainerId, client_id))) {
    return notFoundResponse()
  }

  try {
    const data = await updateClient({
      clientId: client_id,
      ...body,
    })

    return NextResponse.json({ status: 'ok', data })
  } catch (error) {
    console.error('クライアント更新エラー:', error)
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Unknown error' },
      { status: 500 }
    )
  }
}
