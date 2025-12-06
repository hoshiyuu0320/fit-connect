import React from 'react'
import Link from 'next/link'
import type { TodaysSession } from '@/lib/supabase/getTodaysSessions'

export type SessionItemProps = TodaysSession

export function SessionItem({
  client_id,
  client_name,
  session_date,
  duration_minutes,
  status,
  session_type,
}: SessionItemProps) {
  // 時刻をフォーマット（HH:mm形式）
  const formatTime = (dateString: string) => {
    const date = new Date(dateString)
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${hours}:${minutes}`
  }

  // 終了時刻を計算
  const calculateEndTime = (startDate: string, durationMinutes: number) => {
    const start = new Date(startDate)
    const end = new Date(start.getTime() + durationMinutes * 60000)
    const hours = end.getHours().toString().padStart(2, '0')
    const minutes = end.getMinutes().toString().padStart(2, '0')
    return `${hours}:${minutes}`
  }

  // ステータスに応じたスタイルとラベル
  const getStatusStyle = (status: string) => {
    switch (status) {
      case 'completed':
        return {
          bgColor: 'bg-green-50',
          textColor: 'text-green-700',
          borderColor: 'border-green-200',
          label: '完了',
        }
      case 'confirmed':
        return {
          bgColor: 'bg-blue-50',
          textColor: 'text-blue-700',
          borderColor: 'border-blue-200',
          label: '確定',
        }
      case 'cancelled':
        return {
          bgColor: 'bg-gray-50',
          textColor: 'text-gray-500',
          borderColor: 'border-gray-200',
          label: 'キャンセル',
        }
      default: // scheduled
        return {
          bgColor: 'bg-white',
          textColor: 'text-gray-700',
          borderColor: 'border-gray-200',
          label: '予定',
        }
    }
  }

  const statusStyle = getStatusStyle(status)

  return (
    <Link
      href={`/clients/${client_id}`}
      className={`block border ${statusStyle.borderColor} ${statusStyle.bgColor} rounded-lg p-4 hover:shadow-md transition-all`}
    >
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <div className="flex items-center space-x-2 mb-1">
            <span className="text-sm font-semibold text-gray-900">
              {formatTime(session_date)} - {calculateEndTime(session_date, duration_minutes)}
            </span>
            <span
              className={`text-xs px-2 py-0.5 rounded-full ${statusStyle.bgColor} ${statusStyle.textColor} border ${statusStyle.borderColor}`}
            >
              {statusStyle.label}
            </span>
          </div>
          <p className="text-base font-medium text-gray-900 mb-1">
            {client_name}さん
          </p>
          {session_type && (
            <p className="text-sm text-gray-600">
              {session_type} ({duration_minutes}分)
            </p>
          )}
        </div>
      </div>
    </Link>
  )
}
