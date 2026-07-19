'use client'

import { useEffect, useState } from 'react'
import { format } from 'date-fns'
import { Loader2 } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import type { PaymentMethod, PaymentWithClient } from '@/types/payment'
import { PAYMENT_METHOD_LABELS } from '@/types/payment'

// 手動記録で選択できる支払方法（stripe はオンライン決済用のため除外）
const MANUAL_METHODS: PaymentMethod[] = ['cash', 'bank_transfer', 'card_external']

interface MarkPaidModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  payment: PaymentWithClient | null
  onSaved: () => void
}

export function MarkPaidModal({
  open,
  onOpenChange,
  payment,
  onSaved,
}: MarkPaidModalProps) {
  const [method, setMethod] = useState<string>('')
  const [paidAt, setPaidAt] = useState('')
  const [receiptNumber, setReceiptNumber] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')

  // モーダルを開くたびにフォームをリセット（入金日は今日をデフォルト）
  useEffect(() => {
    if (open) {
      setMethod('')
      setPaidAt(format(new Date(), 'yyyy-MM-dd'))
      setReceiptNumber('')
      setErrorMessage('')
    }
  }, [open])

  const handleSubmit = async () => {
    if (!payment) return
    if (!method) {
      setErrorMessage('支払方法を選択してください')
      return
    }

    setSubmitting(true)
    setErrorMessage('')

    try {
      const res = await fetch(`/api/payments/${payment.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'mark_paid',
          method,
          ...(paidAt ? { paidAt } : {}),
          ...(receiptNumber.trim() ? { receiptNumber: receiptNumber.trim() } : {}),
        }),
      })

      if (!res.ok) {
        throw new Error('支払済みへの更新に失敗しました')
      }

      onOpenChange(false)
      onSaved()
    } catch (error) {
      console.error('支払済み更新エラー:', error)
      alert('支払済みへの更新に失敗しました')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>支払済みにする</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-4">
          {/* 対象の確認 */}
          {payment && (
            <div
              className="rounded-md border px-4 py-3"
              style={{ backgroundColor: '#F8FAFC', borderColor: '#E2E8F0' }}
            >
              <p className="text-[13px] font-medium" style={{ color: '#0F172A' }}>
                {payment.client_name}
                <span className="text-[12px] font-normal ml-2" style={{ color: '#94A3B8' }}>
                  {payment.ticket_name ?? '手動記録'}
                </span>
              </p>
              <p className="text-[15px] font-bold tabular-nums mt-1" style={{ color: '#0F172A' }}>
                ¥{payment.amount_yen.toLocaleString('ja-JP')}
              </p>
            </div>
          )}

          {/* 支払方法 */}
          <div className="space-y-2">
            <Label htmlFor="paid_method">
              支払方法 <span className="text-[#DC2626]">*</span>
            </Label>
            <Select value={method} onValueChange={setMethod} disabled={submitting}>
              <SelectTrigger id="paid_method">
                <SelectValue placeholder="支払方法を選択" />
              </SelectTrigger>
              <SelectContent className="bg-white">
                {MANUAL_METHODS.map((m) => (
                  <SelectItem key={m} value={m}>
                    {PAYMENT_METHOD_LABELS[m]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* 入金日 */}
          <div className="space-y-2">
            <Label htmlFor="paid_at">入金日</Label>
            <Input
              id="paid_at"
              type="date"
              value={paidAt}
              onChange={(e) => setPaidAt(e.target.value)}
              disabled={submitting}
            />
          </div>

          {/* 領収書番号 */}
          <div className="space-y-2">
            <Label htmlFor="receipt_number">領収書番号（任意）</Label>
            <Input
              id="receipt_number"
              value={receiptNumber}
              onChange={(e) => setReceiptNumber(e.target.value)}
              placeholder="例: R-2026-0001"
              disabled={submitting}
            />
          </div>

          {errorMessage && (
            <p className="text-sm text-[#DC2626]">{errorMessage}</p>
          )}
        </div>

        <DialogFooter>
          <Button
            type="button"
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={submitting}
          >
            キャンセル
          </Button>
          <Button
            type="button"
            onClick={handleSubmit}
            disabled={submitting}
            className="bg-[#14B8A6] hover:bg-[#0D9488] text-white"
          >
            {submitting && <Loader2 size={14} className="mr-1.5 animate-spin" />}
            {submitting ? '更新中...' : '支払済みにする'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
