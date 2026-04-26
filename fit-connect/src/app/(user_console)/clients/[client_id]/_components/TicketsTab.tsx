'use client'

import { useState, useMemo } from 'react'
import { format } from 'date-fns'
import type { Ticket } from '@/types/client'
import { TICKET_TYPE_OPTIONS } from '@/types/client'

interface TicketsTabProps {
  tickets: Ticket[]
}

function TicketCard({ ticket }: { ticket: Ticket }) {
  const now = new Date()
  const expired = new Date(ticket.valid_until) < now
  const usedUp = ticket.remaining_sessions === 0
  const progressPercentage = ticket.total_sessions === 0
    ? 0
    : (ticket.remaining_sessions / ticket.total_sessions) * 100

  const daysUntilExpiry = (new Date(ticket.valid_until).getTime() - now.getTime()) / (1000 * 60 * 60 * 24)
  const expiringSoon = !expired && daysUntilExpiry <= 30

  return (
    <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
      <div className="flex items-start justify-between mb-3">
        <div>
          <div className="flex items-center gap-2 flex-wrap">
            <h4 className="font-semibold text-sm text-[#0F172A]">{ticket.ticket_name}</h4>
            {expired && (
              <span className="inline-flex items-center px-1.5 py-0.5 text-[10px] font-medium text-[#DC2626] bg-[#FEF2F2] border border-[#FECACA] rounded-md">
                期限切れ
              </span>
            )}
            {usedUp && !expired && (
              <span className="inline-flex items-center px-1.5 py-0.5 text-[10px] font-medium text-[#64748B] bg-[#F8FAFC] border border-[#E2E8F0] rounded-md">
                使い切り
              </span>
            )}
            {expiringSoon && !expired && (
              <span className="inline-flex items-center px-1.5 py-0.5 text-[10px] font-medium text-[#F59E0B] bg-[#FFFBEB] border border-[#FDE68A] rounded-md">
                期限切れ間近
              </span>
            )}
          </div>
          <p className="text-xs text-[#94A3B8] mt-0.5">
            {TICKET_TYPE_OPTIONS[ticket.ticket_type as keyof typeof TICKET_TYPE_OPTIONS] || ticket.ticket_type}
          </p>
        </div>
        <p className="text-2xl font-bold text-[#0F172A]">
          {ticket.remaining_sessions}
          <span className="text-xs text-[#94A3B8] ml-1">/ {ticket.total_sessions}回</span>
        </p>
      </div>

      {/* プログレスバー */}
      <div className="w-full bg-[#F1F5F9] rounded h-2 mb-2">
        <div
          className="bg-[#14B8A6] h-2 rounded transition-all"
          style={{ width: `${progressPercentage}%` }}
        />
      </div>

      <p className="text-xs text-[#94A3B8]">
        有効期限: {format(new Date(ticket.valid_from), 'yyyy/MM/dd')} ~ {format(new Date(ticket.valid_until), 'yyyy/MM/dd')}
      </p>
    </div>
  )
}

export function TicketsTab({ tickets }: TicketsTabProps) {
  const [showExpired, setShowExpired] = useState(false)

  // ダッシュボード型サマリー
  const stats = useMemo(() => {
    const now = new Date()
    const activeTickets = tickets.filter(
      (t) => new Date(t.valid_until) >= now && t.remaining_sessions > 0
    )
    const totalRemaining = activeTickets.reduce((sum, t) => sum + t.remaining_sessions, 0)
    const expiringSoon = activeTickets.filter((t) => {
      const daysUntilExpiry = (new Date(t.valid_until).getTime() - now.getTime()) / (1000 * 60 * 60 * 24)
      return daysUntilExpiry <= 30
    }).length
    return {
      activeCount: activeTickets.length,
      totalRemaining,
      expiringSoon,
    }
  }, [tickets])

  // アクティブ/期限切れセクション分離
  const { activeTickets, expiredTickets } = useMemo(() => {
    const now = new Date()
    const active: Ticket[] = []
    const expired: Ticket[] = []
    for (const t of tickets) {
      if (new Date(t.valid_until) < now || t.remaining_sessions === 0) {
        expired.push(t)
      } else {
        active.push(t)
      }
    }
    return { activeTickets: active, expiredTickets: expired }
  }, [tickets])

  return (
    <div className="space-y-4">
      {/* ヘッダー */}
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-[#0F172A]">チケット</h2>
        <a href="/tickets" className="text-sm text-[#14B8A6] hover:text-[#0D9488] font-medium">
          チケット管理 →
        </a>
      </div>

      {tickets.length > 0 ? (
        <>
          {/* サマリーバー */}
          <div className="grid grid-cols-3 gap-3">
            <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
              <p className="text-lg font-bold text-[#0F172A]">{stats.activeCount}</p>
              <p className="text-[11px] text-[#94A3B8]">有効チケット</p>
            </div>
            <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
              <p className="text-lg font-bold text-[#0F172A]">
                {stats.totalRemaining}
                <span className="text-xs text-[#94A3B8] ml-0.5">回</span>
              </p>
              <p className="text-[11px] text-[#94A3B8]">総残回数</p>
            </div>
            <div className="bg-white border border-[#E2E8F0] rounded-md p-3 text-center">
              <p className={`text-lg font-bold ${stats.expiringSoon > 0 ? 'text-[#F59E0B]' : 'text-[#0F172A]'}`}>
                {stats.expiringSoon}
              </p>
              <p className="text-[11px] text-[#94A3B8]">期限切れ間近</p>
            </div>
          </div>

          {/* 有効なチケット */}
          {activeTickets.length > 0 && (
            <div className="mb-6">
              <h3 className="text-sm font-semibold text-[#0F172A] mb-3">有効なチケット</h3>
              <div className="space-y-3">
                {activeTickets.map((ticket) => (
                  <TicketCard key={ticket.id} ticket={ticket} />
                ))}
              </div>
            </div>
          )}

          {/* 期限切れ・使い切り（折りたたみ） */}
          {expiredTickets.length > 0 && (
            <div>
              <button
                onClick={() => setShowExpired(!showExpired)}
                className="flex items-center gap-2 text-sm text-[#94A3B8] hover:text-[#64748B] mb-3 transition-colors"
              >
                <span>{showExpired ? '▼' : '▶'}</span>
                <span>期限切れ・使い切り ({expiredTickets.length})</span>
              </button>
              {showExpired && (
                <div className="space-y-3 opacity-60">
                  {expiredTickets.map((ticket) => (
                    <TicketCard key={ticket.id} ticket={ticket} />
                  ))}
                </div>
              )}
            </div>
          )}
        </>
      ) : (
        <div className="flex items-center justify-center h-48 bg-white border border-[#E2E8F0] rounded-md">
          <div className="text-center">
            <p className="text-[#94A3B8] mb-2">チケットがありません</p>
            <a href="/tickets" className="text-sm text-[#14B8A6] hover:text-[#0D9488] font-medium">
              チケット管理ページで発行する →
            </a>
          </div>
        </div>
      )}
    </div>
  )
}
