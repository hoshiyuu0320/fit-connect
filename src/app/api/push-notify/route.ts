import { NextRequest, NextResponse } from 'next/server'
import webpush from 'web-push'

// VAPID設定
const vapidPublicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY
const vapidPrivateKey = process.env.VAPID_PRIVATE_KEY
const vapidSubject = process.env.VAPID_SUBJECT || 'mailto:admin@fit-connect.com'

if (vapidPublicKey && vapidPrivateKey) {
  webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey)
}

export async function POST(request: NextRequest) {
  try {
    // API Key認証（設定されている場合）
    const pushApiKey = process.env.PUSH_API_KEY
    if (pushApiKey) {
      const requestApiKey = request.headers.get('x-api-key')
      if (requestApiKey !== pushApiKey) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
      }
    }

    if (!vapidPublicKey || !vapidPrivateKey) {
      return NextResponse.json(
        { error: 'VAPID keys not configured' },
        { status: 500 }
      )
    }

    const body = await request.json()
    const { subscriptions, title, body: messageBody, url } = body

    if (!subscriptions || !Array.isArray(subscriptions) || subscriptions.length === 0) {
      return NextResponse.json(
        { error: 'No subscriptions provided' },
        { status: 400 }
      )
    }

    const payload = JSON.stringify({
      title: title || '新着メッセージ',
      body: messageBody || '',
      url: url || '/message',
    })

    const results = await Promise.allSettled(
      subscriptions.map((sub: { endpoint: string; keys: { p256dh: string; auth: string } }) =>
        webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: {
              p256dh: sub.keys.p256dh,
              auth: sub.keys.auth,
            },
          },
          payload
        )
      )
    )

    const succeeded = results.filter((r) => r.status === 'fulfilled').length
    const failed = results.filter((r) => r.status === 'rejected').length

    return NextResponse.json({
      status: 'ok',
      sent: succeeded,
      failed,
    })
  } catch (error) {
    console.error('Error sending push notifications:', error)
    return NextResponse.json(
      { error: 'Failed to send push notifications' },
      { status: 500 }
    )
  }
}
