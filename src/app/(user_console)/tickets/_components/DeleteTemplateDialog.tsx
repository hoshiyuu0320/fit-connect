'use client'

import { useState } from 'react'
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogCancel,
} from '@/components/ui/alert-dialog'
import type { TicketTemplate } from '@/types/client'

interface DeleteTemplateDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  template: TicketTemplate | null
  onDeleted: () => void
}

export function DeleteTemplateDialog({
  open,
  onOpenChange,
  template,
  onDeleted,
}: DeleteTemplateDialogProps) {
  const [deleting, setDeleting] = useState(false)

  const handleDelete = async () => {
    if (!template) return

    setDeleting(true)
    try {
      const res = await fetch(`/api/ticket-templates/${template.id}`, {
        method: 'DELETE',
      })

      if (!res.ok) {
        throw new Error('テンプレートの削除に失敗しました')
      }

      onOpenChange(false)
      onDeleted()
    } catch (error) {
      console.error('テンプレート削除エラー:', error)
      alert('テンプレートの削除に失敗しました')
    } finally {
      setDeleting(false)
    }
  }

  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>テンプレートを削除しますか？</AlertDialogTitle>
          <AlertDialogDescription>
            「{template?.template_name}」を削除します。このテンプレートに紐づく月契約も削除されます。この操作は取り消せません。
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={deleting}>キャンセル</AlertDialogCancel>
          <button
            onClick={handleDelete}
            disabled={deleting}
            className="inline-flex items-center justify-center rounded-md text-sm font-medium px-4 py-2 bg-red-600 text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {deleting ? '削除中...' : '削除'}
          </button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
