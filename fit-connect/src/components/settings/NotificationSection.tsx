'use client'

import { useState, useEffect, useCallback } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { supabase } from '@/lib/supabase'
import { urlBase64ToUint8Array } from '@/lib/notifications/pushSubscriptionKey'
import { syncPushSubscription, type SubscriptionSnapshot } from '@/lib/notifications/syncPushSubscription'

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

const MESSAGE_KEY_MISSING = '現在プッシュ通知を有効にできません。時間をおいて再度お試しください。'
const MESSAGE_REGISTER_FAILED = 'プッシュ通知の登録に失敗しました。再度お試しください。'
const MESSAGE_CHANGE_FAILED = 'プッシュ通知の設定を変更できませんでした。再度お試しください。'
const MESSAGE_PREF_SAVE_FAILED = '通知設定の保存に失敗しました。再度お試しください。'
const NOTICE_RESUBSCRIBE = '通知の設定が変わりました。もう一度オンにしてください。'

/** POST / DELETE /api/push-subscriptions を呼び、2xx なら true（例外はそのまま投げる。非 2xx は原因を追えるよう HTTP ステータスをログに残す） */
async function callPushSubscriptionsApi(method: 'POST' | 'DELETE', body: object): Promise<boolean> {
  const response = await fetch('/api/push-subscriptions', {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!response.ok) {
    console.error('[NotificationSection] /api/push-subscriptions の呼び出しに失敗しました:', method, response.status)
  }
  return response.ok
}

/**
 * 登録済みの Service Worker から今の購読を読む（SW や購読が無ければ null）。
 * navigator.serviceWorker.ready は SW が1つも無いと永久に解決しないので、getRegistration を使う
 */
async function readCurrentSubscription(): Promise<{
  subscription: PushSubscription
  snapshot: SubscriptionSnapshot
} | null> {
  const registration = await navigator.serviceWorker.getRegistration()
  if (!registration) return null
  const subscription = await registration.pushManager.getSubscription()
  if (!subscription) return null
  const json = subscription.toJSON()
  return {
    subscription,
    snapshot: {
      endpoint: subscription.endpoint,
      applicationServerKey: subscription.options?.applicationServerKey ?? null,
      p256dh: json.keys?.p256dh ?? null,
      auth: json.keys?.auth ?? null,
    },
  }
}

function isPushSupported(): boolean {
  return (
    typeof window !== 'undefined' &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window
  )
}

type NotificationSectionProps = {
  trainerId: string
}

export function NotificationSection({ trainerId }: NotificationSectionProps) {
  const [permission, setPermission] = useState<NotificationPermission>('default')
  const [isSubscribed, setIsSubscribed] = useState(false)
  const [loading, setLoading] = useState(false)
  // 設定画面を開いたときの購読の登録し直しの最中（親トグルを押せなくする）
  const [syncing, setSyncing] = useState(false)
  const [supported, setSupported] = useState(true)
  // 行が無ければ有効（デフォルトON）
  const [prefs, setPrefs] = useState<Record<NotificationKind, boolean>>({
    message: true,
    goal_achievement: true,
  })
  const [savingKind, setSavingKind] = useState<NotificationKind | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  useEffect(() => {
    // ブラウザがWeb Push APIをサポートしているか確認
    if (!isPushSupported()) {
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

  // 設定画面を開いたときの購読の登録し直し（設計書 §7.2）。通知が許可されているときだけ、マウント時に1回
  useEffect(() => {
    if (!trainerId) return
    if (!isPushSupported()) return
    if (Notification.permission !== 'granted') return

    // React の StrictMode（dev）は effect を2回走らせる。1回目は cleanup で cancelled になるので、
    // 通信・解除の手前で止める（POST / DELETE / unsubscribe を二重に走らせない）
    let cancelled = false
    let current: PushSubscription | null = null
    setSyncing(true)

    syncPushSubscription({
      vapidPublicKey: process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY,
      // syncPushSubscription は例外の原因を捨てて 'failed' を返すだけなので、ここで原因をログに残してから投げ直す
      getSubscription: async () => {
        try {
          const found = await readCurrentSubscription()
          current = found?.subscription ?? null
          return found?.snapshot ?? null
        } catch (error) {
          console.error('[NotificationSection] プッシュ購読の読み取りに失敗しました:', error)
          throw error
        }
      },
      post: async (body) => {
        if (cancelled) return false
        try {
          return await callPushSubscriptionsApi('POST', body)
        } catch (error) {
          console.error('[NotificationSection] /api/push-subscriptions の呼び出しで例外が発生しました:', error)
          throw error
        }
      },
      del: async (body) => {
        if (cancelled) return false
        try {
          return await callPushSubscriptionsApi('DELETE', body)
        } catch (error) {
          console.error('[NotificationSection] /api/push-subscriptions の呼び出しで例外が発生しました:', error)
          throw error
        }
      },
      unsubscribe: async () => {
        if (cancelled || !current) return false
        try {
          const unsubscribed = await current.unsubscribe()
          if (!unsubscribed) {
            console.error('[NotificationSection] プッシュ購読を解除できませんでした（unsubscribe が false）')
          }
          return unsubscribed
        } catch (error) {
          console.error('[NotificationSection] プッシュ購読の解除に失敗しました:', error)
          throw error
        }
      },
    })
      .then((result) => {
        if (cancelled) return
        if (result === 'purged') {
          setIsSubscribed(false)
          setNotice(NOTICE_RESUBSCRIBE)
        } else if (result === 'failed') {
          console.error('[NotificationSection] プッシュ通知の購読の登録し直しに失敗しました')
        }
      })
      .finally(() => {
        if (!cancelled) setSyncing(false)
      })

    return () => {
      cancelled = true
    }
  }, [trainerId])

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
      setErrorMessage(null)
      setNotice(null)
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
        setErrorMessage(MESSAGE_PREF_SAVE_FAILED)
      }

      setSavingKind(null)
    },
    [trainerId, prefs]
  )

  const handleEnable = useCallback(async () => {
    if (!trainerId) return
    setErrorMessage(null)
    setNotice(null)

    // 公開鍵が無いと購読できない。許可のダイアログを出す前に確かめる
    const vapidPublicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY
    if (!vapidPublicKey) {
      setErrorMessage(MESSAGE_KEY_MISSING)
      return
    }

    setLoading(true)

    try {
      // 1. 通知の許可をリクエスト（閉じた・拒否は何も出さない。拒否は下の説明文で案内する）
      const result = await Notification.requestPermission()
      setPermission(result)

      if (result !== 'granted') {
        return
      }

      // 2. Service Workerを登録
      const registration = await navigator.serviceWorker.register('/sw.js', { scope: '/' })
      await navigator.serviceWorker.ready

      // 3. Push購読を作成
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
      })

      const subscriptionJson = subscription.toJSON()
      const p256dh = subscriptionJson.keys?.p256dh
      const auth = subscriptionJson.keys?.auth

      if (!subscription.endpoint || !p256dh || !auth) {
        console.error('Invalid subscription data')
        setErrorMessage(MESSAGE_CHANGE_FAILED)
        return
      }

      // 4. サーバーに購読情報を保存
      const saved = await callPushSubscriptionsApi('POST', {
        endpoint: subscription.endpoint,
        p256dh,
        auth,
      })

      if (saved) {
        setIsSubscribed(true)
      } else {
        setErrorMessage(MESSAGE_REGISTER_FAILED)
      }
    } catch (error) {
      console.error('Error enabling push notifications:', error)
      setErrorMessage(MESSAGE_CHANGE_FAILED)
    } finally {
      setLoading(false)
    }
  }, [trainerId])

  const handleDisable = useCallback(async () => {
    if (!trainerId) return
    setErrorMessage(null)
    setNotice(null)
    setLoading(true)

    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.getSubscription()

      if (subscription) {
        // 1. サーバーから購読情報を削除。失敗したらブラウザの購読は残す（やり直せるように）
        const deleted = await callPushSubscriptionsApi('DELETE', {
          endpoint: subscription.endpoint,
        })
        if (!deleted) {
          setErrorMessage(MESSAGE_CHANGE_FAILED)
          return
        }

        // 2. ブラウザの購読を解除
        await subscription.unsubscribe()
      }

      setIsSubscribed(false)
    } catch (error) {
      console.error('Error disabling push notifications:', error)
      setErrorMessage(MESSAGE_CHANGE_FAILED)
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
            disabled={loading || syncing || permission === 'denied'}
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

          {errorMessage && (
            <div role="alert" className="text-sm px-3 py-2 rounded bg-red-50 text-red-600">
              {errorMessage}
            </div>
          )}

          {notice && (
            <div
              role="status"
              className="text-sm px-3 py-2 rounded border border-slate-200 bg-slate-50 text-slate-700"
            >
              {notice}
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
