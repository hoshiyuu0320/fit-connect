import React from 'react'
import Link from 'next/link'

export type AlertType = 'inactive' | 'ticket_expiring' | 'workout_undone'

export type AlertItemProps = {
  type: AlertType
  clientId?: string
  clientName?: string
  message: string
  severity: 'high' | 'medium'
}

export function AlertItem({
  clientId,
  clientName,
  message,
  severity,
}: AlertItemProps) {
  const dot =
    severity === 'high' ? (
      <span className="w-2 h-2 rounded-full bg-red-500 inline-block flex-shrink-0 mt-1.5" />
    ) : (
      <span className="w-2 h-2 rounded-full bg-amber-500 inline-block flex-shrink-0 mt-1.5" />
    )

  const accentBorder = severity === 'high' ? 'border-l-red-500' : 'border-l-amber-500'
  const severityColor = severity === 'high' ? 'text-red-600' : 'text-amber-600'

  const content = (
    <div className={`p-4 border-l-2 ${accentBorder}`}>
      <div className="flex items-start space-x-3">
        {dot}
        <div className="flex-1 min-w-0">
          <p className={`text-sm font-medium ${severityColor}`}>
            {clientName ? `${clientName}さん - ${message}` : message}
          </p>
        </div>
      </div>
    </div>
  )

  if (clientId) {
    return (
      <Link
        href={`/clients/${clientId}`}
        className="block border-b border-[#E2E8F0] last:border-b-0 hover:bg-[#F8FAFC] transition-colors"
      >
        {content}
      </Link>
    )
  }

  return (
    <div className="block border-b border-[#E2E8F0] last:border-b-0">
      {content}
    </div>
  )
}
