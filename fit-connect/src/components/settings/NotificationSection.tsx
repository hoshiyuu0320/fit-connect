'use client'

import { useState, useEffect, useCallback } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { supabase } from '@/lib/supabase'

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

type NotificationKind = 'message' | 'goal_achievement'

const NOTIFICATION_KINDS: {
  kind: NotificationKind
  label: string
  description: string
}[] = [
  {
    kind: 'message',
    label: 'メッセージ受信',
    description: 'クライアントからメッセージが届いたとき',
  },
  {
    kind: 'goal_achievement',
    label: '目標達成のお知らせ',
    description: 'クライアントが目標を達成したとき',
  },
]

type NotificationSectionProps = {
  trainerId: string
}

export function NotificationSection({ trainerId }: NotificationSectionProps) {
  const [permission, setPermission] = useState<NotificationPermission>('default')
  const [isSubscribed, setIsSubscribed] = useState(false)
  const [loading, setLoading] = useState(false)
  const [supported, setSupported] = useState(true)
  // 行が無ければ有効（デフォルトON）
  const [prefs, setPrefs] = useState<Record<NotificationKind, boolean>>({
    message: true,
    goal_achievement: true,
  })
  const [savingKind, setSavingKind] = useState<NotificationKind | null>(null)
  const [prefError, setPrefError] = useState<string | null>(null)

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

  // 通知種別ごとの設定を読み込み（RLSにより自分の行のみ取得可能）
  useEffect(() => {
    if (!trainerId) return
    let cancelled = false

    const loadPreferences = async () => {
      const { data, error } = await supabase
        .from('notification_preferences')
        .select('kind, enabled')
        .eq('user_id', trainerId)

      if (cancelled) return

      if (error) {
        console.error('通知設定の取得エラー:', error)
        return
      }

      if (data && data.length > 0) {
        setPrefs((prev) => {
          const next = { ...prev }
          for (const row of data as { kind: string; enabled: boolean }[]) {
            if (row.kind === 'message' || row.kind === 'goal_achievement') {
              next[row.kind] = row.enabled
            }
          }
          return next
        })
      }
    }

    loadPreferences()
    return () => {
      cancelled = true
    }
  }, [trainerId])

  const handleTogglePref = useCallback(
    async (kind: NotificationKind) => {
      if (!trainerId) return
      const nextValue = !prefs[kind]

      setSavingKind(kind)
      setPrefError(null)
      // 楽観的更新
      setPrefs((prev) => ({ ...prev, [kind]: nextValue }))

      const { error } = await supabase.from('notification_preferences').upsert(
        {
          user_id: trainerId,
          kind,
          enabled: nextValue,
        },
        { onConflict: 'user_id,kind' }
      )

      if (error) {
        console.error('通知設定の保存エラー:', error)
        // ロールバック
        setPrefs((prev) => ({ ...prev, [kind]: !nextValue }))
        setPrefError('通知設定の保存に失敗しました。再度お試しください。')
      }

      setSavingKind(null)
    },
    [trainerId, prefs]
  )

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

        {/* 通知種別ごとの設定 */}
        <div className="border-t border-gray-100 pt-4 space-y-3">
          <p className="text-sm font-medium text-gray-700">通知の種類</p>

          {prefError && (
            <div className="text-sm px-3 py-2 rounded bg-red-50 text-red-600">
              {prefError}
            </div>
          )}

          <div className={`space-y-3 ${isSubscribed ? '' : 'opacity-50'}`}>
            {NOTIFICATION_KINDS.map(({ kind, label, description }) => (
              <div key={kind} className="flex items-center justify-between">
                <div>
                  <Label
                    htmlFor={`notification-${kind}`}
                    className="text-sm font-normal"
                  >
                    {label}
                  </Label>
                  <p className="text-xs text-gray-500">{description}</p>
                </div>
                <button
                  id={`notification-${kind}`}
                  type="button"
                  role="switch"
                  aria-checked={prefs[kind]}
                  disabled={!isSubscribed || savingKind === kind}
                  onClick={() => handleTogglePref(kind)}
                  className={`relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed ${
                    prefs[kind] ? 'bg-blue-600' : 'bg-gray-300'
                  }`}
                >
                  <span
                    className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                      prefs[kind] ? 'translate-x-6' : 'translate-x-1'
                    }`}
                  />
                </button>
              </div>
            ))}
          </div>

          {!isSubscribed && (
            <p className="text-xs text-gray-400">
              プッシュ通知をオンにすると種類ごとの設定を変更できます。
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
