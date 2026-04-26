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
    <div className="bg-[#F0FDFA] border-l-[3px] border-[#14B8A6] rounded-md p-3 mb-2 flex items-center justify-between gap-3">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-sm font-semibold text-[#14B8A6]">
            {senderName}
          </span>
        </div>
        <p className="text-sm text-[#475569] truncate">
          {content}
        </p>
        {imageUrls.length > 0 && (
          <div className="flex items-center gap-1 mt-1 text-xs text-[#94A3B8]">
            <ImageIcon className="h-3 w-3" />
            <span>画像 {imageUrls.length}枚</span>
          </div>
        )}
      </div>
      <button
        type="button"
        onClick={onCancel}
        className="flex-shrink-0 p-1 text-[#94A3B8] hover:text-[#64748B] hover:bg-[#F0FDFA] rounded-md transition-colors"
        title="返信をキャンセル"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  )
}
