'use client'

import { useEffect, useState } from 'react'
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
import { Textarea } from '@/components/ui/textarea'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import type { Client } from '@/types/client'

interface AddPaymentModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  clients: Client[]
  onSaved: () => void
}

export function AddPaymentModal({
  open,
  onOpenChange,
  clients,
  onSaved,
}: AddPaymentModalProps) {
  const [clientId, setClientId] = useState('')
  const [amount, setAmount] = useState('')
  const [dueDate, setDueDate] = useState('')
  const [note, setNote] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')

  // モーダルを開くたびにフォームをリセット
  useEffect(() => {
    if (open) {
      setClientId('')
      setAmount('')
      setDueDate('')
      setNote('')
      setErrorMessage('')
    }
  }, [open])

  const handleSubmit = async () => {
    const amountYen = Number(amount)
    if (!clientId) {
      setErrorMessage('顧客を選択してください')
      return
    }
    if (amount === '' || !Number.isInteger(amountYen) || amountYen < 1) {
      setErrorMessage('金額は1円以上の整数で入力してください')
      return
    }

    setSubmitting(true)
    setErrorMessage('')

    try {
      const res = await fetch('/api/payments', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          clientId,
          amountYen,
          ...(dueDate ? { dueDate } : {}),
          ...(note.trim() ? { note: note.trim() } : {}),
        }),
      })

      if (!res.ok) {
        throw new Error('支払記録の作成に失敗しました')
      }

      onOpenChange(false)
      onSaved()
    } catch (error) {
      console.error('支払記録作成エラー:', error)
      alert('支払記録の作成に失敗しました')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>支払記録を追加</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-4">
          {/* 顧客 */}
          <div className="space-y-2">
            <Label htmlFor="payment_client">
              顧客 <span className="text-[#DC2626]">*</span>
            </Label>
            <Select
              value={clientId}
              onValueChange={setClientId}
              disabled={submitting || clients.length === 0}
            >
              <SelectTrigger id="payment_client">
                <SelectValue
                  placeholder={clients.length === 0 ? '顧客がいません' : '顧客を選択'}
                />
              </SelectTrigger>
              <SelectContent className="bg-white">
                {clients.map((client) => (
                  <SelectItem key={client.client_id} value={client.client_id}>
                    {client.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* 金額 */}
          <div className="space-y-2">
            <Label htmlFor="payment_amount">
              金額（円・税込） <span className="text-[#DC2626]">*</span>
            </Label>
            <Input
              id="payment_amount"
              type="number"
              min="1"
              step="1"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="例: 8000"
              disabled={submitting}
            />
          </div>

          {/* 期日 */}
          <div className="space-y-2">
            <Label htmlFor="payment_due_date">期日（任意）</Label>
            <Input
              id="payment_due_date"
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
              disabled={submitting}
            />
          </div>

          {/* メモ */}
          <div className="space-y-2">
            <Label htmlFor="payment_note">メモ（任意）</Label>
            <Textarea
              id="payment_note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="例: 出張セッション代"
              rows={2}
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
            {submitting ? '追加中...' : '追加'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
