'use client'

import { PURPOSE_OPTIONS } from '@/types/client'

interface ChatHeaderProps {
  client: { name: string; profile_image_url: string | null; purpose?: string } | null
}

export function ChatHeader({ client }: ChatHeaderProps) {
  if (!client) {
    return (
      <div className="flex items-center gap-3 px-4 py-3 border-b border-gray-200 bg-white">
        <span className="text-sm text-gray-400">クライアントを選択してください</span>
      </div>
    )
  }

  const initial = client.name.charAt(0).toUpperCase()
  const purposeLabel = client.purpose
    ? PURPOSE_OPTIONS[client.purpose as keyof typeof PURPOSE_OPTIONS] || client.purpose
    : null

  return (
    <div className="flex items-center gap-3 px-4 py-3 border-b border-gray-200 bg-white">
      {client.profile_image_url ? (
        <img
          src={client.profile_image_url}
          alt={client.name}
          className="w-9 h-9 rounded-full object-cover"
        />
      ) : (
        <div className="w-9 h-9 rounded-full bg-gray-200 flex items-center justify-center text-sm font-bold text-gray-600">
          {initial}
        </div>
      )}
      <div>
        <p className="font-semibold text-gray-900 text-sm leading-tight">{client.name}</p>
        {purposeLabel && (
          <p className="text-xs text-gray-500 leading-tight">目標: {purposeLabel}</p>
        )}
      </div>
    </div>
  )
}
