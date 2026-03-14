'use client'

import { useState } from 'react'
import type { TicketTemplate, Client } from '@/types/client'
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

interface CreateSubscriptionModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  templates: TicketTemplate[]
  clients: Client[]
  onCreated: () => void
}

export function CreateSubscriptionModal({
  open,
  onOpenChange,
  templates,
  clients,
  onCreated,
}: CreateSubscriptionModalProps) {
  const [templateId, setTemplateId] = useState('')
  const [clientId, setClientId] = useState('')
  const [startDate, setStartDate] = useState(() => {
    const today = new Date()
    return today.toISOString().split('T')[0]
  })
  const [loading, setLoading] = useState(false)

  const recurringTemplates = templates.filter((t) => t.is_recurring)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!templateId || !clientId || !startDate) {
      alert('全ての項目を入力してください')
      return
    }

    setLoading(true)
    try {
      const res = await fetch('/api/ticket-subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          templateId,
          clientId,
          startDate,
        }),
      })

      if (!res.ok) {
        const error = await res.json()
        throw new Error(error.message || '月契約の作成に失敗しました')
      }

      // 成功
      onOpenChange(false)
      onCreated()

      // リセット
      setTemplateId('')
      setClientId('')
      setStartDate(new Date().toISOString().split('T')[0])
    } catch (error) {
      console.error('月契約作成エラー:', error)
      alert(error instanceof Error ? error.message : '月契約の作成に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>月契約を追加</DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* テンプレート選択 */}
          <div className="space-y-2">
            <Label htmlFor="template">テンプレート</Label>
            <Select value={templateId} onValueChange={setTemplateId}>
              <SelectTrigger id="template">
                <SelectValue placeholder="テンプレートを選択" />
              </SelectTrigger>
              <SelectContent className="bg-white">
                {recurringTemplates.length > 0 ? (
                  recurringTemplates.map((template) => (
                    <SelectItem key={template.id} value={template.id}>
                      {template.template_name} ({template.total_sessions}回/{template.valid_months}ヶ月)
                    </SelectItem>
                  ))
                ) : (
                  <div className="px-2 py-1.5 text-sm text-[#94A3B8]">
                    月契約テンプレートがありません
                  </div>
                )}
              </SelectContent>
            </Select>
          </div>

          {/* 顧客選択 */}
          <div className="space-y-2">
            <Label htmlFor="client">顧客</Label>
            <Select value={clientId} onValueChange={setClientId}>
              <SelectTrigger id="client">
                <SelectValue placeholder="顧客を選択" />
              </SelectTrigger>
              <SelectContent className="bg-white">
                {clients.length > 0 ? (
                  clients.map((client) => (
                    <SelectItem key={client.client_id} value={client.client_id}>
                      {client.name}
                    </SelectItem>
                  ))
                ) : (
                  <div className="px-2 py-1.5 text-sm text-[#94A3B8]">
                    顧客がいません
                  </div>
                )}
              </SelectContent>
            </Select>
          </div>

          {/* 開始日 */}
          <div className="space-y-2">
            <Label htmlFor="startDate">開始日</Label>
            <Input
              id="startDate"
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              required
            />
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={loading}
            >
              キャンセル
            </Button>
            <Button
              type="submit"
              disabled={loading || recurringTemplates.length === 0 || clients.length === 0}
              className="bg-[#14B8A6] hover:bg-[#0D9488] text-white"
            >
              {loading ? '作成中...' : '作成'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
