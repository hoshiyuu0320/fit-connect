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
      <div className="bg-white rounded-md border border-[#E2E8F0] p-6">
        <h2 className="text-lg font-bold text-[#0F172A] mb-4 flex items-center space-x-2">
          <span className="text-[#94A3B8]"><BellAlertIcon /></span>
          <span>対応が必要</span>
        </h2>
        <div className="text-center py-8">
          <div className="w-12 h-12 mx-auto mb-3 rounded-md bg-emerald-50 flex items-center justify-center">
            <svg className="w-6 h-6 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <p className="text-[#475569] font-medium">対応が必要な項目はありません</p>
          <p className="text-sm text-[#94A3B8] mt-1">すべての顧客が順調です！</p>
        </div>
      </div>
    )
  }

  // 最大5件まで表示
  const displayedAlerts = alerts.slice(0, 5)
  const hasMore = alerts.length > 5

  return (
    <div className="bg-white rounded-md border border-[#E2E8F0]">
      <div className="p-6 pb-4 border-b border-[#E2E8F0]">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-[#0F172A] flex items-center space-x-2">
            <span className="text-[#94A3B8]"><BellAlertIcon /></span>
            <span>対応が必要</span>
          </h2>
          <span className="text-xs font-semibold text-red-600 bg-red-50 border border-red-200 px-2.5 py-1 rounded">
            {alerts.length}件
          </span>
        </div>
      </div>
      <div className="divide-y divide-[#E2E8F0]">
        {displayedAlerts.map((alert, index) => (
          <AlertItem key={`${alert.clientId}-${index}`} {...alert} />
        ))}
      </div>
      {hasMore && (
        <div className="p-4 bg-[#F8FAFC] text-center rounded-b-md">
          <p className="text-sm text-[#475569]">
            他 {alerts.length - 5} 件のアラートがあります
          </p>
        </div>
      )}
    </div>
  )
}
