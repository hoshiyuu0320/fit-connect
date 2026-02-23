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

  return (
    <div
      onClick={onClick}
      className={`flex items-center gap-3 px-3 py-3 cursor-pointer hover:bg-gray-50 transition-colors ${
        isSelected ? 'bg-blue-50 border-l-2 border-blue-500' : 'border-l-2 border-transparent'
      }`}
    >
      {/* Avatar */}
      <div className="flex-shrink-0">
        {client.profile_image_url ? (
          <img
            src={client.profile_image_url}
            alt={client.name}
            className="w-10 h-10 rounded-full object-cover"
          />
        ) : (
          <div className="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center text-sm font-bold text-gray-600">
            {initial}
          </div>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between gap-1">
          <span className="font-medium text-sm text-gray-900 truncate">{client.name}</span>
          {lastMessageAt && (
            <span className="text-xs text-gray-400 flex-shrink-0">{formatTimestamp(lastMessageAt)}</span>
          )}
        </div>
        <div className="flex items-center justify-between gap-1 mt-0.5">
          {lastMessage ? (
            <p className="text-xs text-gray-500 truncate max-w-[140px]">{lastMessage}</p>
          ) : (
            <p className="text-xs text-gray-400 italic">メッセージなし</p>
          )}
          {unreadCount > 0 && (
            <span className="flex-shrink-0 bg-red-500 text-white rounded-full min-w-[20px] h-5 text-xs flex items-center justify-center px-1">
              {unreadCount > 99 ? '99+' : unreadCount}
            </span>
          )}
        </div>
      </div>
    </div>
  )
}
