'use client'

import { useState } from 'react'
import type { TicketSubscription } from '@/types/client'
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogCancel,
} from '@/components/ui/alert-dialog'
import { Button } from '@/components/ui/button'

interface SubscriptionStatusDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  subscription: TicketSubscription | null
  onUpdated: () => void
}

export function SubscriptionStatusDialog({
  open,
  onOpenChange,
  subscription,
  onUpdated,
}: SubscriptionStatusDialogProps) {
  const [loading, setLoading] = useState(false)

  const handleStatusChange = async (newStatus: TicketSubscription['status']) => {
    if (!subscription) return

    setLoading(true)
    try {
      const res = await fetch(`/api/ticket-subscriptions/${subscription.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: newStatus }),
      })

      if (!res.ok) {
        const error = await res.json()
        throw new Error(error.message || 'ステータスの変更に失敗しました')
      }

      // 成功
      onOpenChange(false)
      onUpdated()
    } catch (error) {
      console.error('ステータス変更エラー:', error)
      alert(error instanceof Error ? error.message : 'ステータスの変更に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  if (!subscription) return null

  const currentStatus = subscription.status
  const statusLabels = {
    active: '有効',
    paused: '一時停止',
    cancelled: '解約済',
  }

  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>月契約のステータスを変更</AlertDialogTitle>
          <AlertDialogDescription asChild>
            <div className="space-y-2">
              <p>
                {subscription.client_name}の「{subscription.template?.template_name}」
              </p>
              <p className="text-sm">
                現在のステータス: <span className="font-medium">{statusLabels[currentStatus]}</span>
              </p>
            </div>
          </AlertDialogDescription>
        </AlertDialogHeader>

        <AlertDialogFooter className="flex-col sm:flex-row gap-2">
          <div className="flex gap-2 flex-wrap">
            <Button
              onClick={() => handleStatusChange('active')}
              disabled={loading || currentStatus === 'active'}
              className="bg-emerald-600 hover:bg-emerald-700 text-white"
            >
              有効にする
            </Button>
            <Button
              onClick={() => handleStatusChange('paused')}
              disabled={loading || currentStatus === 'paused'}
              className="bg-amber-500 hover:bg-amber-600 text-white"
            >
              一時停止
            </Button>
            <Button
              onClick={() => handleStatusChange('cancelled')}
              disabled={loading || currentStatus === 'cancelled'}
              className="bg-rose-600 hover:bg-rose-700 text-white"
              variant="destructive"
            >
              解約する
            </Button>
          </div>
          <AlertDialogCancel disabled={loading}>キャンセル</AlertDialogCancel>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
