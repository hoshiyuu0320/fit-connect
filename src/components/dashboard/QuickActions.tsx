import React from 'react'
import Link from 'next/link'

type QuickActionButtonProps = {
  href: string
  icon: string
  label: string
  disabled?: boolean
}

function QuickActionButton({ href, icon, label, disabled = false }: QuickActionButtonProps) {
  const baseClasses = "flex items-center justify-center space-x-2 px-6 py-4 rounded-lg font-medium transition-all"
  const enabledClasses = "bg-blue-600 text-white hover:bg-blue-700 hover:shadow-md"
  const disabledClasses = "bg-gray-100 text-gray-400 cursor-not-allowed"

  if (disabled) {
    return (
      <div className={`${baseClasses} ${disabledClasses}`}>
        <span className="text-xl">{icon}</span>
        <span>{label}</span>
      </div>
    )
  }

  return (
    <Link href={href} className={`${baseClasses} ${enabledClasses}`}>
      <span className="text-xl">{icon}</span>
      <span>{label}</span>
    </Link>
  )
}

export function QuickActions() {
  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6">
      <h2 className="text-lg font-bold text-gray-900 mb-4 flex items-center space-x-2">
        <span>⚡</span>
        <span>クイックアクション</span>
      </h2>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <QuickActionButton href="/clients" icon="🔍" label="顧客を探す" />
        <QuickActionButton href="/message" icon="💬" label="メッセージ" />
        <QuickActionButton href="/report" icon="📊" label="レポート" disabled />
        <QuickActionButton href="/schedule" icon="📅" label="スケジュール" disabled />
      </div>
    </div>
  )
}
