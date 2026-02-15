'use client'

import { useState, useRef } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { uploadNoteFile } from '@/lib/supabase/uploadNoteFile'

interface CreateNoteModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  clientId: string
  trainerId: string
  onCreated: () => void
}

export function CreateNoteModal({
  open,
  onOpenChange,
  clientId,
  trainerId,
  onCreated,
}: CreateNoteModalProps) {
  const [title, setTitle] = useState('')
  const [sessionNumber, setSessionNumber] = useState<string>('')
  const [content, setContent] = useState('')
  const [isShared, setIsShared] = useState(false)
  const [files, setFiles] = useState<File[]>([])
  const [submitting, setSubmitting] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const resetForm = () => {
    setTitle('')
    setSessionNumber('')
    setContent('')
    setIsShared(false)
    setFiles([])
  }

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      const newFiles = Array.from(e.target.files)
      setFiles((prev) => [...prev, ...newFiles])
    }
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
    }
  }

  const removeFile = (index: number) => {
    setFiles((prev) => prev.filter((_, i) => i !== index))
  }

  const handleSubmit = async () => {
    if (!title.trim()) return

    setSubmitting(true)
    try {
      // ファイルアップロード
      let fileUrls: string[] = []
      if (files.length > 0) {
        fileUrls = await Promise.all(
          files.map((file) => uploadNoteFile(file, trainerId, clientId))
        )
      }

      // カルテ作成API
      const res = await fetch('/api/client-notes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          trainerId,
          clientId,
          title: title.trim(),
          content,
          fileUrls,
          isShared,
          sessionNumber: sessionNumber ? parseInt(sessionNumber, 10) : null,
        }),
      })

      if (!res.ok) {
        throw new Error('カルテの作成に失敗しました')
      }

      resetForm()
      onOpenChange(false)
      onCreated()
    } catch (error) {
      console.error('カルテ作成エラー:', error)
      alert('カルテの作成に失敗しました')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>カルテを追加</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-4">
          {/* タイトル */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              タイトル <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="例: セッション#12 記録"
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              disabled={submitting}
            />
          </div>

          {/* セッション番号 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              セッション番号
            </label>
            <input
              type="number"
              value={sessionNumber}
              onChange={(e) => setSessionNumber(e.target.value)}
              placeholder="例: 12"
              min="1"
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              disabled={submitting}
            />
          </div>

          {/* 内容 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              内容
            </label>
            <textarea
              value={content}
              onChange={(e) => setContent(e.target.value)}
              placeholder="セッションの内容、弱点分析、改善点などを記入..."
              rows={6}
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
              disabled={submitting}
            />
          </div>

          {/* ファイル添付 */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              ファイル添付
            </label>
            <input
              ref={fileInputRef}
              type="file"
              accept=".jpg,.jpeg,.png,.webp,.pdf"
              multiple
              onChange={handleFileChange}
              className="hidden"
              disabled={submitting}
            />
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              className="inline-flex items-center px-3 py-2 border border-gray-300 rounded-md text-sm text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50"
              disabled={submitting}
            >
              ファイルを選択
            </button>
            <p className="text-xs text-gray-500 mt-1">
              JPEG, PNG, WebP, PDF（最大10MB）
            </p>

            {/* 選択済みファイル一覧 */}
            {files.length > 0 && (
              <div className="mt-2 space-y-2">
                {files.map((file, index) => (
                  <div
                    key={index}
                    className="flex items-center justify-between p-2 bg-gray-50 rounded-md"
                  >
                    <div className="flex items-center space-x-2 min-w-0">
                      {file.type === 'application/pdf' ? (
                        <span className="text-red-500 text-lg flex-shrink-0">PDF</span>
                      ) : (
                        <img
                          src={URL.createObjectURL(file)}
                          alt={file.name}
                          className="w-10 h-10 object-cover rounded flex-shrink-0"
                        />
                      )}
                      <span className="text-sm text-gray-700 truncate">
                        {file.name}
                      </span>
                    </div>
                    <button
                      type="button"
                      onClick={() => removeFile(index)}
                      className="text-gray-400 hover:text-red-500 flex-shrink-0 ml-2"
                      disabled={submitting}
                    >
                      ✕
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* 共有チェック */}
          <div className="flex items-center space-x-2">
            <input
              type="checkbox"
              id="isShared"
              checked={isShared}
              onChange={(e) => setIsShared(e.target.checked)}
              className="rounded border-gray-300"
              disabled={submitting}
            />
            <label htmlFor="isShared" className="text-sm text-gray-700">
              クライアントに共有する
            </label>
          </div>
        </div>

        <DialogFooter>
          <button
            type="button"
            onClick={() => onOpenChange(false)}
            className="px-4 py-2 text-sm text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
            disabled={submitting}
          >
            キャンセル
          </button>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={!title.trim() || submitting}
            className="px-4 py-2 text-sm text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {submitting ? '作成中...' : '作成'}
          </button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
