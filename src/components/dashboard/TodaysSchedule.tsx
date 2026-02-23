import React from 'react'
import Link from 'next/link'
import { SessionItem } from './SessionItem'
import type { TodaysSession } from '@/lib/supabase/getTodaysSessions'

type TodaysScheduleProps = {
  sessions: TodaysSession[]
}

function CalendarIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
      />
    </svg>
  )
}

export function TodaysSchedule({ sessions }: TodaysScheduleProps) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
      <div className="p-6 pb-4 border-b border-gray-100">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-gray-900 flex items-center space-x-2">
            <span className="text-gray-500"><CalendarIcon /></span>
            <span>本日の予定</span>
          </h2>
          {sessions.length > 0 && (
            <span className="text-xs font-semibold text-blue-600 bg-blue-50 border border-blue-200 px-2.5 py-1 rounded-full">
              {sessions.length}件
            </span>
          )}
        </div>
      </div>

      <div className="p-6">
        {sessions.length === 0 ? (
          <div className="text-center py-8">
            <div className="w-12 h-12 mx-auto mb-3 rounded-full bg-gray-100 flex items-center justify-center text-gray-400">
              <CalendarIcon />
            </div>
            <p className="text-gray-600 font-medium">本日の予定はありません</p>
            <p className="text-sm text-gray-500 mt-1">新しいセッションを予約しましょう</p>
            <Link
              href="/schedule"
              className="mt-4 inline-flex items-center text-sm text-blue-600 hover:text-blue-700 font-medium"
            >
              スケジュールを見る
              <svg className="w-4 h-4 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </Link>
          </div>
        ) : (
          <div className="space-y-3">
            {sessions.map((session) => (
              <SessionItem key={session.id} {...session} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
