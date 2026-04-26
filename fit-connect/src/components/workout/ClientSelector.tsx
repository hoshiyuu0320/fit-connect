"use client"

import { useEffect, useState } from 'react'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { getClients } from '@/lib/supabase/getClients'
import type { Client } from '@/types/client'

interface ClientSelectorProps {
  trainerId: string
  selectedClientId: string | null
  onSelect: (clientId: string) => void
  showAllOption?: boolean
  className?: string
}

export function ClientSelector({ trainerId, selectedClientId, onSelect, showAllOption, className }: ClientSelectorProps) {
  const [clients, setClients] = useState<Client[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!trainerId) return
    const fetch = async () => {
      try {
        const data = await getClients(trainerId)
        setClients(data)
      } catch (error) {
        console.error('クライアント取得エラー:', error)
      } finally {
        setLoading(false)
      }
    }
    fetch()
  }, [trainerId])

  if (loading) {
    return (
      <div className={`${className ?? 'w-48'} h-10 bg-gray-100 rounded-md animate-pulse`} />
    )
  }

  return (
    <Select value={selectedClientId ?? '__all__'} onValueChange={onSelect}>
      <SelectTrigger className={`${className ?? 'w-48'} bg-white`}>
        <SelectValue placeholder="クライアントを選択" />
      </SelectTrigger>
      <SelectContent>
        {showAllOption && (
          <SelectItem value="__all__">全員</SelectItem>
        )}
        {clients.map((client) => (
          <SelectItem key={client.client_id} value={client.client_id}>
            {client.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}
