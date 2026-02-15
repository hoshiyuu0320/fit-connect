'use client'

import { useState, useEffect, useRef } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { uploadNoteFile } from '@/lib/supabase/uploadNoteFile'
import { deleteNoteFile } from '@/lib/supabase/deleteNoteFile'
import type { ClientNote } from '@/types/client'

interface EditNoteModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  note: ClientNote | null
  trainerId: string
  clientId: string
  onUpdated: () => void
}

export function EditNoteModal({
  open,
  onOpenChange,
  note,
  trainerId,
  clientId,
  onUpdated,
}: EditNoteModalProps) {
  const [title, setTitle] = useState('')
  const [sessionNumber, setSessionNumber] = useState<string>('')
  const [content, setContent] = useState('')
  const [isShared, setIsShared] = useState(false)
  const [existingFileUrls, setExistingFileUrls] = useState<string[]>([])
  const [newFiles, setNewFiles] = useState<File[]>([])
  const [removedFileUrls, setRemovedFileUrls] = useState<string[]>([])
  const [submitting, setSubmitting] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (note) {
      setTitle(note.title)
      setSessionNumber(note.session_number?.toString() || '')
      setContent(note.content)
      setIsShared(note.is_shared)
      setExistingFileUrls(note.file_urls || [])
      setNewFiles([])
      setRemovedFileUrls([])
    }
  }, [note])

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      const files = Array.from(e.target.files)
      setNewFiles((prev) => [...prev, ...files])
    }
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
    }
  }

  const removeExistingFile = (url: string) => {
    setExistingFileUrls((prev) => prev.filter((u) => u !== url))
    setRemovedFileUrls((prev) => [...prev, url])
  }

  const removeNewFile = (index: number) => {
    setNewFiles((prev) => prev.filter((_, i) => i !== index))
  }

  const getFileName = (url: string) => {
    // ハッシュフラグメントに元のファイル名がある場合はそちらを使用
    const hashIndex = url.indexOf('#')
    if (hashIndex !== -1) {
      return decodeURIComponent(url.substring(hashIndex + 1))
    }
    // フォールバック: パスから抽出
    const decoded = decodeURIComponent(url.split('/').pop() || '')
    const match = decoded.match(/^\d+_(.+)$/)
    return match ? match[1] : decoded
  }

  const isPdf = (url: string) => {
    return url.toLowerCase().endsWith('.pdf')
  }

  const handleSubmit = async () => {
    if (!note || !title.trim()) return

    setSubmitting(true)
    try {
      // 削除されたファイルをStorageから削除
      if (removedFileUrls.length > 0) {
        await Promise.all(removedFileUrls.map((url) => deleteNoteFile(url)))
      }

      // 新しいファイルをアップロード
      let newFileUrls: string[] = []
      if (newFiles.length > 0) {
        newFileUrls = await Promise.all(
          newFiles.map((file) => uploadNoteFile(file, trainerId, clientId))
        )
      }

      // 最終的なファイルURL一覧
      const fileUrls = [...existingFileUrls, ...newFileUrls]

      // カルテ更新API
      const res = await fetch(`/api/client-notes/${note.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: title.trim(),
          content,
          fileUrls,
          isShared,
          sessionNumber: sessionNumber ? parseInt(sessionNumber, 10) : null,
        }),
      })

      if (!res.ok) {
        throw new Error('カルテの更新に失敗しました')
      }

      onOpenChange(false)
      onUpdated()
    } catch (error) {
      console.error('カルテ更新エラー:', error)
      alert('カルテの更新に失敗しました')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>カルテを編集</DialogTitle>
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
              ファイルを追加
            </button>
            <p className="text-xs text-gray-500 mt-1">
              JPEG, PNG, WebP, PDF（最大10MB）
            </p>

            {/* 既存ファイル一覧 */}
            {existingFileUrls.length > 0 && (
              <div className="mt-2 space-y-2">
                {existingFileUrls.map((url, index) => (
                  <div
                    key={index}
                    className="flex items-center justify-between p-2 bg-gray-50 rounded-md"
                  >
                    <div className="flex items-center space-x-2 min-w-0">
                      {isPdf(url) ? (
                        <span className="text-red-500 text-lg flex-shrink-0">PDF</span>
                      ) : (
                        <img
                          src={url}
                          alt="添付ファイル"
                          className="w-10 h-10 object-cover rounded flex-shrink-0"
                        />
                      )}
                      <span className="text-sm text-gray-700 truncate">
                        {getFileName(url)}
                      </span>
                    </div>
                    <button
                      type="button"
                      onClick={() => removeExistingFile(url)}
                      className="text-gray-400 hover:text-red-500 flex-shrink-0 ml-2"
                      disabled={submitting}
                    >
                      ✕
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* 新規ファイル一覧 */}
            {newFiles.length > 0 && (
              <div className="mt-2 space-y-2">
                {newFiles.map((file, index) => (
                  <div
                    key={`new-${index}`}
                    className="flex items-center justify-between p-2 bg-blue-50 rounded-md"
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
                      <span className="text-xs text-blue-600 flex-shrink-0">新規</span>
                    </div>
                    <button
                      type="button"
                      onClick={() => removeNewFile(index)}
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
              id="editIsShared"
              checked={isShared}
              onChange={(e) => setIsShared(e.target.checked)}
              className="rounded border-gray-300"
              disabled={submitting}
            />
            <label htmlFor="editIsShared" className="text-sm text-gray-700">
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
            {submitting ? '更新中...' : '更新'}
          </button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
