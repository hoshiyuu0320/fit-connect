'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { QRCodeCanvas } from 'qrcode.react'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Alert, AlertTitle, AlertDescription } from '@/components/ui/alert'
import { Copy, Download, AlertTriangle } from 'lucide-react'
import { getClientCount } from '@/lib/supabase/getClientCount'
import { PLANS, type PlanId } from '@/lib/billing/plans'

type ClientInviteModalProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  trainerId: string
}

type ClientLimitInfo = {
  count: number
  maxClients: number
  planLabel: string
}

export default function ClientInviteModal({ open, onOpenChange, trainerId }: ClientInviteModalProps) {
  const [copied, setCopied] = useState(false)
  const [limitInfo, setLimitInfo] = useState<ClientLimitInfo | null>(null)

  useEffect(() => {
    if (!open) return

    let cancelled = false

    const fetchLimitInfo = async () => {
      try {
        const [count, res] = await Promise.all([
          getClientCount(trainerId),
          fetch('/api/billing/status'),
        ])
        if (!res.ok) {
          throw new Error(`課金状態の取得に失敗しました (${res.status})`)
        }
        const data: { effectivePlan?: string } = await res.json()
        const effectivePlan = data.effectivePlan
        if (effectivePlan !== 'free' && effectivePlan !== 'pro' && effectivePlan !== 'business') {
          throw new Error('不正なプラン値です')
        }
        const plan = PLANS[effectivePlan as PlanId]
        if (!cancelled) {
          setLimitInfo({
            count,
            maxClients: plan.maxClients,
            planLabel: plan.label,
          })
        }
      } catch (error) {
        // 取得失敗時は既存表示のまま（DB側トリガーが最終防衛のため fail-open）
        console.error('顧客数上限情報の取得エラー:', error)
        if (!cancelled) {
          setLimitInfo(null)
        }
      }
    }

    fetchLimitInfo()

    return () => {
      cancelled = true
    }
  }, [open, trainerId])

  const limitReached = limitInfo != null && limitInfo.count >= limitInfo.maxClients

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(trainerId)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch (error) {
      console.error('コピーに失敗しました:', error)
      // Fallback for older browsers
      const input = document.createElement('input')
      input.value = trainerId
      document.body.appendChild(input)
      input.select()
      document.execCommand('copy')
      document.body.removeChild(input)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const handleDownloadQR = () => {
    const canvas = document.getElementById('invite-qr-code') as HTMLCanvasElement
    if (!canvas) return

    const url = canvas.toDataURL('image/png')
    const link = document.createElement('a')
    link.href = url
    link.download = 'fitconnect-invite.png'
    link.click()
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px] bg-white">
        <DialogHeader>
          <DialogTitle>クライアントを招待</DialogTitle>
        </DialogHeader>

        {limitReached ? (
          <div className="space-y-6">
            {/* 上限到達の警告（アップグレード誘導） */}
            <Alert className="border-amber-200 bg-amber-50 text-amber-900 rounded-md [&>svg]:text-amber-600">
              <AlertTriangle className="h-4 w-4" />
              <AlertTitle>顧客数が上限に達しています</AlertTitle>
              <AlertDescription className="text-amber-800">
                顧客数が上限（{limitInfo.maxClients}人）に達しています。
                新しい顧客を招待するには、プランのアップグレードが必要です。
              </AlertDescription>
            </Alert>

            <p className="text-sm text-gray-600 text-center">
              顧客数: 現在{limitInfo.count}人 / 上限{limitInfo.maxClients}人（{limitInfo.planLabel}プラン）
            </p>

            <Button asChild className="w-full">
              <Link href="/settings/billing">プランを確認する</Link>
            </Button>
          </div>
        ) : (
          <div className="space-y-6">
            {/* 説明テキスト */}
            <p className="text-sm text-gray-600 text-center">
              QRコードをスキャンするか、招待コードをアプリで入力してください
            </p>

            {/* QRコード表示 */}
            <div className="flex justify-center">
              <div className="bg-white border rounded-lg p-4">
                <QRCodeCanvas
                  id="invite-qr-code"
                  value={trainerId}
                  size={256}
                  level="H"
                  includeMargin={true}
                />
              </div>
            </div>

            {/* 招待コード */}
            <div className="space-y-2">
              <Label htmlFor="invite-code">招待コード</Label>
              <div className="flex gap-2">
                <Input
                  id="invite-code"
                  type="text"
                  value={trainerId}
                  readOnly
                  className="font-mono text-sm"
                />
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  onClick={handleCopy}
                  className="shrink-0"
                >
                  <Copy className="h-4 w-4" />
                </Button>
              </div>
              {copied && (
                <p className="text-sm text-emerald-600 flex items-center gap-1">
                  <span>✓</span>
                  <span>コピーしました</span>
                </p>
              )}
            </div>

            {/* ダウンロードボタン */}
            <Button
              type="button"
              variant="outline"
              onClick={handleDownloadQR}
              className="w-full"
            >
              <Download className="h-4 w-4 mr-2" />
              QRコードをダウンロード
            </Button>

            {/* 顧客数の現在値 / 上限（控えめに表示） */}
            {limitInfo && (
              <p className="text-xs text-gray-500 text-center">
                顧客数: 現在{limitInfo.count}人 / 上限{limitInfo.maxClients}人（{limitInfo.planLabel}プラン）
              </p>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
