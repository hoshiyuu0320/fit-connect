'use client'

import { useEffect, useState } from 'react'
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
import { getTickets } from '@/lib/supabase/getTickets'
import { Ticket } from '@/types/client'

interface TicketSelectModalProps {
  isOpen: boolean
  clientId: string
  planTitle: string
  assignedDate: string // "YYYY-MM-DD"
  estimatedMinutes: number | null
  defaultSessionTime?: string // "HH:mm" - ドロップ先の時刻
  onConfirm: (ticketId: string | null, sessionTime: string) => void
  onCancel: () => void
}

export default function TicketSelectModal({
  isOpen,
  clientId,
  planTitle,
  assignedDate,
  estimatedMinutes,
  defaultSessionTime,
  onConfirm,
  onCancel,
}: TicketSelectModalProps) {
  const [tickets, setTickets] = useState<Ticket[]>([])
  const [selectedTicketId, setSelectedTicketId] = useState<string | null>(null)
  const [sessionTime, setSessionTime] = useState('10:00')
  const [isLoading, setIsLoading] = useState(false)

  useEffect(() => {
    if (!isOpen || !clientId) return

    const fetchTickets = async () => {
      setIsLoading(true)
      try {
        const data = await getTickets(clientId)
        const validTickets = data.filter(
          (t) =>
            t.remaining_sessions > 0 &&
            new Date(t.valid_until) >= new Date()
        )
        setTickets(validTickets)
      } catch (error) {
        console.error('チケット取得エラー:', error)
      } finally {
        setIsLoading(false)
      }
    }

    fetchTickets()
  }, [isOpen, clientId])

  // モーダルが開くたびに初期化
  useEffect(() => {
    if (isOpen) {
      setSelectedTicketId(null)
      setSessionTime(defaultSessionTime ?? '10:00')
    }
  }, [isOpen, defaultSessionTime])

  const formatDate = (dateStr: string): string => {
    const date = new Date(dateStr + 'T00:00:00')
    return date.toLocaleDateString('ja-JP', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      weekday: 'short',
    })
  }

  const formatValidUntil = (dateStr: string): string => {
    const date = new Date(dateStr)
    const y = date.getFullYear()
    const m = String(date.getMonth() + 1).padStart(2, '0')
    const d = String(date.getDate()).padStart(2, '0')
    return `${y}/${m}/${d}`
  }

  const handleConfirm = () => {
    onConfirm(selectedTicketId, sessionTime)
  }

  return (
    <Dialog open={isOpen} onOpenChange={(open) => { if (!open) onCancel() }}>
      <DialogContent className="sm:max-w-[480px] bg-white">
        <DialogHeader>
          <DialogTitle>セッション設定</DialogTitle>
        </DialogHeader>

        <div className="space-y-5">
          {/* プラン情報（読み取り専用） */}
          <div className="rounded-lg bg-gray-50 border p-4 space-y-2">
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500 w-20 shrink-0">プラン名</span>
              <span className="text-sm font-medium text-gray-900">{planTitle}</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500 w-20 shrink-0">日付</span>
              <span className="text-sm text-gray-900">{formatDate(assignedDate)}</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500 w-20 shrink-0">推定時間</span>
              <span className="text-sm text-gray-900">
                {estimatedMinutes != null ? `${estimatedMinutes} 分` : '未設定'}
              </span>
            </div>
          </div>

          {/* セッション開始時刻 */}
          <div className="space-y-2">
            <Label htmlFor="session-time">セッション開始時刻</Label>
            <Input
              id="session-time"
              type="time"
              value={sessionTime}
              onChange={(e) => setSessionTime(e.target.value)}
              className="w-full"
            />
          </div>

          {/* チケット選択 */}
          <div className="space-y-2">
            <Label>使用チケット</Label>

            {isLoading ? (
              <div className="flex items-center justify-center py-6">
                <div className="animate-spin rounded-full h-6 w-6 border-2 border-blue-600 border-t-transparent" />
              </div>
            ) : tickets.length === 0 ? (
              <p className="text-sm text-gray-500 py-4 text-center">
                利用可能なチケットがありません
              </p>
            ) : (
              <div className="space-y-2 max-h-52 overflow-y-auto pr-1">
                {tickets.map((ticket) => (
                  <div
                    key={ticket.id}
                    onClick={() => setSelectedTicketId(ticket.id)}
                    className={`cursor-pointer rounded-lg border-2 p-3 transition-colors ${
                      selectedTicketId === ticket.id
                        ? 'border-blue-500 bg-blue-50'
                        : 'border-gray-200 bg-white hover:border-gray-300'
                    }`}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="space-y-0.5">
                        <p className="text-sm font-medium text-gray-900">
                          {ticket.ticket_name}
                        </p>
                        <p className="text-xs text-gray-500">{ticket.ticket_type}</p>
                      </div>
                      <div className="text-right shrink-0">
                        <p className="text-sm font-semibold text-blue-600">
                          残り {ticket.remaining_sessions} / {ticket.total_sessions} 回
                        </p>
                        <p className="text-xs text-gray-400">
                          有効期限: {formatValidUntil(ticket.valid_until)}
                        </p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {/* チケットを使用しない */}
            <div
              onClick={() => setSelectedTicketId(null)}
              className={`cursor-pointer rounded-lg border-2 p-3 transition-colors ${
                selectedTicketId === null
                  ? 'border-blue-500 bg-blue-50'
                  : 'border-gray-200 bg-white hover:border-gray-300'
              }`}
            >
              <p className="text-sm text-gray-700">チケットを使用しない</p>
            </div>
          </div>
        </div>

        <DialogFooter className="pt-4">
          <Button type="button" variant="outline" onClick={onCancel}>
            キャンセル
          </Button>
          <Button type="button" onClick={handleConfirm}>
            確定
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
