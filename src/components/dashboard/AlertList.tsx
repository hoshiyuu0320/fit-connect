import React from 'react'
import { AlertItem, type AlertItemProps } from './AlertItem'

type AlertListProps = {
  alerts: AlertItemProps[]
}

export function AlertList({ alerts }: AlertListProps) {
  if (alerts.length === 0) {
    return (
      <div className="bg-white rounded-lg border border-gray-200 p-6">
        <h2 className="text-lg font-bold text-gray-900 mb-4 flex items-center space-x-2">
          <span>⚠️</span>
          <span>要確認</span>
        </h2>
        <div className="text-center py-8">
          <div className="text-5xl mb-3">✨</div>
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
    <div className="bg-white rounded-lg border border-gray-200">
      <div className="p-6 pb-4 border-b border-gray-100">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-gray-900 flex items-center space-x-2">
            <span>⚠️</span>
            <span>要確認</span>
          </h2>
          <span className="text-sm font-semibold text-red-600 bg-red-50 px-2 py-1 rounded">
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
        <div className="p-4 bg-gray-50 text-center">
          <p className="text-sm text-gray-600">
            他 {alerts.length - 5} 件のアラートがあります
          </p>
        </div>
      )}
    </div>
  )
}
