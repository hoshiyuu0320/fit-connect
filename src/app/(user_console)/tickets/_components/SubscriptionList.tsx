'use client'

import { useState } from 'react'
import { format } from 'date-fns'
import { Pencil } from 'lucide-react'
import type { TicketSubscription, TicketTemplate, Client } from '@/types/client'
import { CreateSubscriptionModal } from './CreateSubscriptionModal'
import { SubscriptionStatusDialog } from './SubscriptionStatusDialog'

interface SubscriptionListProps {
  subscriptions: TicketSubscription[]
  templates: TicketTemplate[]
  clients: Client[]
  onRefetch: () => void
}

export function SubscriptionList({ subscriptions, templates, clients, onRefetch }: SubscriptionListProps) {
  const [createOpen, setCreateOpen] = useState(false)
  const [statusSub, setStatusSub] = useState<TicketSubscription | null>(null)

  const handleDelete = async (sub: TicketSubscription) => {
    if (!confirm(`${sub.client_name}の月契約を削除しますか？`)) return

    try {
      const res = await fetch(`/api/ticket-subscriptions/${sub.id}`, {
        method: 'DELETE',
      })
      if (!res.ok) throw new Error('削除に失敗しました')
      onRefetch()
    } catch (error) {
      console.error('削除エラー:', error)
      alert('削除に失敗しました')
    }
  }

  const getStatusBadge = (status: TicketSubscription['status']) => {
    switch (status) {
      case 'active':
        return (
          <span className="inline-flex items-center gap-1.5 px-2 py-1 text-[11px] font-medium bg-[#F0FDF4] text-[#16A34A] border border-[#BBF7D0] rounded-md">
            <span className="w-1.5 h-1.5 rounded-full bg-[#16A34A] flex-shrink-0" />
            有効
          </span>
        )
      case 'paused':
        return (
          <span className="inline-flex items-center gap-1.5 px-2 py-1 text-[11px] font-medium bg-[#FFFBEB] text-[#B45309] border border-[#FDE68A] rounded-md">
            <span className="w-1.5 h-1.5 rounded-full bg-[#B45309] flex-shrink-0" />
            一時停止
          </span>
        )
      case 'cancelled':
        return (
          <span className="inline-flex items-center gap-1.5 px-2 py-1 text-[11px] font-medium bg-[#F8FAFC] text-[#94A3B8] border border-[#E2E8F0] rounded-md">
            <span className="w-1.5 h-1.5 rounded-full bg-[#94A3B8] flex-shrink-0" />
            解約済
          </span>
        )
    }
  }

  return (
    <div className="space-y-4">
      {/* ヘッダー */}
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-[#0F172A]">月契約</h2>
        <button
          onClick={() => setCreateOpen(true)}
          className="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-[#14B8A6] rounded-md hover:bg-[#0D9488]"
        >
          + 月契約を追加
        </button>
      </div>

      {/* 月契約一覧 */}
      {subscriptions.length > 0 ? (
        <div className="bg-white rounded-md border border-[#E2E8F0] overflow-hidden">
          <div className="overflow-x-auto">
            <table className="min-w-full">
              <thead className="bg-[#F8FAFC]">
                <tr>
                  <th className="px-6 py-3 text-left text-[11px] font-semibold text-[#94A3B8] border-b border-[#E2E8F0]">
                    顧客名
                  </th>
                  <th className="px-6 py-3 text-left text-[11px] font-semibold text-[#94A3B8] border-b border-[#E2E8F0]">
                    テンプレート
                  </th>
                  <th className="px-6 py-3 text-left text-[11px] font-semibold text-[#94A3B8] border-b border-[#E2E8F0]">
                    ステータス
                  </th>
                  <th className="px-6 py-3 text-left text-[11px] font-semibold text-[#94A3B8] border-b border-[#E2E8F0]">
                    開始日
                  </th>
                  <th className="px-6 py-3 text-left text-[11px] font-semibold text-[#94A3B8] border-b border-[#E2E8F0]">
                    次回発行日
                  </th>
                  <th className="px-6 py-3 text-right text-[11px] font-semibold text-[#94A3B8] border-b border-[#E2E8F0]">
                    操作
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white">
                {subscriptions.map((sub) => (
                  <tr key={sub.id} className="border-b border-[#E2E8F0] hover:bg-[#FAFBFC]">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        {(() => {
                          const clientImage = clients.find(c => c.client_id === sub.client_id)?.profile_image_url
                          return clientImage ? (
                            <img
                              src={clientImage}
                              alt={sub.client_name ?? ''}
                              className="w-7 h-7 rounded-full object-cover flex-shrink-0"
                            />
                          ) : (
                            <div
                              className={`w-7 h-7 rounded-full flex items-center justify-center text-[11px] font-semibold flex-shrink-0 border ${
                                sub.status === 'cancelled'
                                  ? 'bg-[#F8FAFC] border-[#E2E8F0] text-[#94A3B8]'
                                  : 'bg-[#F0FDFA] border-[#CCFBF1] text-[#14B8A6]'
                              }`}
                            >
                              {(sub.client_name ?? '?').charAt(0)}
                            </div>
                          )
                        })()}
                        <span className="text-[13px] font-medium text-[#0F172A]">{sub.client_name ?? '—'}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {sub.template ? (
                        <div>
                          <p className="text-[13px] text-[#0F172A]">{sub.template.template_name}</p>
                          <p className="text-[11px] text-[#94A3B8]">
                            {sub.template.total_sessions}回/{sub.template.valid_months}ヶ月
                          </p>
                        </div>
                      ) : (
                        <span className="text-[13px] text-[#94A3B8]">テンプレート削除済み</span>
                      )}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {getStatusBadge(sub.status)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-[13px] text-[#0F172A]">
                      {format(new Date(sub.start_date), 'yyyy/MM/dd')}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-[13px] text-[#0F172A]">
                      {format(new Date(sub.next_issue_date), 'yyyy/MM/dd')}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right space-x-1">
                      <button
                        onClick={() => setStatusSub(sub)}
                        className="px-2 py-1 text-[12px] font-medium text-[#475569] hover:text-[#0F172A] hover:bg-[#F8FAFC] rounded-md"
                      >
                        ステータス変更
                      </button>
                      <button
                        onClick={() => handleDelete(sub)}
                        className="px-2 py-1 text-[12px] font-medium text-[#DC2626] hover:text-[#B91C1C] hover:bg-[#FEF2F2] rounded-md"
                      >
                        削除
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        <div className="flex items-center justify-center h-48 bg-white rounded-md border border-dashed border-[#E2E8F0]">
          <div className="text-center">
            <div className="w-12 h-12 rounded-full bg-[#F0FDFA] border border-[#CCFBF1] flex items-center justify-center mx-auto mb-3">
              <Pencil className="w-5 h-5 text-[#14B8A6]" />
            </div>
            <p className="text-[13px] text-[#475569] mb-2">月契約はありません</p>
            <button
              onClick={() => setCreateOpen(true)}
              className="text-sm text-[#14B8A6] hover:text-[#0D9488] font-medium"
            >
              月契約を追加する
            </button>
          </div>
        </div>
      )}

      {/* モーダル */}
      <CreateSubscriptionModal
        open={createOpen}
        onOpenChange={setCreateOpen}
        templates={templates}
        clients={clients}
        onCreated={onRefetch}
      />

      <SubscriptionStatusDialog
        open={!!statusSub}
        onOpenChange={(open) => !open && setStatusSub(null)}
        subscription={statusSub}
        onUpdated={onRefetch}
      />
    </div>
  )
}
