import React from 'react'
import Link from 'next/link'

export type AlertType = 'inactive' | 'ticket_expiring'

export type AlertItemProps = {
  type: AlertType
  clientId: string
  clientName: string
  message: string
  severity: 'high' | 'medium'
}

export function AlertItem({
  clientId,
  clientName,
  message,
  severity,
}: AlertItemProps) {
  const severityIcon = severity === 'high' ? '🔴' : '🟡'
  const severityColor = severity === 'high' ? 'text-red-700' : 'text-yellow-700'

  return (
    <Link
      href={`/clients/${clientId}`}
      className="block border-b border-gray-100 last:border-b-0 hover:bg-gray-50 transition-colors"
    >
      <div className="p-4">
        <div className="flex items-start space-x-3">
          <span className="text-lg flex-shrink-0">{severityIcon}</span>
          <div className="flex-1 min-w-0">
            <p className={`text-sm font-medium ${severityColor}`}>
              {clientName}さん - {message}
            </p>
          </div>
        </div>
      </div>
    </Link>
  )
}
