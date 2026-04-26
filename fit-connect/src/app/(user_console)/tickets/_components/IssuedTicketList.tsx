'use client'

import { useState } from 'react'
import { format } from 'date-fns'
import { Ticket } from 'lucide-react'
import type { TicketWithClient, Client } from '@/types/client'
import { TICKET_TYPE_OPTIONS } from '@/types/client'
import { EditIssuedTicketModal } from './EditIssuedTicketModal'
import { DeleteIssuedTicketDialog } from './DeleteIssuedTicketDialog'

interface IssuedTicketListProps {
  tickets: TicketWithClient[]
  clients: Client[]
  onRefetch: () => void
}

type TicketStatus = 'expired' | 'nearExpiry' | 'lowRemaining' | 'active'

function getTicketStatus(ticket: TicketWithClient): TicketStatus {
  const now = new Date()
  const validUntil = new Date(ticket.valid_until)
  const expired = validUntil < now || ticket.remaining_sessions === 0
  const daysUntilExpiry = Math.ceil((validUntil.getTime() - now.getTime()) / (1000 * 60 * 60 * 24))
  const lowRemaining = ticket.remaining_sessions <= ticket.total_sessions * 0.25

  if (expired) return 'expired'
  if (daysUntilExpiry <= 30) return 'nearExpiry'
  if (lowRemaining) return 'lowRemaining'
  return 'active'
}

const STATUS_CONFIG = {
  expired: {
    label: '期限切れ',
    bg: '#FEF2F2',
    text: '#DC2626',
    border: '#FECACA',
    dot: '#DC2626',
  },
  nearExpiry: {
    label: '期限切れ間近',
    bg: '#FFFBEB',
    text: '#B45309',
    border: '#FDE68A',
    dot: '#B45309',
  },
  lowRemaining: {
    label: '残りわずか',
    bg: '#FFFBEB',
    text: '#B45309',
    border: '#FDE68A',
    dot: '#B45309',
  },
  active: {
    label: '有効',
    bg: '#F0FDF4',
    text: '#16A34A',
    border: '#BBF7D0',
    dot: '#16A34A',
  },
}


