'use client'

interface ReplyQuoteProps {
  senderName: string         // 返信先の送信者名
  content: string            // 返信先のメッセージ本文
  isTrainerMessage?: boolean // 後方互換性のため残留（未使用）
  inTrainerBubble?: boolean  // teal背景バブル内かどうか（色調整に使用）
  onClick?: () => void       // クリック時のコールバック（元メッセージにスクロール、オプション）
}

export function ReplyQuote({
  senderName,
  content,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  isTrainerMessage: _isTrainerMessage,
  inTrainerBubble = false,
  onClick,
}: ReplyQuoteProps) {
  return (
    <div
      className={`
        px-2 py-1.5 mb-1.5 rounded-md border-l-2
        ${inTrainerBubble
          ? 'bg-white/15 border-l-white/50'
          : 'bg-[#F8FAFC] border-l-[#14B8A6]'
        }
        ${onClick ? 'cursor-pointer hover:opacity-80 transition-opacity' : ''}
      `}
      onClick={onClick}
    >
      <div className={`text-[10px] font-semibold ${inTrainerBubble ? 'text-white/85' : 'text-[#475569]'}`}>
        {senderName}
      </div>
      <div className={`text-xs truncate ${inTrainerBubble ? 'text-white/85' : 'text-[#475569]'}`}>
        {content}
      </div>
    </div>
  )
}
