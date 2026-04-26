import React from 'react'
import Link from 'next/link'
import { formatRelativeTime } from '@/utils/formatRelativeTime'

type MessagePreviewItemProps = {
  clientId: string
  clientName: string
  message: string
  timestamp: string
}

export function MessagePreviewItem({
  clientId,
  clientName,
  message,
  timestamp,
}: MessagePreviewItemProps) {
  // メッセージを50文字で切り詰め
  const truncatedMessage = message.length > 50 ? `${message.slice(0, 50)}...` : message

  // イニシャルアバター用の先頭1文字
  const initial = clientName.charAt(0)

  return (
    <Link
      href={`/message?clientId=${clientId}`}
      className="block border-b border-[#F8FAFC] last:border-b-0 hover:bg-[#F8FAFC] transition-colors"
    >
      <div className="p-4">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center space-x-3">
            <div className="w-9 h-9 rounded-full bg-[#F8FAFC] text-[#475569] flex items-center justify-center text-sm font-bold flex-shrink-0">
              {initial}
            </div>
            <span className="font-semibold text-[#0F172A]">{clientName}さん</span>
          </div>
          <span className="text-xs text-[#94A3B8]">{formatRelativeTime(timestamp)}</span>
        </div>
        <p className="text-sm text-[#94A3B8] pl-12">{truncatedMessage}</p>
      </div>
    </Link>
  )
}
