import React from 'react'
import Link from 'next/link'

type QuickActionButtonProps = {
  href: string
  icon: React.ReactNode
  label: string
}

function QuickActionButton({ href, icon, label }: QuickActionButtonProps) {
  return (
    <Link
      href={href}
      className="flex flex-col items-center justify-center space-y-2 px-4 py-5 rounded-md font-medium transition-all bg-white border border-[#E2E8F0] hover:border-[#14B8A6] hover:bg-[#F0FDFA] hover:text-[#0F172A] text-[#475569]"
    >
      <span className="text-[#94A3B8]">{icon}</span>
      <span className="text-sm">{label}</span>
    </Link>
  )
}

function UsersIcon() {
  return (
    <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
      />
    </svg>
  )
}

function ChatIcon() {
  return (
    <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
      />
    </svg>
  )
}

function ChartBarIcon() {
  return (
    <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
      />
    </svg>
  )
}

function CalendarIcon() {
  return (
    <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
      />
    </svg>
  )
}

function LightningIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M13 10V3L4 14h7v7l9-11h-7z"
      />
    </svg>
  )
}

export function QuickActions() {
  return (
    <div className="bg-white rounded-md border border-[#E2E8F0] p-6">
      <h2 className="text-lg font-bold text-[#0F172A] mb-4 flex items-center space-x-2">
        <span className="text-[#94A3B8]"><LightningIcon /></span>
        <span>クイックアクション</span>
      </h2>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <QuickActionButton href="/clients" icon={<UsersIcon />} label="顧客を探す" />
        <QuickActionButton href="/message" icon={<ChatIcon />} label="メッセージ" />
        <QuickActionButton href="/report" icon={<ChartBarIcon />} label="レポート" />
        <QuickActionButton href="/schedule" icon={<CalendarIcon />} label="スケジュール" />
      </div>
    </div>
  )
}
