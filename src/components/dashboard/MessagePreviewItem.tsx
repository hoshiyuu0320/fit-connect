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
      className="block border-b border-gray-100 last:border-b-0 hover:bg-gray-50 transition-colors"
    >
      <div className="p-4">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center space-x-3">
            <div className="w-9 h-9 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center text-sm font-bold flex-shrink-0">
              {initial}
            </div>
            <span className="font-semibold text-gray-900">{clientName}さん</span>
          </div>
          <span className="text-xs text-gray-500">{formatRelativeTime(timestamp)}</span>
        </div>
        <p className="text-sm text-gray-600 pl-12">{truncatedMessage}</p>
      </div>
    </Link>
  )
}
