'use client'

import { Suspense, useEffect, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Link from 'next/link'
import { Check, ChevronLeft, Loader2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { PLANS, type PlanId } from '@/lib/billing/plans'

interface BillingStatus {
  billingConfigured: boolean
  plan: PlanId
  effectivePlan: PlanId
  isTrial: boolean
  trialDaysLeft: number | null
  trialEndsAt: string | null
  subscriptionStatus: string | null
  currentPeriodEnd: string | null
  cancelAtPeriodEnd: boolean
  hasStripeCustomer: boolean
}

const PLAN_ORDER: PlanId[] = ['free', 'pro', 'business']

const AI_FEATURE_NOTES: Record<PlanId, string> = {
  free: 'AI食事解析 お試し 月30回',
  pro: 'AI食事解析 利用可（1顧客あたり 日10回・月100回）',
  business: 'AI食事解析 利用可（1顧客あたり 日10回・月100回）',
}

const COMMON_FEATURES = [
  '顧客管理',
  'ワークアウト計画',
  'メッセージ',
  '食事/体重記録',
  'チケット管理',
]

function BillingPageContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const checkoutResult = searchParams.get('checkout')

  const [status, setStatus] = useState<BillingStatus | null>(null)
  const [statusError, setStatusError] = useState(false)
  const [loading, setLoading] = useState(true)
  const [checkoutPlan, setCheckoutPlan] = useState<PlanId | null>(null)
  const [portalLoading, setPortalLoading] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    const init = async () => {
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser()

        if (!user) {
          router.push('/login')
          return
        }

        const res = await fetch('/api/billing/status')
        if (res.status === 401) {
          router.push('/login')
          return
        }
        if (!res.ok) {
          throw new Error(`契約状況の取得に失敗しました (${res.status})`)
        }

        const data: BillingStatus = await res.json()
        if (!cancelled) {
          setStatus(data)
        }
      } catch (error) {
        console.error('契約状況取得エラー:', error)
        if (!cancelled) {
          setStatusError(true)
        }
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }

    init()

    return () => {
      cancelled = true
    }
  }, [router])

  const handleCheckout = async (planId: 'pro' | 'business') => {
    setActionError(null)
    setCheckoutPlan(planId)

    try {
      const res = await fetch('/api/billing/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan: planId }),
      })

      if (res.status === 503) {
        setActionError('決済機能は現在準備中です')
        setCheckoutPlan(null)
        return
      }
      if (res.status === 401) {
        router.push('/login')
        return
      }
      if (!res.ok) {
        throw new Error(`チェックアウトの開始に失敗しました (${res.status})`)
      }

      const { url } = await res.json()
      if (!url) {
        throw new Error('チェックアウトURLが取得できませんでした')
      }

      // 遷移完了までボタンは無効のままにする（多重送信防止）
      window.location.href = url
    } catch (error) {
      console.error('チェックアウトエラー:', error)
      setActionError('決済ページへの遷移に失敗しました。時間をおいて再度お試しください。')
      setCheckoutPlan(null)
    }
  }

  const handlePortal = async () => {
    setActionError(null)
    setPortalLoading(true)

    try {
      const res = await fetch('/api/billing/portal', { method: 'POST' })

      if (res.status === 503) {
        setActionError('決済機能は現在準備中です')
        setPortalLoading(false)
        return
      }
      if (res.status === 400) {
        setActionError('お支払い情報が見つかりませんでした')
        setPortalLoading(false)
        return
      }
      if (!res.ok) {
        throw new Error(`ポータルの取得に失敗しました (${res.status})`)
      }

      const { url } = await res.json()
      if (!url) {
        throw new Error('ポータルURLが取得できませんでした')
      }

      // 遷移完了までボタンは無効のままにする
      window.location.href = url
    } catch (error) {
      console.error('ポータル遷移エラー:', error)
      setActionError('お支払い管理ページへの遷移に失敗しました。時間をおいて再度お試しください。')
      setPortalLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-48px)]">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent"></div>
      </div>
    )
  }

  const currentPlan: PlanId | null = status?.effectivePlan ?? null
  const currentRank = currentPlan ? PLAN_ORDER.indexOf(currentPlan) : null
  const billingUnavailable = status !== null && !status.billingConfigured

  return (
    <main className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-4xl mx-auto p-6 space-y-6">
        {/* 戻るリンク */}
        <Link
          href="/settings"
          className="inline-flex items-center text-sm text-gray-600 hover:text-gray-900 mb-6 cursor-pointer"
        >
          <ChevronLeft className="w-4 h-4 mr-1" />
          設定に戻る
        </Link>

        {/* ページタイトル */}
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-gray-900">プラン・お支払い</h1>
        </div>

        {/* チェックアウト結果メッセージ */}
        {checkoutResult === 'success' && (
          <div className="p-3 rounded-md text-sm bg-emerald-50 text-emerald-700">
            プランを変更しました。反映まで数秒かかる場合があります
          </div>
        )}
        {checkoutResult === 'cancel' && (
          <div className="p-3 rounded-md text-sm bg-gray-100 text-gray-600">
            プランの変更は完了していません。いつでも再度お手続きいただけます。
          </div>
        )}

        {/* トライアルバナー */}
        {status?.isTrial && (
          <div className="p-4 rounded-md text-sm bg-blue-50 text-blue-800 border border-blue-100">
            Proプランを無料トライアル中です
            {status.trialDaysLeft != null && `（残り${status.trialDaysLeft}日）`}
            。終了後は自動的にFreeプランになります。
          </div>
        )}

        {/* 契約状況の取得エラー */}
        {statusError && (
          <div className="p-3 rounded-md text-sm bg-gray-100 text-gray-600">
            現在の契約状況を取得できませんでした。時間をおいてページを再読み込みしてください。
          </div>
        )}

        {/* 決済未設定の注記 */}
        {billingUnavailable && (
          <div className="p-3 rounded-md text-sm bg-gray-100 text-gray-600">
            決済機能は現在準備中です
          </div>
        )}

        {/* 操作エラー */}
        {actionError && (
          <div role="alert" className="p-3 rounded-md text-sm bg-rose-50 text-rose-700">
            {actionError}
          </div>
        )}

        {/* プラン比較カード */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {PLAN_ORDER.map((planId) => {
            const plan = PLANS[planId]
            const isCurrent = currentPlan === planId
            const rank = PLAN_ORDER.indexOf(planId)
            const isUpgrade =
              !isCurrent && (currentRank === null ? planId !== 'free' : rank > currentRank)
            const isCheckingOut = checkoutPlan === planId

            return (
              <Card
                key={planId}
                className={cn('flex flex-col', isCurrent && 'border-primary')}
              >
                <CardHeader>
                  <div className="flex items-start justify-between gap-2">
                    <CardTitle className="text-lg">{plan.label}</CardTitle>
                    {isCurrent ? (
                      <span className="inline-flex items-center rounded-md bg-primary px-2 py-0.5 text-xs font-medium text-primary-foreground whitespace-nowrap">
                        現在のプラン
                      </span>
                    ) : plan.recommended ? (
                      <span className="inline-flex items-center rounded-md bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary whitespace-nowrap">
                        おすすめ
                      </span>
                    ) : null}
                  </div>
                  <div className="pt-2">
                    <span className="text-3xl font-bold text-gray-900">
                      ¥{plan.priceJpy.toLocaleString('ja-JP')}
                    </span>
                    <span className="ml-1 text-sm text-gray-500">/月（税込）</span>
                  </div>
                  <CardDescription>顧客{plan.maxClients}人まで</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-1 flex-col">
                  <ul className="space-y-2 text-sm text-gray-700">
                    <li className="flex items-start gap-2">
                      <Check className="w-4 h-4 mt-0.5 shrink-0 text-teal-600" />
                      <span>{AI_FEATURE_NOTES[planId]}</span>
                    </li>
                    {COMMON_FEATURES.map((feature) => (
                      <li key={feature} className="flex items-start gap-2">
                        <Check className="w-4 h-4 mt-0.5 shrink-0 text-teal-600" />
                        <span>{feature}</span>
                      </li>
                    ))}
                  </ul>
                  <div className="mt-auto pt-6">
                    {isCurrent ? (
                      <Button variant="outline" className="w-full" disabled>
                        利用中
                      </Button>
                    ) : isUpgrade ? (
                      <Button
                        className="w-full cursor-pointer"
                        disabled={checkoutPlan !== null || billingUnavailable}
                        onClick={() => handleCheckout(planId as 'pro' | 'business')}
                      >
                        {isCheckingOut ? (
                          <>
                            <Loader2 className="animate-spin" />
                            処理中...
                          </>
                        ) : (
                          'このプランにする'
                        )}
                      </Button>
                    ) : (
                      <p className="text-xs text-gray-500 text-center py-2">
                        お支払い管理から変更できます
                      </p>
                    )}
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>

        {/* お支払い管理 */}
        {status?.hasStripeCustomer && (
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">お支払い管理</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {status.cancelAtPeriodEnd && (
                <div className="p-3 rounded-md text-sm bg-amber-50 text-amber-800">
                  現在の期間終了時に解約予定です
                </div>
              )}
              <p className="text-sm text-gray-600">
                お支払い方法の変更・解約のお手続きは、Stripeのお客様ポータルから行えます。
              </p>
              <Button
                variant="outline"
                className="cursor-pointer"
                disabled={portalLoading}
                onClick={handlePortal}
              >
                {portalLoading && <Loader2 className="animate-spin" />}
                お支払い方法・解約の管理
              </Button>
            </CardContent>
          </Card>
        )}

        {/* フッタ注記 */}
        <p className="text-xs text-gray-500 text-center pb-6">
          価格はすべて税込です。決済は Stripe により安全に処理されます。
        </p>
      </div>
    </main>
  )
}

export default function BillingPage() {
  return (
    <Suspense
      fallback={
        <div className="flex items-center justify-center h-[calc(100vh-48px)]">
          <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent"></div>
        </div>
      }
    >
      <BillingPageContent />
    </Suspense>
  )
}
