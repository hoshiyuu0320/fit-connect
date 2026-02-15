'use client'

import { useState } from 'react'
import { format } from 'date-fns'
import type { TicketWithClient } from '@/types/client'
import { TICKET_TYPE_OPTIONS } from '@/types/client'
import { EditIssuedTicketModal } from './EditIssuedTicketModal'
import { DeleteIssuedTicketDialog } from './DeleteIssuedTicketDialog'

interface IssuedTicketListProps {
  tickets: TicketWithClient[]
  onRefetch: () => void
}

export function IssuedTicketList({ tickets, onRefetch }: IssuedTicketListProps) {
  const [editTicket, setEditTicket] = useState<TicketWithClient | null>(null)
  const [deleteTicket, setDeleteTicket] = useState<TicketWithClient | null>(null)

  // 期限チェック
  const isExpired = (validUntil: string) => {
    return new Date(validUntil) < new Date()
  }

  if (tickets.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow-sm border p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">発行済みチケット</h2>
        <p className="text-center text-gray-500 py-8">発行済みチケットはありません</p>
      </div>
    )
  }

  return (
    <div className="bg-white rounded-lg shadow-sm border p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-4">発行済みチケット</h2>

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                顧客名
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                チケット名
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                種別
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                残回数
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                有効期限
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                操作
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {tickets.map((ticket) => {
              const expired = isExpired(ticket.valid_until)
              const rowClass = expired ? 'bg-gray-50 text-gray-400' : ''
              const progress = (ticket.remaining_sessions / ticket.total_sessions) * 100

              return (
                <tr key={ticket.id} className={rowClass}>
                  <td className="px-4 py-3 text-sm">{ticket.client_name}</td>
                  <td className="px-4 py-3 text-sm">{ticket.ticket_name}</td>
                  <td className="px-4 py-3 text-sm">
                    {TICKET_TYPE_OPTIONS[ticket.ticket_type as keyof typeof TICKET_TYPE_OPTIONS] ||
                      ticket.ticket_type}
                  </td>
                  <td className="px-4 py-3">
                    <div className="space-y-1">
                      <div className="text-sm">
                        残{ticket.remaining_sessions}/{ticket.total_sessions}回
                      </div>
                      <div className="w-full bg-gray-200 rounded-full h-1.5">
                        <div
                          className="bg-blue-600 h-1.5 rounded-full transition-all"
                          style={{ width: `${progress}%` }}
                        />
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-sm">
                    {format(new Date(ticket.valid_from), 'yyyy/MM/dd')} ~{' '}
                    {format(new Date(ticket.valid_until), 'yyyy/MM/dd')}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex gap-2">
                      <button
                        onClick={() => setEditTicket(ticket)}
                        className="text-sm text-blue-600 hover:text-blue-700 hover:underline"
                        disabled={expired}
                      >
                        編集
                      </button>
                      <button
                        onClick={() => setDeleteTicket(ticket)}
                        className="text-sm text-rose-600 hover:text-rose-700 hover:underline"
                      >
                        削除
                      </button>
                    </div>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {/* 編集モーダル */}
      <EditIssuedTicketModal
        open={!!editTicket}
        onOpenChange={(open) => !open && setEditTicket(null)}
        ticket={editTicket}
        onUpdated={() => {
          setEditTicket(null)
          onRefetch()
        }}
      />

      {/* 削除確認ダイアログ */}
      <DeleteIssuedTicketDialog
        open={!!deleteTicket}
        onOpenChange={(open) => !open && setDeleteTicket(null)}
        ticket={deleteTicket}
        onDeleted={() => {
          setDeleteTicket(null)
          onRefetch()
        }}
      />
    </div>
  )
}
