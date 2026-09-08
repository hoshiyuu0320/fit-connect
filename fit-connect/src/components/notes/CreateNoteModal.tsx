'use client'

import { useEffect, useRef, useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { uploadNoteFile } from '@/lib/supabase/uploadNoteFile'
import {
  formatSessionOptionLabel,
  seedNoteLinkSession,
  selectNoteLinkSession,
  EMPTY_SESSION_SELECTION_FIELD,
  type SessionSelectionField,
} from '@/lib/sessions/noteLinkOptions'
import type { ClientSessionOptionsStatus } from '@/hooks/useClientSessionOptions'
import type { ClientSessionOption } from '@/lib/supabase/getClientSessions'

/** 読み込み中プレースホルダの value（実在の session_id と衝突しない値） */
const LOADING_OPTION_VALUE = '__loading'

interface CreateNoteModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  clientId: string
  trainerId: string
  sessions: ClientSessionOption[]  // 「対象セッション」の選択肢（新しい順）
  // 選択肢の取得状態。読み込み中・失敗を黙って「紐づけない」に見せないために使う
  sessionsStatus?: ClientSessionOptionsStatus
  // 開いたときに選択済みにするセッション（カルテタブ: 直近の完了セッション / セッション詳細: そのセッション）
  initialSessionId?: string | null
  // 開いたときに本文へ流し込む初期値（ワークアウト実施画面: サマリーのトレーナーノート）。
  // 本文が空のときだけ反映する（書きかけがあれば上書きしない）
  initialContent?: string
  onCreated: () => void
}

export function CreateNoteModal({
  open,
  onOpenChange,
  clientId,
  trainerId,
  sessions,
  sessionsStatus = 'ready',
  initialSessionId,
  initialContent,
  onCreated,
}: CreateNoteModalProps) {
  const [title, setTitle] = useState('')
  const [link, setLink] = useState<SessionSelectionField>(EMPTY_SESSION_SELECTION_FIELD)
  const [content, setContent] = useState('')
  const [isShared, setIsShared] = useState(false)
  const [files, setFiles] = useState<File[]>([])
  const [submitting, setSubmitting] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)
  // 反映済みの initialSessionId（null は未反映）。閉じたらクリアして次に開いたとき再度反映する
  const [seededKey, setSeededKey] = useState<string | null>(null)
  // initialContent を反映済みか。閉じたら戻して次に開いたとき再度反映する
  const [contentSeeded, setContentSeeded] = useState(false)

  // 開くたびに初期選択を反映する（別のセッションから開き直したとき前回の選択が残らないように）。
  // ただしトレーナーが既に対象セッションを選び直していれば seedNoteLinkSession 側で何もしない
  // （モーダルはアンマウントされないため、キャンセル→開き直しで明示的な選択が巻き戻らないように）
  useEffect(() => {
    if (!open) {
      setSeededKey(null)
      return
    }

    const key = initialSessionId ?? ''
    if (seededKey === key) return

    // 指定されたセッションが選択肢に見当たらないうちは保留する
    // （sessions は非同期に届くため、揃うまで選択肢に無く反映できない）
    if (key && !sessions.some((session) => session.id === key)) return

    setSeededKey(key)
    setLink((prev) => seedNoteLinkSession(prev, key, sessions))
  }, [open, initialSessionId, sessions, seededKey])

  // 開いたときに本文の初期値を1回だけ反映する。
  // 本文が空のときだけ流し込み、書きかけ（キャンセル→開き直しで残っている本文）は上書きしない
  // （対象セッションの「触っていないときだけシード」と同じ規律）
  useEffect(() => {
    if (!open) {
      setContentSeeded(false)
      return
    }
    if (contentSeeded) return

    setContentSeeded(true)
    if (initialContent) {
      setContent((prev) => (prev.trim() ? prev : initialContent))
    }
  }, [open, initialContent, contentSeeded])

  const handleSessionIdChange = (value: string) => {
    if (value === LOADING_OPTION_VALUE) return
    setLink(selectNoteLinkSession(value))
  }

  const sessionId = link.value

  const sessionsLoading = sessionsStatus === 'loading'
  const sessionsFailed = sessionsStatus === 'error'
  // プレースホルダに差し替えるのは初回取得中だけ
  // （カルテ更新後の再取得では既存の選択肢と選択状態を保つ）
  const showSessionsLoading = sessionsLoading && sessions.length === 0

  // 開くときに指定された対象セッションをまだ反映できていない（取得中・取得失敗）状態。
  // 意図した紐づけが落ちたまま「紐づけなし」で保存されないよう作成を止める。
  // トレーナーが自分で選び直した後なら、その意思を優先するので未反映扱いにしない
  const blockedBySession =
    !!initialSessionId &&
    link.source !== 'manual' &&
    !sessions.some((session) => session.id === initialSessionId)

  const resetForm = () => {
    setTitle('')
    setLink(EMPTY_SESSION_SELECTION_FIELD)
    setSeededKey(null)
    setContentSeeded(false)
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
    if (!title.trim() || blockedBySession) return

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
          clientId,
          title: title.trim(),
          content,
          fileUrls,
          isShared,
          sessionId: sessionId || null,
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

          {/* 対象セッション（任意） */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              対象セッション
            </label>
            <select
              value={showSessionsLoading ? LOADING_OPTION_VALUE : sessionId}
              onChange={(e) => handleSessionIdChange(e.target.value)}
              className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-50 disabled:text-gray-500"
              disabled={submitting || showSessionsLoading}
            >
              {/* 読み込み中は「紐づけない」が選ばれているように見せない */}
              {showSessionsLoading ? (
                <option value={LOADING_OPTION_VALUE}>読み込み中...</option>
              ) : (
                <option value="">紐づけない</option>
              )}
              {sessions.map((session) => (
                <option key={session.id} value={session.id}>
                  {formatSessionOptionLabel(session)}
                </option>
              ))}
            </select>
            {sessionsFailed ? (
              <p className="text-xs text-red-600 mt-1">
                セッション一覧を取得できませんでした。時間をおいて開き直してください。
              </p>
            ) : blockedBySession && sessionsLoading ? (
              <p className="text-xs text-gray-500 mt-1">
                対象セッションを読み込んでいます...
              </p>
            ) : blockedBySession ? (
              <p className="text-xs text-red-600 mt-1">
                対象セッションを反映できませんでした。開き直すか、対象セッションを選び直してください。
              </p>
            ) : null}
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
            disabled={!title.trim() || submitting || blockedBySession}
            className="px-4 py-2 text-sm text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {submitting ? '作成中...' : '作成'}
          </button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
