'use client'

import { X, Image as ImageIcon } from 'lucide-react'

interface ReplyPreviewProps {
  senderName: string
  content: string
  imageUrls?: string[]
  onCancel: () => void
}

export function ReplyPreview({
  senderName,
  content,
  imageUrls = [],
  onCancel,
}: ReplyPreviewProps) {
  return (
    <div className="bg-gray-100 border-l-4 border-blue-500 rounded p-3 mb-2 flex items-center justify-between gap-3">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-sm font-semibold text-gray-900">
            {senderName}
          </span>
        </div>
        <p className="text-sm text-gray-600 truncate">
          {content}
        </p>
        {imageUrls.length > 0 && (
          <div className="flex items-center gap-1 mt-1 text-xs text-gray-500">
            <ImageIcon className="h-3 w-3" />
            <span>画像 {imageUrls.length}枚</span>
          </div>
        )}
      </div>
      <button
        type="button"
        onClick={onCancel}
        className="flex-shrink-0 p-1 text-gray-400 hover:text-gray-600 hover:bg-gray-200 rounded transition-colors"
        title="返信をキャンセル"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  )
}
