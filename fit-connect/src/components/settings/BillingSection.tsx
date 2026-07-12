'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { ChevronRight } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { PLANS, type PlanId } from '@/lib/billing/plans'

interface BillingStatusSummary {
  effectivePlan: PlanId
  isTrial: boolean
  trialDaysLeft: number | null
}

export function BillingSection() {
  const [status, setStatus] = useState<BillingStatusSummary | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false

    const fetchStatus = async () => {
      try {
        const res = await fetch('/api/billing/status')
        if (!res.ok) {
          throw new Error(`契約状況の取得に失敗しました (${res.status})`)
        }
        const data: BillingStatusSummary = await res.json()
        if (!cancelled) {
          setStatus(data)
        }
      } catch (error) {
        console.error('契約状況取得エラー:', error)
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }

    fetchStatus()

    return () => {
      cancelled = true
    }
  }, [])

  return (
    <Card>
      <CardHeader>
        <CardTitle>プラン・お支払い</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <p className="text-sm text-gray-600">現在のプラン</p>
          {loading ? (
            <div className="h-6 w-20 rounded-md bg-gray-100 animate-pulse" />
          ) : status ? (
            <div className="flex items-center gap-2">
              {status.isTrial && (
                <span className="text-xs text-blue-700">
                  Proトライアル中
                  {status.trialDaysLeft != null && `（残り${status.trialDaysLeft}日）`}
                </span>
              )}
              <span className="inline-flex items-center rounded-md bg-gray-100 px-2.5 py-0.5 text-sm font-medium text-gray-900">
                {PLANS[status.effectivePlan]?.label ?? status.effectivePlan}
              </span>
            </div>
          ) : (
            <span className="text-sm text-gray-400">-</span>
          )}
        </div>
        <div className="border-t pt-1">
          <Link
            href="/settings/billing"
            className="flex items-center justify-between p-3 -mx-3 rounded-lg hover:bg-gray-50 transition-colors cursor-pointer"
          >
            <p className="text-sm font-medium text-gray-900">プランを管理</p>
            <ChevronRight className="w-5 h-5 text-gray-400" />
          </Link>
        </div>
      </CardContent>
    </Card>
  )
}
