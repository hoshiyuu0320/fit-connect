import React from 'react'
import Link from 'next/link'

type StatCardColor = 'blue' | 'purple' | 'green' | 'red'

type StatCardProps = {
  icon: React.ReactNode
  label: string
  value: number | string
  suffix?: string
  color: StatCardColor
  href?: string
}

const colorMap: Record<StatCardColor, { border: string; bg: string; iconBg: string; iconText: string }> = {
  blue: {
    border: 'border-l-blue-500',
    bg: 'bg-blue-50',
    iconBg: 'bg-blue-100',
    iconText: 'text-blue-600',
  },
  purple: {
    border: 'border-l-purple-500',
    bg: 'bg-purple-50',
    iconBg: 'bg-purple-100',
    iconText: 'text-purple-600',
  },
  green: {
    border: 'border-l-green-500',
    bg: 'bg-green-50',
    iconBg: 'bg-green-100',
    iconText: 'text-green-600',
  },
  red: {
    border: 'border-l-red-500',
    bg: 'bg-red-50',
    iconBg: 'bg-red-100',
    iconText: 'text-red-600',
  },
}

export function StatCard({ icon, label, value, suffix, color, href }: StatCardProps) {
  const c = colorMap[color]

  const content = (
    <div className={`bg-white rounded-xl border border-gray-200 border-l-4 ${c.border} p-6 hover:shadow-md transition-shadow`}>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-medium text-gray-600">{label}</h3>
        <div className={`w-10 h-10 rounded-lg ${c.iconBg} ${c.iconText} flex items-center justify-center`}>
          {icon}
        </div>
      </div>
      <div className="flex items-baseline space-x-1">
        <p className="text-3xl font-bold text-gray-900">{value}</p>
        {suffix && <span className="text-sm text-gray-500">{suffix}</span>}
      </div>
    </div>
  )

  if (href) {
    return <Link href={href}>{content}</Link>
  }

  return content
}
