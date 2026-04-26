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
    <div className="bg-white rounded-md border border-[#E2E8F0] overflow-hidden">
      <div className="p-6 pb-4 border-b border-[#E2E8F0]">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-[#0F172A] flex items-center space-x-2">
            <span className="text-[#94A3B8]"><CalendarIcon /></span>
            <span>本日の予定</span>
          </h2>
          {sessions.length > 0 && (
            <span className="text-xs font-semibold text-[#14B8A6] bg-[#F0FDFA] border border-[#CCFBF1] px-2.5 py-1 rounded">
              {sessions.length}件
            </span>
          )}
        </div>
      </div>

      <div className="p-6">
        {sessions.length === 0 ? (
          <div className="text-center py-8">
            <div className="w-12 h-12 mx-auto mb-3 rounded-md bg-[#F8FAFC] flex items-center justify-center text-[#94A3B8]">
              <CalendarIcon />
            </div>
            <p className="text-[#475569] font-medium">本日の予定はありません</p>
            <p className="text-sm text-[#94A3B8] mt-1">新しいセッションを予約しましょう</p>
            <Link
              href="/schedule"
              className="mt-4 inline-flex items-center text-sm text-[#14B8A6] hover:text-[#0D9488] font-medium"
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
