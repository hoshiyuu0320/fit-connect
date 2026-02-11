'use client'

interface ReplyQuoteProps {
  senderName: string         // 返信先の送信者名
  content: string            // 返信先のメッセージ本文
  isTrainerMessage: boolean  // このメッセージ自体がトレーナーのものかどうか（色分けに使用）
  onClick?: () => void       // クリック時のコールバック（元メッセージにスクロール、オプション）
}

export function ReplyQuote({
  senderName,
  content,
  isTrainerMessage,
  onClick,
}: ReplyQuoteProps) {
  return (
    <div
      className={`
        px-2 py-1.5 mb-1.5 rounded border-l-2
        ${isTrainerMessage
          ? 'bg-blue-50 border-blue-400'
          : 'bg-gray-50 border-gray-400'
        }
        ${onClick ? 'cursor-pointer hover:opacity-80 transition-opacity' : ''}
      `}
      onClick={onClick}
    >
      <div className="text-xs font-semibold text-gray-600">
        {senderName}
      </div>
      <div className="text-xs text-gray-500 truncate">
        {content}
      </div>
    </div>
  )
}
