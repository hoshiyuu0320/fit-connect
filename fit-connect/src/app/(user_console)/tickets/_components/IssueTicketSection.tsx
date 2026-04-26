'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import type { TicketTemplate, Client } from '@/types/client'

interface IssueTicketSectionProps {
  templates: TicketTemplate[]
  clients: Client[]
  onIssued: () => void
}

export function IssueTicketSection({ templates, clients, onIssued }: IssueTicketSectionProps) {
  const [selectedTemplateId, setSelectedTemplateId] = useState<string>('')
  const [selectedClientId, setSelectedClientId] = useState<string>('')
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState('')

  // 都度テンプレートのみフィルタリング
  const oneTimeTemplates = templates.filter((t) => !t.is_recurring)

  const handleIssue = async () => {
    if (!selectedTemplateId || !selectedClientId) {
      setMessage('テンプレートと顧客を選択してください')
      setTimeout(() => setMessage(''), 3000)
      return
    }

    setLoading(true)
    setMessage('')

    try {
      const response = await fetch('/api/tickets/issue', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          templateId: selectedTemplateId,
          clientId: selectedClientId,
        }),
      })

      if (!response.ok) {
        throw new Error('チケット発行に失敗しました')
      }

      setMessage('チケットを発行しました')
      setSelectedTemplateId('')
      setSelectedClientId('')
      onIssued()

      setTimeout(() => setMessage(''), 3000)
    } catch (error) {
      console.error('チケット発行エラー:', error)
      setMessage('エラーが発生しました')
      setTimeout(() => setMessage(''), 3000)
    } finally {
      setLoading(false)
    }
  }

  const isError = message.includes('エラー') || message.includes('選択')

  return (
    <div className="bg-white rounded-md border border-[#E2E8F0] p-5">
      <p className="text-[13px] font-semibold text-[#0F172A] mb-3">チケット発行</p>

      <div className="flex items-end gap-4">
        {/* テンプレート選択 */}
        <div className="flex-1">
          <p className="text-[12px] font-medium text-[#475569] mb-1">テンプレート</p>
          <Select
            value={selectedTemplateId}
            onValueChange={setSelectedTemplateId}
            disabled={oneTimeTemplates.length === 0}
          >
            <SelectTrigger>
              <SelectValue
                placeholder={
                  oneTimeTemplates.length === 0 ? 'テンプレートがありません' : 'テンプレートを選択'
                }
              />
            </SelectTrigger>
            <SelectContent className="bg-white">
              {oneTimeTemplates.map((template) => (
                <SelectItem key={template.id} value={template.id}>
                  {template.template_name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {/* 顧客選択 */}
        <div className="flex-1">
          <p className="text-[12px] font-medium text-[#475569] mb-1">顧客</p>
          <Select
            value={selectedClientId}
            onValueChange={setSelectedClientId}
            disabled={clients.length === 0}
          >
            <SelectTrigger>
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

        {/* 発行ボタン */}
        <Button
          onClick={handleIssue}
          disabled={loading}
          className="bg-[#14B8A6] hover:bg-[#0D9488] text-white rounded-md px-5 py-2 text-sm font-semibold whitespace-nowrap"
        >
          {loading ? '発行中...' : '発行する'}
        </Button>
      </div>

      {/* メッセージ */}
      {message && (
        <p
          className="text-sm mt-3"
          style={{ color: isError ? '#DC2626' : '#16A34A' }}
        >
          {message}
        </p>
      )}
    </div>
  )
}
