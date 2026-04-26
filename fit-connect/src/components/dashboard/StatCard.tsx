import React from 'react'
import Link from 'next/link'

type StatCardColor = 'teal' | 'green' | 'amber' | 'red'

type StatCardProps = {
  icon: React.ReactNode
  label: string
  value: number | string
  suffix?: string
  color: StatCardColor
  href?: string
}

const colorMap: Record<StatCardColor, { iconBg: string; iconText: string }> = {
  teal: {
    iconBg: 'bg-[#F0FDFA]',
    iconText: 'text-[#14B8A6]',
  },
  green: {
    iconBg: 'bg-emerald-50',
    iconText: 'text-emerald-600',
  },
  amber: {
    iconBg: 'bg-amber-50',
    iconText: 'text-amber-600',
  },
  red: {
    iconBg: 'bg-red-50',
    iconText: 'text-red-600',
  },
}

export function StatCard({ icon, label, value, suffix, color, href }: StatCardProps) {
  const c = colorMap[color]

  const content = (
    <div className="bg-white rounded-md border border-[#E2E8F0] p-6 hover:shadow-sm transition-shadow">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-xs font-medium text-[#94A3B8]">{label}</h3>
        <div className={`w-10 h-10 rounded-md ${c.iconBg} ${c.iconText} flex items-center justify-center`}>
          {icon}
        </div>
      </div>
      <div className="flex items-baseline space-x-1">
        <p className="text-[32px] font-bold text-[#0F172A] tracking-tight leading-none">{value}</p>
        {suffix && <span className="text-xs text-[#94A3B8]">{suffix}</span>}
      </div>
    </div>
  )

  if (href) {
    return <Link href={href}>{content}</Link>
  }

  return content
}
