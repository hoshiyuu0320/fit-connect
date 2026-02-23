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
          badgeBg: 'bg-green-100',
          badgeText: 'text-green-700',
          label: '完了',
        }
      case 'confirmed':
        return {
          bgColor: 'bg-blue-50',
          textColor: 'text-blue-700',
          borderColor: 'border-blue-200',
          badgeBg: 'bg-blue-100',
          badgeText: 'text-blue-700',
          label: '確定',
        }
      case 'cancelled':
        return {
          bgColor: 'bg-gray-50',
          textColor: 'text-gray-500',
          borderColor: 'border-gray-200',
          badgeBg: 'bg-gray-100',
          badgeText: 'text-gray-500',
          label: 'キャンセル',
        }
      default: // scheduled
        return {
          bgColor: 'bg-white',
          textColor: 'text-gray-700',
          borderColor: 'border-gray-200',
          badgeBg: 'bg-gray-100',
          badgeText: 'text-gray-600',
          label: '予定',
        }
    }
  }

  const statusStyle = getStatusStyle(status)

  return (
    <Link
      href={`/clients/${client_id}`}
      className={`block border ${statusStyle.borderColor} ${statusStyle.bgColor} rounded-xl p-4 hover:shadow-md transition-all`}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <div className="text-center">
            <p className="text-base font-bold text-gray-900 leading-none">
              {formatTime(session_date)}
            </p>
            <p className="text-xs text-gray-500 mt-0.5">
              〜{calculateEndTime(session_date, duration_minutes)}
            </p>
          </div>
          <div className="w-px h-10 bg-gray-200" />
          <div>
            <p className="text-base font-semibold text-gray-900">
              {client_name}さん
            </p>
            {session_type && (
              <p className="text-sm text-gray-500">
                {session_type} &middot; {duration_minutes}分
              </p>
            )}
          </div>
        </div>
        <span className={`text-xs font-semibold px-2.5 py-1 rounded-full ${statusStyle.badgeBg} ${statusStyle.badgeText}`}>
          {statusStyle.label}
        </span>
      </div>
    </Link>
  )
}
