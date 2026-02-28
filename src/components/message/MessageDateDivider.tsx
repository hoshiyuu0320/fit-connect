'use client'

interface MessageDateDividerProps {
  date: string  // ISO日付文字列
}

const WEEKDAY_JA = ['日', '月', '火', '水', '木', '金', '土']

function formatDate(dateStr: string): string {
  const date = new Date(dateStr)
  const now = new Date()

  const isToday =
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate()

  const yesterday = new Date(now)
  yesterday.setDate(now.getDate() - 1)
  const isYesterday =
    date.getFullYear() === yesterday.getFullYear() &&
    date.getMonth() === yesterday.getMonth() &&
    date.getDate() === yesterday.getDate()

  if (isToday) return '今日'
  if (isYesterday) return '昨日'

  const weekday = WEEKDAY_JA[date.getDay()]
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日（${weekday}）`
}

export function MessageDateDivider({ date }: MessageDateDividerProps) {
  return (
    <div className="flex items-center justify-center my-4">
      <span className="bg-gray-100 text-gray-500 text-xs px-3 py-1 rounded-full">
        {formatDate(date)}
      </span>
    </div>
  )
}
