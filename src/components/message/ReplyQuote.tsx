'use client'

interface ReplyQuoteProps {
  senderName: string         // 返信先の送信者名
  content: string            // 返信先のメッセージ本文
  isTrainerMessage: boolean  // このメッセージ自体がトレーナーのものかどうか（色分けに使用）
  inTrainerBubble?: boolean  // emerald背景バブル内かどうか（色調整に使用）
  onClick?: () => void       // クリック時のコールバック（元メッセージにスクロール、オプション）
}

export function ReplyQuote({
  senderName,
  content,
  isTrainerMessage,
  inTrainerBubble = false,
  onClick,
}: ReplyQuoteProps) {
  return (
    <div
      className={`
        px-2 py-1.5 mb-1.5 rounded border-l-2
        ${inTrainerBubble
          ? 'bg-emerald-600/30 border-emerald-300/50'
          : isTrainerMessage
            ? 'bg-blue-50 border-blue-400'
            : 'bg-gray-50 border-gray-400'
        }
        ${onClick ? 'cursor-pointer hover:opacity-80 transition-opacity' : ''}
      `}
      onClick={onClick}
    >
      <div className={`text-xs font-semibold ${inTrainerBubble ? 'text-emerald-100' : 'text-gray-600'}`}>
        {senderName}
      </div>
      <div className={`text-xs truncate ${inTrainerBubble ? 'text-emerald-200' : 'text-gray-500'}`}>
        {content}
      </div>
    </div>
  )
}
