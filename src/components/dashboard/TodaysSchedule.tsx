import React from 'react'
import { SessionItem } from './SessionItem'
import type { TodaysSession } from '@/lib/supabase/getTodaysSessions'

type TodaysScheduleProps = {
  sessions: TodaysSession[]
}

export function TodaysSchedule({ sessions }: TodaysScheduleProps) {
  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
      <div className="p-4 border-b border-gray-200 bg-gray-50">
        <h2 className="text-lg font-semibold text-gray-900">本日の予定</h2>
        <p className="text-sm text-gray-600 mt-1">
          {sessions.length > 0
            ? `${sessions.length}件のセッション予定があります`
            : 'セッション予定はありません'}
        </p>
      </div>

      <div className="p-4">
        {sessions.length === 0 ? (
          <div className="text-center py-8">
            <p className="text-gray-500 text-sm">
              本日のセッション予定はありません
            </p>
            <p className="text-gray-400 text-xs mt-2">
              新しいセッションを予約しましょう！
            </p>
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
