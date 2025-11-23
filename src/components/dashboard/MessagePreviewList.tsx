import React from 'react'
import Link from 'next/link'
import { MessagePreviewItem } from './MessagePreviewItem'
import type { RecentMessage } from '@/lib/supabase/getRecentMessages'

type MessagePreviewListProps = {
  messages: RecentMessage[]
}

export function MessagePreviewList({ messages }: MessagePreviewListProps) {
  if (messages.length === 0) {
    return (
      <div className="bg-white rounded-lg border border-gray-200 p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-bold text-gray-900 flex items-center space-x-2">
            <span>💬</span>
            <span>最近のメッセージ</span>
          </h2>
        </div>
        <p className="text-center text-gray-500 py-8">メッセージがありません</p>
      </div>
    )
  }

  return (
    <div className="bg-white rounded-lg border border-gray-200">
      <div className="flex items-center justify-between p-6 pb-4">
        <h2 className="text-lg font-bold text-gray-900 flex items-center space-x-2">
          <span>💬</span>
          <span>最近のメッセージ</span>
        </h2>
        <Link
          href="/message"
          className="text-sm text-blue-600 hover:text-blue-700 font-medium"
        >
          全て見る
        </Link>
      </div>
      <div className="divide-y divide-gray-100">
        {messages.map((msg) => (
          <MessagePreviewItem
            key={msg.id}
            clientId={msg.client_id}
            clientName={msg.sender_name}
            message={msg.message}
            timestamp={msg.timestamp}
          />
        ))}
      </div>
    </div>
  )
}
