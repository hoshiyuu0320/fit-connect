'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
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

  return (
    <div className="bg-white rounded-lg shadow-sm border p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-4">チケット発行</h2>

      <div className="space-y-4">
        {/* テンプレート選択 */}
        <div className="space-y-2">
          <Label>テンプレート</Label>
          <Select value={selectedTemplateId} onValueChange={setSelectedTemplateId} disabled={oneTimeTemplates.length === 0}>
            <SelectTrigger>
              <SelectValue placeholder={oneTimeTemplates.length === 0 ? 'テンプレートがありません' : 'テンプレートを選択'} />
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
        <div className="space-y-2">
          <Label>顧客</Label>
          <Select value={selectedClientId} onValueChange={setSelectedClientId} disabled={clients.length === 0}>
            <SelectTrigger>
              <SelectValue placeholder={clients.length === 0 ? '顧客がいません' : '顧客を選択'} />
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

        {/* メッセージ */}
        {message && (
          <p
            className={`text-sm ${
              message.includes('エラー') || message.includes('選択')
                ? 'text-rose-600'
                : 'text-emerald-600'
            }`}
          >
            {message}
          </p>
        )}

        {/* 発行ボタン */}
        <div className="flex justify-end">
          <Button onClick={handleIssue} disabled={loading}>
            {loading ? '発行中...' : '発行する'}
          </Button>
        </div>
      </div>
    </div>
  )
}
