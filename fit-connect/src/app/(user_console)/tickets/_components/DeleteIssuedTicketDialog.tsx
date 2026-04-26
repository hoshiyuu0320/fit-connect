'use client'

import { useState } from 'react'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import type { TicketWithClient } from '@/types/client'

interface DeleteIssuedTicketDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  ticket: TicketWithClient | null
  onDeleted: () => void
}

export function DeleteIssuedTicketDialog({
  open,
  onOpenChange,
  ticket,
  onDeleted,
}: DeleteIssuedTicketDialogProps) {
  const [loading, setLoading] = useState(false)

  const handleDelete = async () => {
    if (!ticket) return

    setLoading(true)

    try {
      const response = await fetch(`/api/tickets/${ticket.id}`, {
        method: 'DELETE',
      })

      if (!response.ok) {
        throw new Error('チケット削除に失敗しました')
      }

      onDeleted()
    } catch (error) {
      console.error('チケット削除エラー:', error)
      alert('削除に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>チケットを削除しますか？</AlertDialogTitle>
          <AlertDialogDescription>
            {ticket?.client_name}の「{ticket?.ticket_name}」を削除します。
            この操作は取り消せません。
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={loading}>キャンセル</AlertDialogCancel>
          <AlertDialogAction
            onClick={handleDelete}
            disabled={loading}
            className="bg-[#DC2626] hover:bg-[#B91C1C] text-white rounded-md"
          >
            {loading ? '削除中...' : '削除'}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