export function IssuedTicketList({ tickets, clients, onRefetch }: IssuedTicketListProps) {
  const [editTicket, setEditTicket] = useState<TicketWithClient | null>(null)
  const [deleteTicket, setDeleteTicket] = useState<TicketWithClient | null>(null)

  if (tickets.length === 0) {
    return (
      <div className="bg-white rounded-md border border-[#E2E8F0] p-6">
        <h2 className="text-[15px] font-semibold text-[#0F172A] mb-4">発行済みチケット</h2>
        <div className="flex flex-col items-center justify-center py-12 border border-dashed border-[#E2E8F0] rounded-md">
          <div className="w-12 h-12 rounded-full bg-[#F0FDFA] border border-[#CCFBF1] flex items-center justify-center mb-3">
            <Ticket size={24} style={{ color: '#14B8A6' }} />
          </div>
          <p className="text-[13px] text-[#94A3B8] mb-1">発行済みチケットはありません</p>
          <p className="text-[12px]" style={{ color: '#14B8A6' }}>
            上のフォームからチケットを発行してください
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="bg-white rounded-md border border-[#E2E8F0]">
      <div className="px-5 py-4 border-b border-[#E2E8F0]">
        <h2 className="text-[15px] font-semibold text-[#0F172A]">発行済みチケット</h2>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-[#F8FAFC] border-b border-[#E2E8F0]">
            <tr>
              <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                顧客名
              </th>
              <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                チケット名
              </th>
              <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                種別
              </th>
              <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                残回数
              </th>
              <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                有効期限
              </th>
              <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                ステータス
              </th>
              <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                操作
              </th>
            </tr>
          </thead>
          <tbody>
            {tickets.map((ticket, index) => {
              const status = getTicketStatus(ticket)
              const isExpired = status === 'expired'
              const progress = (ticket.remaining_sessions / ticket.total_sessions) * 100
              // 残回数バーの色は回数の割合のみで判定（有効期限と独立）
              const sessionsRatio = ticket.total_sessions > 0 ? ticket.remaining_sessions / ticket.total_sessions : 0
              const progressColor = sessionsRatio === 0 ? '#94A3B8' : sessionsRatio <= 0.25 ? '#F59E0B' : '#14B8A6'
              const statusConfig = STATUS_CONFIG[status]
              const isLast = index === tickets.length - 1

              // 有効期限ゲージ計算
              const validFrom = new Date(ticket.valid_from).getTime()
              const validUntil = new Date(ticket.valid_until).getTime()
              const now = Date.now()
              const totalDuration = validUntil - validFrom
              const remainingDuration = Math.max(0, validUntil - now)
              const remainingPercent = totalDuration > 0 ? Math.min(100, (remainingDuration / totalDuration) * 100) : 0
              const daysRemaining = Math.max(0, Math.ceil(remainingDuration / (1000 * 60 * 60 * 24)))
              const expiryBarColor = isExpired ? '#94A3B8' : daysRemaining <= 30 ? '#F59E0B' : '#14B8A6'

              return (
                <tr
                  key={ticket.id}
                  className="hover:bg-[#FAFBFC]"
                >
                  {/* 顧客名（アバター付き） */}
                  <td
                    className="px-4 py-3 text-[13px] text-[#0F172A]"
                    style={{ borderBottom: isLast ? 'none' : '1px solid #E2E8F0', opacity: isExpired ? 0.5 : 1 }}
                  >
                    <div className="flex items-center gap-2">
                      {(() => {
                        const clientImage = clients.find(c => c.client_id === ticket.client_id)?.profile_image_url
                        return clientImage ? (
                          <img
                            src={clientImage}
                            alt={ticket.client_name ?? ''}
                            className="w-7 h-7 rounded-full object-cover flex-shrink-0"
                          />
                        ) : (
                          <div
                            className="w-7 h-7 rounded-full flex items-center justify-center text-[12px] font-semibold flex-shrink-0"
                            style={{
                              backgroundColor: '#F0FDFA',
                              border: '1px solid #CCFBF1',
                              color: '#14B8A6',
                            }}
                          >
                            {ticket.client_name?.charAt(0) ?? '?'}
                          </div>
                        )
                      })()}
                      <span>{ticket.client_name}</span>
                    </div>
                  </td>

                  {/* チケット名 */}
                  <td
                    className="px-4 py-3 text-[13px] text-[#0F172A]"
                    style={{ borderBottom: isLast ? 'none' : '1px solid #E2E8F0', opacity: isExpired ? 0.5 : 1 }}
                  >
                    {ticket.ticket_name}
                  </td>

                  {/* 種別バッジ */}
                  <td
                    className="px-4 py-3"
                    style={{ borderBottom: isLast ? 'none' : '1px solid #E2E8F0', opacity: isExpired ? 0.5 : 1 }}
                  >
                    <span
                      className="rounded-md px-2 py-0.5 text-[11px] font-medium"
                      style={{
                        backgroundColor: '#F0FDFA',
                        color: '#14B8A6',
                        border: '1px solid #CCFBF1',
                      }}
                    >
                      {TICKET_TYPE_OPTIONS[ticket.ticket_type as keyof typeof TICKET_TYPE_OPTIONS] ||
                        ticket.ticket_type}
                    </span>
                  </td>

                  {/* 残回数 + プログレスバー */}
                  <td
                    className="px-4 py-3"
                    style={{ borderBottom: isLast ? 'none' : '1px solid #E2E8F0', opacity: isExpired ? 0.5 : 1 }}
                  >
                    <div className="space-y-1">
                      <div className="text-[13px] text-[#0F172A]">
                        残{ticket.remaining_sessions}/{ticket.total_sessions}回
                      </div>
                      <div className="w-full rounded-full h-[6px]" style={{ backgroundColor: '#F1F5F9' }}>
                        <div
                          className="h-[6px] rounded-full transition-all"
                          style={{ width: `${progress}%`, backgroundColor: progressColor }}
                        />
                      </div>
                    </div>
                  </td>

                  {/* 有効期限 + ゲージ */}
                  <td
                    className="px-4 py-3"
                    style={{ borderBottom: isLast ? 'none' : '1px solid #E2E8F0', opacity: isExpired ? 0.5 : 1 }}
                  >
                    <div className="space-y-1">
                      <div className="text-[13px] text-[#0F172A]">
                        {isExpired ? '期限切れ' : `残${daysRemaining}日`}
                        <span className="text-[11px] text-[#94A3B8] ml-1">
                          (~{format(new Date(ticket.valid_until), 'yyyy/MM/dd')})
                        </span>
                      </div>
                      <div className="w-full rounded-full h-[6px]" style={{ backgroundColor: '#F1F5F9' }}>
                        <div
                          className="h-[6px] rounded-full transition-all"
                          style={{ width: `${remainingPercent}%`, backgroundColor: expiryBarColor }}
                        />
                      </div>
                    </div>
                  </td>

                  {/* ステータスバッジ */}
                  <td
                    className="px-4 py-3"
                    style={{ borderBottom: isLast ? 'none' : '1px solid #E2E8F0', opacity: isExpired ? 0.5 : 1 }}
                  >
                    <span
                      className="inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-[11px] font-medium"
                      style={{
                        backgroundColor: statusConfig.bg,
                        color: statusConfig.text,
                        border: `1px solid ${statusConfig.border}`,
                      }}
                    >
                      <span
                        className="w-1.5 h-1.5 rounded-full flex-shrink-0"
                        style={{ backgroundColor: statusConfig.dot }}
                      />
                      {statusConfig.label}
                    </span>
                  </td>

                  {/* 操作 */}
                  <td
                    className="px-4 py-3"
                    style={{ borderBottom: isLast ? 'none' : '1px solid #E2E8F0' }}
                  >
                    <div className="flex gap-1">
                      <button
                        onClick={() => setEditTicket(ticket)}
                        className="text-[13px] text-[#475569] hover:text-[#0F172A] hover:bg-[#F8FAFC] px-2 py-1 rounded-md transition-colors"
                        style={
                          isExpired
                            ? { opacity: 0.5, pointerEvents: 'none', cursor: 'not-allowed' }
                            : undefined
                        }
                        disabled={isExpired}
                      >
                        編集
                      </button>
                      <button
                        onClick={() => setDeleteTicket(ticket)}
                        className="text-[13px] text-[#DC2626] hover:text-[#B91C1C] hover:bg-[#FEF2F2] px-2 py-1 rounded-md transition-colors"
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
