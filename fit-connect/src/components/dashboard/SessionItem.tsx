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
          bgColor: 'bg-emerald-50',
          textColor: 'text-emerald-700',
          borderColor: 'border-emerald-200',
          badgeBg: 'bg-emerald-50',
          badgeText: 'text-emerald-700',
          label: '完了',
        }
      case 'confirmed':
        return {
          bgColor: 'bg-[#F0FDFA]',
          textColor: 'text-[#14B8A6]',
          borderColor: 'border-[#CCFBF1]',
          badgeBg: 'bg-[#F0FDFA]',
          badgeText: 'text-[#14B8A6]',
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
          textColor: 'text-[#475569]',
          borderColor: 'border-[#E2E8F0]',
          badgeBg: 'bg-[#F8FAFC]',
          badgeText: 'text-[#475569]',
          label: '予定',
        }
    }
  }

  const statusStyle = getStatusStyle(status)

  return (
    <Link
      href={`/clients/${client_id}`}
      className={`block border ${statusStyle.borderColor} ${statusStyle.bgColor} rounded-md p-4 hover:shadow-sm transition-all`}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <div className="text-center">
            <p className="text-base font-bold text-[#0F172A] leading-none">
              {formatTime(session_date)}
            </p>
            <p className="text-xs text-[#94A3B8] mt-0.5">
              〜{calculateEndTime(session_date, duration_minutes)}
            </p>
          </div>
          <div className="w-px h-10 bg-[#E2E8F0]" />
          <div>
            <p className="text-base font-semibold text-[#0F172A]">
              {client_name}さん
            </p>
            {session_type && (
              <p className="text-sm text-[#475569]">
                {session_type} &middot; {duration_minutes}分
              </p>
            )}
          </div>
        </div>
        <span className={`text-xs font-semibold px-2.5 py-1 rounded ${statusStyle.badgeBg} ${statusStyle.badgeText}`}>
          {statusStyle.label}
        </span>
      </div>
    </Link>
  )
}
