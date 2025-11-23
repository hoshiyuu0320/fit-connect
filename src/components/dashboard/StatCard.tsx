import React from 'react'

type StatCardProps = {
  icon: string
  label: string
  value: number | string
  suffix?: string
}

export function StatCard({ icon, label, value, suffix }: StatCardProps) {
  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6 hover:shadow-md transition-shadow">
      <div className="flex items-center space-x-3 mb-3">
        <span className="text-2xl">{icon}</span>
        <h3 className="text-sm font-medium text-gray-600">{label}</h3>
      </div>
      <div className="flex items-baseline space-x-1">
        <p className="text-3xl font-bold text-gray-900">{value}</p>
        {suffix && <span className="text-sm text-gray-500">{suffix}</span>}
      </div>
    </div>
  )
}
