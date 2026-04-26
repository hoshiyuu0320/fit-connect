'use client'

import Link from 'next/link'
import { User } from 'lucide-react'
import { PURPOSE_OPTIONS, GENDER_OPTIONS } from '@/types/client'

interface ChatHeaderProps {
  client: {
    client_id?: string
    name: string
    profile_image_url: string | null
    purpose?: string
    gender?: string
    age?: number
  } | null
}

export function ChatHeader({ client }: ChatHeaderProps) {
  if (!client) {
    return (
      <div className="flex items-center gap-3 px-4 py-3 border-b border-[#E2E8F0] bg-white">
        <span className="text-sm text-[#94A3B8]">クライアントを選択してください</span>
      </div>
    )
  }

  const initial = client.name.charAt(0).toUpperCase()

  const purposeLabel = client.purpose
    ? PURPOSE_OPTIONS[client.purpose as keyof typeof PURPOSE_OPTIONS] || client.purpose
    : null

  const genderLabel = client.gender
    ? GENDER_OPTIONS[client.gender as keyof typeof GENDER_OPTIONS] || client.gender
    : null

  const subTextParts: string[] = []
  if (purposeLabel) subTextParts.push(purposeLabel)
  if (genderLabel) subTextParts.push(genderLabel)
  if (client.age) subTextParts.push(`${client.age}歳`)

  const subText = subTextParts.join('・')

  return (
    <div className="flex items-center justify-between gap-3 px-4 py-3 border-b border-[#E2E8F0] bg-white">
      <div className="flex items-center gap-3">
        {client.profile_image_url ? (
          <img
            src={client.profile_image_url}
            alt={client.name}
            className="w-9 h-9 rounded-full object-cover"
          />
        ) : (
          <div className="w-9 h-9 rounded-full bg-[#F8FAFC] border border-[#E2E8F0] flex items-center justify-center text-sm font-bold text-[#64748B]">
            {initial}
          </div>
        )}
        <div>
          <p className="font-semibold text-[#0F172A] text-sm leading-tight">{client.name}</p>
          {subText && (
            <p className="text-xs text-[#94A3B8] leading-tight mt-0.5">{subText}</p>
          )}
        </div>
      </div>

      {client.client_id && (
        <Link
          href={`/clients/${client.client_id}`}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-[#64748B] border border-[#E2E8F0] rounded-md hover:bg-[#F8FAFC] transition-colors"
        >
          <User size={13} />
          <span>顧客詳細</span>
        </Link>
      )}
    </div>
  )
}
