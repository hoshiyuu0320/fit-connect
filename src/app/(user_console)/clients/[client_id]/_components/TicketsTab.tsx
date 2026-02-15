import { format } from 'date-fns'
import type { Ticket } from '@/types/client'
import { TICKET_TYPE_OPTIONS } from '@/types/client'

interface TicketsTabProps {
  tickets: Ticket[]
}

export function TicketsTab({ tickets }: TicketsTabProps) {
  const isExpired = (validUntil: string) => {
    return new Date(validUntil) < new Date()
  }

  const isUsedUp = (remaining: number) => {
    return remaining === 0
  }

  const getProgressPercentage = (remaining: number, total: number) => {
    if (total === 0) return 0
    return (remaining / total) * 100
  }

  return (
    <div className="space-y-4">
      {/* ヘッダー */}
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-gray-900">チケット</h2>
        <a href="/tickets" className="text-sm text-blue-600 hover:text-blue-700 font-medium">
          チケット管理 →
        </a>
      </div>

      {/* チケット一覧 */}
      {tickets.length > 0 ? (
        <div className="space-y-4">
          {tickets.map((ticket) => {
            const expired = isExpired(ticket.valid_until)
            const usedUp = isUsedUp(ticket.remaining_sessions)
            const progressPercentage = getProgressPercentage(ticket.remaining_sessions, ticket.total_sessions)

            return (
              <div
                key={ticket.id}
                className={`bg-white rounded-lg shadow-sm border p-5 ${expired ? 'opacity-60' : ''}`}
              >
                {/* ヘッダー行 */}
                <div className="mb-3">
                  <div className="flex items-center gap-2">
                    <h3 className="text-base font-semibold text-gray-900">
                      {ticket.ticket_name}
                    </h3>
                    {expired && (
                      <span className="inline-flex items-center px-2 py-0.5 text-xs font-medium text-red-600 bg-red-50 rounded">
                        期限切れ
                      </span>
                    )}
                    {usedUp && !expired && (
                      <span className="inline-flex items-center px-2 py-0.5 text-xs font-medium text-gray-600 bg-gray-100 rounded">
                        使い切り
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-gray-500 mt-1">
                    {TICKET_TYPE_OPTIONS[ticket.ticket_type as keyof typeof TICKET_TYPE_OPTIONS] || ticket.ticket_type}
                  </p>
                </div>

                {/* 進捗バー */}
                <div className="mb-3">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-sm text-gray-700">
                      残り {ticket.remaining_sessions} / {ticket.total_sessions}回
                    </span>
                    <span className="text-sm text-gray-500">
                      {Math.round(progressPercentage)}%
                    </span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div
                      className="bg-blue-600 h-2 rounded-full transition-all"
                      style={{ width: `${progressPercentage}%` }}
                    />
                  </div>
                </div>

                {/* 有効期限 */}
                <div className="text-xs text-gray-500">
                  有効期限: {format(new Date(ticket.valid_from), 'yyyy/MM/dd')} ~ {format(new Date(ticket.valid_until), 'yyyy/MM/dd')}
                </div>
              </div>
            )
          })}
        </div>
      ) : (
        <div className="flex items-center justify-center h-48 bg-white rounded-lg shadow-sm border">
          <div className="text-center">
            <p className="text-gray-500 mb-2">チケットがありません</p>
            <a href="/tickets" className="text-sm text-blue-600 hover:text-blue-700 font-medium">
              チケット管理ページで発行する →
            </a>
          </div>
        </div>
      )}
    </div>
  )
}
