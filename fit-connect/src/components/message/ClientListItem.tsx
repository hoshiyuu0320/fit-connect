'use client'

interface ClientListItemProps {
  client: { client_id: string; name: string; profile_image_url: string | null }
  isSelected: boolean
  unreadCount: number
  lastMessage?: string
  lastMessageAt?: string
  onClick: () => void
}

function formatTimestamp(dateStr: string): string {
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

  if (isToday) {
    return date.toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })
  }
  if (isYesterday) {
    return '昨日'
  }
  return `${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')}`
}

export function ClientListItem({
  client,
  isSelected,
  unreadCount,
  lastMessage,
  lastMessageAt,
  onClick,
}: ClientListItemProps) {
  const initial = client.name.charAt(0).toUpperCase()
  const hasUnread = unreadCount > 0

  return (
    <div
      onClick={onClick}
      className={`flex items-center gap-3 px-3 py-3 cursor-pointer hover:bg-[#F8FAFC] transition-colors border-b border-[#E2E8F0] ${
        isSelected ? 'bg-[#F0FDFA] border-l-2 border-[#14B8A6]' : 'border-l-2 border-transparent'
      }`}
    >
      {/* Avatar */}
      <div className="flex-shrink-0 relative">
        {client.profile_image_url ? (
          <img
            src={client.profile_image_url}
            alt={client.name}
            className="w-10 h-10 rounded-full object-cover"
          />
        ) : (
          <div className={`w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold text-white ${lastMessage ? 'bg-[#64748B]' : 'bg-[#CBD5E1]'}`}>
            {initial}
          </div>
        )}
        {hasUnread && (
          <span className="absolute -top-0.5 -right-0.5 w-3 h-3 bg-[#DC2626] border-2 border-white rounded-full" />
        )}
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between gap-1">
          <span className={`text-sm truncate ${hasUnread ? 'font-bold text-[#0F172A]' : 'font-medium text-[#0F172A]'}`}>
            {client.name}
          </span>
          {lastMessageAt && (
            <span className={`text-xs flex-shrink-0 ${hasUnread ? 'text-[#14B8A6] font-semibold' : 'text-[#94A3B8]'}`}>
              {formatTimestamp(lastMessageAt)}
            </span>
          )}
        </div>
        <div className="flex items-center justify-between gap-1 mt-0.5">
          {lastMessage ? (
            <p className={`text-xs truncate max-w-[140px] ${hasUnread ? 'text-[#0F172A] font-medium' : 'text-[#94A3B8]'}`}>
              {lastMessage}
            </p>
          ) : (
            <p className="text-xs text-[#94A3B8] italic">メッセージなし</p>
          )}
          {hasUnread && (
            <span className="flex-shrink-0 bg-[#14B8A6] text-white rounded-full min-w-[18px] h-[18px] text-[10px] font-bold flex items-center justify-center px-[5px]">
              {unreadCount > 99 ? '99+' : unreadCount}
            </span>
          )}
        </div>
      </div>
    </div>
  )
}
