'use client'

import { useRef } from 'react'
import { ReplyQuote } from '@/components/message/ReplyQuote'
import { RecordCard } from '@/components/message/RecordCard'
import { parseRecordMessage } from '@/components/message/recordCardParser'
import type { Message } from '@/types/client'

interface MessageBubbleProps {
  message: Message
  isTrainer: boolean
  clientId: string
  clientName: string
  clientProfileImageUrl: string | null
  onEditStart: (msg: Message) => void
  onReplyStart: (msg: Message) => void
  canEdit: boolean
  isEditing: boolean
  editInput: string
  onEditInputChange: (val: string) => void
  onEditSave: () => void
  onEditCancel: () => void
  editSaving: boolean
  onImageClick: (url: string) => void
}

export function MessageBubble({
  message,
  isTrainer,
  clientId,
  clientName,
  clientProfileImageUrl,
  onEditStart,
  onReplyStart,
  canEdit,
  isEditing,
  editInput,
  onEditInputChange,
  onEditSave,
  onEditCancel,
  editSaving,
  onImageClick,
}: MessageBubbleProps) {
  const editTextareaRef = useRef<HTMLTextAreaElement>(null)

  const recordCardData = !isTrainer ? parseRecordMessage(message.content) : null

  const avatarInitial = clientName.charAt(0).toUpperCase()

  const clientAvatar = (
    <div className="flex-shrink-0">
      {clientProfileImageUrl ? (
        <img
          src={clientProfileImageUrl}
          alt={clientName}
          className="w-8 h-8 rounded-full object-cover"
        />
      ) : (
        <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center text-xs font-bold text-gray-600">
          {avatarInitial}
        </div>
      )}
    </div>
  )

  const timestamp = (
    <span className={`text-xs mt-1 flex items-center gap-1 ${isTrainer ? 'justify-end' : 'justify-start'}`}>
      {isTrainer && message.read_at && (
        <span className="text-emerald-400 text-[10px]">既読</span>
      )}
      <span className="text-gray-400">{message.timestamp}</span>
      {message.is_edited && (
        <span
          className={`${isTrainer ? 'text-emerald-200' : 'text-gray-400'}`}
          title={message.edited_at ? `編集: ${new Date(message.edited_at).toLocaleString()}` : '編集済み'}
        >
          編集済み
        </span>
      )}
    </span>
  )

  if (isEditing) {
    return (
      <div className={`flex ${isTrainer ? 'justify-end' : 'justify-start gap-2'}`}>
        {!isTrainer && clientAvatar}
        <div className="max-w-xs md:max-w-md lg:max-w-lg">
          <textarea
            ref={editTextareaRef}
            value={editInput}
            onChange={(e) => onEditInputChange(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                e.preventDefault()
                onEditSave()
              }
              if (e.key === 'Escape') {
                onEditCancel()
              }
            }}
            className="w-full border-2 border-blue-400 rounded p-3 outline-none focus:ring-2 focus:ring-blue-300 resize-none bg-white text-gray-900"
            rows={2}
            autoFocus
          />
          <div className="flex items-center gap-2 mt-1">
            <button
              type="button"
              onClick={onEditCancel}
              className="px-3 py-1 text-sm text-gray-600 rounded hover:bg-gray-100"
            >
              キャンセル
            </button>
            <button
              type="button"
              onClick={onEditSave}
              disabled={editSaving || !editInput.trim()}
              className="px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {editSaving ? '保存中...' : '保存'}
            </button>
            <span className="text-xs text-gray-400">Enter で保存 / Esc でキャンセル</span>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className={`flex ${isTrainer ? 'justify-end' : 'justify-start gap-2'}`}>
      {!isTrainer && clientAvatar}

      <div className={`flex flex-col ${isTrainer ? 'items-end' : 'items-start'} max-w-xs md:max-w-md lg:max-w-lg`}>
        <div className="group relative flex items-end gap-1">
          {/* Edit/Reply buttons for trainer bubble - shown on left */}
          {isTrainer && (
            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                type="button"
                onClick={() => onReplyStart(message)}
                className="p-1.5 rounded-full hover:bg-gray-200 transition-colors"
                title="返信"
              >
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-500">
                  <polyline points="9 14 4 9 9 4"></polyline>
                  <path d="M20 20v-7a4 4 0 0 0-4-4H4"></path>
                </svg>
              </button>
              {canEdit && (
                <button
                  type="button"
                  onClick={() => onEditStart(message)}
                  className="p-1.5 rounded-full hover:bg-gray-200 transition-colors"
                  title="メッセージを編集"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-500">
                    <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                    <path d="m15 5 4 4" />
                  </svg>
                </button>
              )}
            </div>
          )}

          {/* Record card or normal message bubble */}
          {recordCardData ? (
            <RecordCard data={recordCardData} clientId={clientId} />
          ) : (
            <div
              className={`px-4 py-2.5 rounded-2xl ${
                isTrainer
                  ? 'bg-emerald-500 text-white rounded-tr-sm'
                  : 'bg-white border border-gray-200 text-gray-900 rounded-tl-sm'
              }`}
            >
              {/* Reply quote */}
              {message.reply_to_message && (
                <ReplyQuote
                  senderName={message.reply_to_message.sender}
                  content={message.reply_to_message.content}
                  isTrainerMessage={isTrainer}
                  inTrainerBubble={isTrainer}
                />
              )}

              {/* Message text */}
              {message.content && (
                <p className="whitespace-pre-wrap break-words text-sm">{message.content}</p>
              )}

              {/* Images */}
              {message.image_urls && message.image_urls.length > 0 && (
                <div className="flex flex-wrap gap-2 mt-2">
                  {message.image_urls.map((url, imgIndex) => (
                    <button
                      key={imgIndex}
                      type="button"
                      onClick={() => onImageClick(url)}
                      className="block"
                    >
                      <img
                        src={url}
                        alt={`添付画像 ${imgIndex + 1}`}
                        className="w-24 h-24 object-cover rounded-lg cursor-pointer hover:opacity-80 transition-opacity"
                      />
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Edit/Reply buttons for client bubble - shown on right */}
          {!isTrainer && (
            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                type="button"
                onClick={() => onReplyStart(message)}
                className="p-1.5 rounded-full hover:bg-gray-200 transition-colors"
                title="返信"
              >
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-500">
                  <polyline points="9 14 4 9 9 4"></polyline>
                  <path d="M20 20v-7a4 4 0 0 0-4-4H4"></path>
                </svg>
              </button>
            </div>
          )}
        </div>

        {timestamp}
      </div>
    </div>
  )
}
