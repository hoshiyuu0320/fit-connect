import React from 'react'
import Link from 'next/link'
import { MessagePreviewItem } from './MessagePreviewItem'
import type { RecentMessage } from '@/lib/supabase/getRecentMessages'

type MessagePreviewListProps = {
  messages: RecentMessage[]
}

function ChatBubbleIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
      />
    </svg>
  )
}

export function MessagePreviewList({ messages }: MessagePreviewListProps) {
  if (messages.length === 0) {
    return (
      <div className="bg-white rounded-md border border-[#E2E8F0] p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-bold text-[#0F172A] flex items-center space-x-2">
            <span className="text-[#94A3B8]"><ChatBubbleIcon /></span>
            <span>最近のメッセージ</span>
          </h2>
        </div>
        <p className="text-center text-[#94A3B8] py-8">メッセージがありません</p>
      </div>
    )
  }

  return (
    <div className="bg-white rounded-md border border-[#E2E8F0]">
      <div className="flex items-center justify-between p-6 pb-4 border-b border-[#E2E8F0]">
        <h2 className="text-lg font-bold text-[#0F172A] flex items-center space-x-2">
          <span className="text-[#94A3B8]"><ChatBubbleIcon /></span>
          <span>最近のメッセージ</span>
        </h2>
        <Link
          href="/message"
          className="text-sm text-[#14B8A6] hover:text-[#0D9488] font-medium"
        >
          全て見る
        </Link>
      </div>
      <div className="divide-y divide-[#E2E8F0]">
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
