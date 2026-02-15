'use client'

import { useState } from 'react'
import { format } from 'date-fns'
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
          <span className="inline-block px-2 py-1 text-xs font-medium bg-emerald-100 text-emerald-700 rounded">
            有効
          </span>
        )
      case 'paused':
        return (
          <span className="inline-block px-2 py-1 text-xs font-medium bg-amber-100 text-amber-700 rounded">
            一時停止
          </span>
        )
      case 'cancelled':
        return (
          <span className="inline-block px-2 py-1 text-xs font-medium bg-rose-100 text-rose-700 rounded">
            解約済
          </span>
        )
    }
  }

  return (
    <div className="space-y-4">
      {/* ヘッダー */}
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-gray-900">月契約</h2>
        <button
          onClick={() => setCreateOpen(true)}
          className="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
        >
          + 月契約を追加
        </button>
      </div>

      {/* 月契約一覧 */}
      {subscriptions.length > 0 ? (
        <div className="bg-white rounded-lg shadow-sm border overflow-hidden">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    顧客名
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    テンプレート
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    ステータス
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    開始日
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    次回発行日
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    操作
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {subscriptions.map((sub) => (
                  <tr key={sub.id}>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      {sub.client_name}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                      {sub.template ? (
                        <>
                          {sub.template.template_name}
                          <span className="ml-2 text-gray-400">
                            ({sub.template.total_sessions}回/{sub.template.valid_months}ヶ月)
                          </span>
                        </>
                      ) : (
                        <span className="text-gray-400">テンプレート削除済み</span>
                      )}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {getStatusBadge(sub.status)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                      {format(new Date(sub.start_date), 'yyyy/MM/dd')}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                      {format(new Date(sub.next_issue_date), 'yyyy/MM/dd')}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm space-x-2">
                      <button
                        onClick={() => setStatusSub(sub)}
                        className="px-3 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                      >
                        ステータス変更
                      </button>
                      <button
                        onClick={() => handleDelete(sub)}
                        className="px-3 py-1 text-xs font-medium text-red-600 bg-red-50 rounded-md hover:bg-red-100"
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
        <div className="flex items-center justify-center h-48 bg-white rounded-lg shadow-sm border">
          <div className="text-center">
            <p className="text-gray-500 mb-2">月契約はありません</p>
            <button
              onClick={() => setCreateOpen(true)}
              className="text-sm text-blue-600 hover:text-blue-700 font-medium"
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
