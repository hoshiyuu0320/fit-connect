'use client'

import { useState } from 'react'
import Image from 'next/image'
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
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)

  const isPdf = (url: string) => url.toLowerCase().endsWith('.pdf')

  const getFileName = (url: string) => {
    const hashIndex = url.indexOf('#')
    if (hashIndex !== -1) {
      return decodeURIComponent(url.substring(hashIndex + 1))
    }
    const decoded = decodeURIComponent(url.split('/').pop() || '')
    const match = decoded.match(/^\d+_(.+)$/)
    return match ? match[1] : decoded
  }

  return (
    <div className="space-y-4">
      {/* ヘッダー */}
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-[#0F172A]">カルテ</h2>
        <button
          onClick={() => setCreateModalOpen(true)}
          className="bg-[#14B8A6] text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-[#0D9488] transition-colors"
        >
          + カルテを追加
        </button>
      </div>

      {/* カルテ一覧 */}
      {notes.length > 0 ? (
        <div className="space-y-3">
          {notes.map((note) => (
            <div
              key={note.id}
              className="bg-white border border-[#E2E8F0] rounded-md overflow-hidden"
            >
              <div className="flex">
                {/* 左アクセントバー + セッション番号 */}
                <div className="w-10 bg-[#F0FDFA] border-r border-[#CCFBF1] flex flex-col items-center justify-start pt-4 flex-shrink-0">
                  {note.session_number != null && (
                    <>
                      <span className="text-[10px] text-[#94A3B8]">#</span>
                      <span className="text-sm font-bold text-[#14B8A6]">{note.session_number}</span>
                    </>
                  )}
                </div>

                {/* メインコンテンツ */}
                <div className="flex-1 p-4 min-w-0">
                  {/* ヘッダー行 */}
                  <div className="flex items-start justify-between mb-2">
                    <div className="min-w-0 mr-3">
                      <h4 className="font-semibold text-sm text-[#0F172A]">{note.title}</h4>
                      <p className="text-[11px] text-[#94A3B8] mt-0.5">
                        {format(new Date(note.created_at), 'yyyy/MM/dd HH:mm')}
                        {note.updated_at !== note.created_at && (
                          <span className="ml-1">(編集済み)</span>
                        )}
                      </p>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      {/* 共有ステータス */}
                      {note.is_shared ? (
                        <span className="flex items-center gap-1 text-[11px] text-[#16A34A]">
                          <svg
                            width="11"
                            height="11"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            strokeWidth="2"
                            strokeLinecap="round"
                            strokeLinejoin="round"
                          >
                            <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" />
                            <polyline points="16 6 12 2 8 6" />
                            <line x1="12" y1="2" x2="12" y2="15" />
                          </svg>
                          共有中
                        </span>
                      ) : (
                        <span className="flex items-center gap-1 text-[11px] text-[#94A3B8]">
                          <svg
                            width="11"
                            height="11"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            strokeWidth="2"
                            strokeLinecap="round"
                            strokeLinejoin="round"
                          >
                            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                          </svg>
                          非公開
                        </span>
                      )}
                      {/* 編集・削除ボタン */}
                      <button
                        onClick={() => setEditNote(note)}
                        className="text-xs text-[#94A3B8] hover:text-[#14B8A6] transition-colors px-2 py-1"
                      >
                        編集
                      </button>
                      <button
                        onClick={() => setDeleteNote(note)}
                        className="text-xs text-[#94A3B8] hover:text-[#DC2626] transition-colors px-2 py-1"
                      >
                        削除
                      </button>
                    </div>
                  </div>

                  {/* コンテンツ */}
                  {note.content && (
                    <p className="text-sm text-[#0F172A] whitespace-pre-wrap mb-3 leading-relaxed">
                      {note.content}
                    </p>
                  )}

                  {/* 添付ファイルサムネイルグリッド */}
                  {note.file_urls && note.file_urls.length > 0 && (
                    <div className="flex gap-2 flex-wrap">
                      {note.file_urls.map((url, i) => {
                        if (isPdf(url)) {
                          return (
                            <a
                              key={i}
                              href={url}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="flex items-center gap-1 px-2 py-1 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md text-xs text-[#64748B] hover:border-[#14B8A6] transition-colors"
                            >
                              <span>📄</span>
                              <span className="max-w-[120px] truncate">{getFileName(url)}</span>
                            </a>
                          )
                        }
                        return (
                          <button
                            key={i}
                            type="button"
                            onClick={() => setLightboxUrl(url)}
                            className="relative w-14 h-14 rounded-md overflow-hidden border border-[#E2E8F0] hover:border-[#14B8A6] hover:opacity-80 transition-all"
                          >
                            <Image
                              src={url}
                              alt={`添付画像 ${i + 1}`}
                              fill
                              className="object-cover"
                              unoptimized
                            />
                          </button>
                        )
                      })}
                    </div>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="flex items-center justify-center h-48 bg-white border border-[#E2E8F0] rounded-md">
          <div className="text-center">
            <p className="text-sm text-[#94A3B8] mb-2">カルテがありません</p>
            <button
              onClick={() => setCreateModalOpen(true)}
              className="text-sm text-[#14B8A6] hover:text-[#0D9488] font-medium transition-colors"
            >
              最初のカルテを作成する
            </button>
          </div>
        </div>
      )}

      {/* 画像ライトボックス */}
      {lightboxUrl && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70"
          onClick={() => setLightboxUrl(null)}
        >
          <div className="relative max-w-3xl max-h-[80vh] w-full mx-4">
            <img
              src={lightboxUrl}
              alt="添付画像"
              className="w-full h-full object-contain rounded-md"
            />
            <button
              className="absolute top-2 right-2 text-white bg-black/50 rounded-md px-2 py-1 text-xs"
              onClick={() => setLightboxUrl(null)}
            >
              閉じる
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
