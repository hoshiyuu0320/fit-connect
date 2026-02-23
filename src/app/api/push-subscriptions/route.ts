import { NextRequest, NextResponse } from 'next/server'
import { savePushSubscription } from '@/lib/supabase/savePushSubscription'
import { deletePushSubscription } from '@/lib/supabase/deletePushSubscription'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { trainerId, endpoint, p256dh, auth } = body

    if (!trainerId || !endpoint || !p256dh || !auth) {
      return NextResponse.json(
        { error: 'Missing required fields' },
        { status: 400 }
      )
    }

    await savePushSubscription({ trainerId, endpoint, p256dh, auth })

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
  try {
    const body = await request.json()
    const { trainerId, endpoint } = body

    if (!trainerId || !endpoint) {
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
