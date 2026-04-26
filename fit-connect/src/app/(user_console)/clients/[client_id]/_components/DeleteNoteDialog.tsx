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
import type { ClientNote } from '@/types/client'

interface DeleteNoteDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  note: ClientNote | null
  onDeleted: () => void
}

export function DeleteNoteDialog({
  open,
  onOpenChange,
  note,
  onDeleted,
}: DeleteNoteDialogProps) {
  const [deleting, setDeleting] = useState(false)

  const handleDelete = async () => {
    if (!note) return

    setDeleting(true)
    try {
      const res = await fetch(`/api/client-notes/${note.id}`, {
        method: 'DELETE',
      })

      if (!res.ok) {
        throw new Error('カルテの削除に失敗しました')
      }

      onOpenChange(false)
      onDeleted()
    } catch (error) {
      console.error('カルテ削除エラー:', error)
      alert('カルテの削除に失敗しました')
    } finally {
      setDeleting(false)
    }
  }

  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>カルテを削除しますか？</AlertDialogTitle>
          <AlertDialogDescription>
            「{note?.title}」を削除します。添付ファイルも含めて完全に削除され、この操作は取り消せません。
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
