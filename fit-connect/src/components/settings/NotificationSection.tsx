'use client'

import { useState, useEffect, useCallback } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData = window.atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray
}

type NotificationSectionProps = {
  trainerId: string
}

export function NotificationSection({ trainerId }: NotificationSectionProps) {
  const [permission, setPermission] = useState<NotificationPermission>('default')
  const [isSubscribed, setIsSubscribed] = useState(false)
  const [loading, setLoading] = useState(false)
  const [supported, setSupported] = useState(true)

  useEffect(() => {
    if (typeof window === 'undefined') return

    // ブラウザがWeb Push APIをサポートしているか確認
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
      setSupported(false)
      return
    }

    setPermission(Notification.permission)

    // 既存のsubscriptionがあるか確認
    navigator.serviceWorker.ready.then((registration) => {
      registration.pushManager.getSubscription().then((subscription) => {
        setIsSubscribed(!!subscription)
      })
    })
  }, [])

  const handleEnable = useCallback(async () => {
    if (!trainerId) return
    setLoading(true)

    try {
      // 1. 通知の許可をリクエスト
      const result = await Notification.requestPermission()
      setPermission(result)

      if (result !== 'granted') {
        return
      }

      // 2. Service Workerを登録
      const registration = await navigator.serviceWorker.register('/sw.js', { scope: '/' })
      await navigator.serviceWorker.ready

      // 3. Push購読を作成
      const vapidPublicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY
      if (!vapidPublicKey) {
        console.error('VAPID public key is not configured')
        return
      }

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
      })

      const subscriptionJson = subscription.toJSON()
      const p256dh = subscriptionJson.keys?.p256dh
      const auth = subscriptionJson.keys?.auth

      if (!subscription.endpoint || !p256dh || !auth) {
        console.error('Invalid subscription data')
        return
      }

      // 4. サーバーに購読情報を保存
      const response = await fetch('/api/push-subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          trainerId,
          endpoint: subscription.endpoint,
          p256dh,
          auth,
        }),
      })

      if (response.ok) {
        setIsSubscribed(true)
      }
    } catch (error) {
      console.error('Error enabling push notifications:', error)
    } finally {
      setLoading(false)
    }
  }, [trainerId])

  const handleDisable = useCallback(async () => {
    if (!trainerId) return
    setLoading(true)

    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()

      if (subscription) {
        // 1. サーバーから購読情報を削除
        await fetch('/api/push-subscriptions', {
          method: 'DELETE',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            trainerId,
            endpoint: subscription.endpoint,
          }),
        })

        // 2. ブラウザの購読を解除
        await subscription.unsubscribe()
      }

      setIsSubscribed(false)
    } catch (error) {
      console.error('Error disabling push notifications:', error)
    } finally {
      setLoading(false)
    }
  }, [trainerId])

  if (!supported) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>通知設定</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-gray-500">
            このブラウザはプッシュ通知に対応していません。Chrome、Edge、またはFirefoxの最新版をご利用ください。
          </p>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>通知設定</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <Label htmlFor="push-notification" className="text-base font-normal">
            プッシュ通知
          </Label>
          <button
            id="push-notification"
            type="button"
            role="switch"
            aria-checked={isSubscribed}
            disabled={loading || permission === 'denied'}
            onClick={isSubscribed ? handleDisable : handleEnable}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 ${
              isSubscribed ? 'bg-blue-600' : 'bg-gray-300'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                isSubscribed ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>

        <p className="text-sm text-gray-500">
          {permission === 'denied'
            ? '通知がブラウザの設定でブロックされています。アドレスバー横の鍵アイコンから通知を「許可」に変更してください。'
            : 'クライアントからメッセージが届いた際にブラウザ通知でお知らせします。'}
        </p>
      </CardContent>
    </Card>
  )
}
