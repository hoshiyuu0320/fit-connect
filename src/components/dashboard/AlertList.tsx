import React from 'react'
import { AlertItem, type AlertItemProps } from './AlertItem'

type AlertListProps = {
  alerts: AlertItemProps[]
}

function BellAlertIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
      />
    </svg>
  )
}

export function AlertList({ alerts }: AlertListProps) {
  if (alerts.length === 0) {
    return (
      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <h2 className="text-lg font-bold text-gray-900 mb-4 flex items-center space-x-2">
          <span className="text-gray-500"><BellAlertIcon /></span>
          <span>対応が必要</span>
        </h2>
        <div className="text-center py-8">
          <div className="w-12 h-12 mx-auto mb-3 rounded-full bg-green-100 flex items-center justify-center">
            <svg className="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <p className="text-gray-600 font-medium">対応が必要な項目はありません</p>
          <p className="text-sm text-gray-500 mt-1">すべての顧客が順調です！</p>
        </div>
      </div>
    )
  }

  // 最大5件まで表示
  const displayedAlerts = alerts.slice(0, 5)
  const hasMore = alerts.length > 5

  return (
    <div className="bg-white rounded-xl border border-gray-200">
      <div className="p-6 pb-4 border-b border-gray-100">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-gray-900 flex items-center space-x-2">
            <span className="text-gray-500"><BellAlertIcon /></span>
            <span>対応が必要</span>
          </h2>
          <span className="text-xs font-semibold text-red-600 bg-red-50 border border-red-200 px-2.5 py-1 rounded-full">
            {alerts.length}件
          </span>
        </div>
      </div>
      <div className="divide-y divide-gray-100">
        {displayedAlerts.map((alert, index) => (
          <AlertItem key={`${alert.clientId}-${index}`} {...alert} />
        ))}
      </div>
      {hasMore && (
        <div className="p-4 bg-gray-50 text-center rounded-b-xl">
          <p className="text-sm text-gray-600">
            他 {alerts.length - 5} 件のアラートがあります
          </p>
        </div>
      )}
    </div>
  )
}
