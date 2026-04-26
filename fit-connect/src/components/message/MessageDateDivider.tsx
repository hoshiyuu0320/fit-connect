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
    <div className="flex items-center justify-center my-4 gap-3">
      <div className="flex-1 h-px bg-[#E2E8F0]" />
      <span className="bg-[#F8FAFC] text-[#94A3B8] text-xs px-3 py-1 rounded-md border border-[#E2E8F0]">
        {formatDate(date)}
      </span>
      <div className="flex-1 h-px bg-[#E2E8F0]" />
    </div>
  )
}
