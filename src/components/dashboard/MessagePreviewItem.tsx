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

  return (
    <Link
      href={`/message?clientId=${clientId}`}
      className="block border-b border-gray-100 last:border-b-0 hover:bg-gray-50 transition-colors"
    >
      <div className="p-4">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center space-x-2">
            <span className="text-lg">👤</span>
            <span className="font-semibold text-gray-900">{clientName}さん</span>
          </div>
          <span className="text-xs text-gray-500">{formatRelativeTime(timestamp)}</span>
        </div>
        <p className="text-sm text-gray-700 pl-7">{truncatedMessage}</p>
      </div>
    </Link>
  )
}
