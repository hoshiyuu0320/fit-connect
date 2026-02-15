'use client'

import { useState } from 'react'
import { format } from 'date-fns'
import type { ClientNote } from '@/types/client'
import { CreateNoteModal } from './CreateNoteModal'
import { EditNoteModal } from './EditNoteModal'
import { DeleteNoteDialog } from './DeleteNoteDialog'

interface NotesTabProps {
  notes: ClientNote[]
  clientId: string
  trainerId: string
  onRefetch: () => void
}

export function NotesTab({ notes, clientId, trainerId, onRefetch }: NotesTabProps) {
  const [createModalOpen, setCreateModalOpen] = useState(false)
  const [editNote, setEditNote] = useState<ClientNote | null>(null)
  const [deleteNote, setDeleteNote] = useState<ClientNote | null>(null)

  const isPdf = (url: string) => url.toLowerCase().endsWith('.pdf')

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

  return (
    <div className="space-y-4">
      {/* ヘッダー */}
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-gray-900">カルテ</h2>
        <button
          onClick={() => setCreateModalOpen(true)}
          className="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
        >
          + カルテを追加
        </button>
      </div>

      {/* カルテ一覧 */}
      {notes.length > 0 ? (
        <div className="space-y-4">
          {notes.map((note) => (
            <div
              key={note.id}
              className="bg-white rounded-lg shadow-sm border p-5"
            >
              {/* ヘッダー行 */}
              <div className="flex items-start justify-between mb-2">
                <div>
                  <h3 className="text-base font-semibold text-gray-900">
                    {note.session_number != null && (
                      <span className="text-blue-600 mr-2">
                        #{note.session_number}
                      </span>
                    )}
                    {note.title}
                  </h3>
                  <p className="text-xs text-gray-500 mt-1">
                    {format(new Date(note.created_at), 'yyyy/MM/dd HH:mm')}
                    {note.updated_at !== note.created_at && ' (編集済み)'}
                  </p>
                </div>
                <div className="flex items-center space-x-2 flex-shrink-0">
                  <button
                    onClick={() => setEditNote(note)}
                    className="px-3 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                  >
                    編集
                  </button>
                  <button
                    onClick={() => setDeleteNote(note)}
                    className="px-3 py-1 text-xs font-medium text-red-600 bg-red-50 rounded-md hover:bg-red-100"
                  >
                    削除
                  </button>
                </div>
              </div>

              {/* 内容 */}
              {note.content && (
                <p className="text-sm text-gray-700 whitespace-pre-wrap mb-3">
                  {note.content}
                </p>
              )}

              {/* 添付ファイル */}
              {note.file_urls && note.file_urls.length > 0 && (
                <div className="flex flex-wrap gap-2 mb-3">
                  {note.file_urls.map((url, index) => (
                    <a
                      key={index}
                      href={url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center space-x-1 px-2 py-1 bg-gray-100 rounded text-xs text-gray-700 hover:bg-gray-200"
                    >
                      {isPdf(url) ? (
                        <>
                          <span className="text-red-500">PDF</span>
                          <span>{getFileName(url)}</span>
                        </>
                      ) : (
                        <>
                          <img
                            src={url}
                            alt="添付"
                            className="w-6 h-6 object-cover rounded"
                          />
                          <span>{getFileName(url)}</span>
                        </>
                      )}
                    </a>
                  ))}
                </div>
              )}

              {/* 共有ステータス */}
              <div className="flex items-center">
                {note.is_shared ? (
                  <span className="inline-flex items-center text-xs text-emerald-600">
                    <span className="mr-1">&#x2705;</span> 共有中
                    {note.shared_at && (
                      <span className="text-gray-400 ml-1">
                        ({format(new Date(note.shared_at), 'M/d')})
                      </span>
                    )}
                  </span>
                ) : (
                  <span className="inline-flex items-center text-xs text-gray-500">
                    <span className="mr-1">&#x1F512;</span> 非公開
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="flex items-center justify-center h-48 bg-white rounded-lg shadow-sm border">
          <div className="text-center">
            <p className="text-gray-500 mb-2">カルテがありません</p>
            <button
              onClick={() => setCreateModalOpen(true)}
              className="text-sm text-blue-600 hover:text-blue-700 font-medium"
            >
              最初のカルテを作成する
            </button>
          </div>
        </div>
      )}

      {/* モーダル */}
      <CreateNoteModal
        open={createModalOpen}
        onOpenChange={setCreateModalOpen}
        clientId={clientId}
        trainerId={trainerId}
        onCreated={onRefetch}
      />

      <EditNoteModal
        open={!!editNote}
        onOpenChange={(open) => !open && setEditNote(null)}
        note={editNote}
        trainerId={trainerId}
        clientId={clientId}
        onUpdated={onRefetch}
      />

      <DeleteNoteDialog
        open={!!deleteNote}
        onOpenChange={(open) => !open && setDeleteNote(null)}
        note={deleteNote}
        onDeleted={onRefetch}
      />
    </div>
  )
}
