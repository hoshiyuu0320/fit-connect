import { NextRequest, NextResponse } from 'next/server'
import { savePushSubscription } from '@/lib/supabase/savePushSubscription'
import { deletePushSubscription } from '@/lib/supabase/deletePushSubscription'
import { requireTrainer } from '@/lib/api/guards'

export async function POST(request: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const body = await request.json()
    const { endpoint, p256dh, auth: pushAuth } = body

    if (!endpoint || !p256dh || !pushAuth) {
      return NextResponse.json(
        { error: 'Missing required fields' },
        { status: 400 }
      )
    }

    await savePushSubscription({ trainerId, endpoint, p256dh, auth: pushAuth })

    return NextResponse.json({ status: 'ok' })
  } catch (error) {
    console.error('Error saving push subscription:', error)
    return NextResponse.json(
      { error: 'Failed to save push subscription' },
      { status: 500 }
    )
  }
}

export async function DELETE(request: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const body = await request.json()
    const { endpoint } = body

    if (!endpoint) {
      return NextResponse.json(
        { error: 'Missing required fields' },
        { status: 400 }
      )
    }

    await deletePushSubscription(trainerId, endpoint)

    return NextResponse.json({ status: 'ok' })
  } catch (error) {
    console.error('Error deleting push subscription:', error)
    return NextResponse.json(
      { error: 'Failed to delete push subscription' },
      { status: 500 }
    )
  }
}
