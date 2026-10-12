'use client'

import { X } from 'lucide-react'

interface NotificationHoldNoticeProps {
  /** 書きかけがあるため切り替えなかった通知の顧客の名前（null なら中身を出さない） */
  heldClientName: string | null
  /** 「〇〇さんの会話を開く」（サイドバーのクリックと同じく切り替える） */
  onOpen: () => void
  /** 案内を閉じる */
  onDismiss: () => void
}

/**
 * メッセージ通知のクリックで別の顧客の会話を開こうとしたが、書きかけがあるため切り替えなかったときの案内。
 * ヘッダーの直下に置く（設計書 docs/superpowers/specs/2026-10-12-message-notification-open-chat-design.md §5）。
 * 中身が後から入ったときに読み上げられるよう、外側の status は常に描画する（中身が無いときは高さ 0）
 */
export function NotificationHoldNotice({ heldClientName, onOpen, onDismiss }: NotificationHoldNoticeProps) {
  return (
    <div role="status" aria-live="polite">
      {heldClientName && (
        <div className="flex flex-wrap items-start gap-x-3 gap-y-1 px-4 py-2 border-b border-[#E2E8F0] bg-[#F8FAFC]">
          {/* 文言は 12rem を基準に伸び、足りなければボタンの組が次の行に回る（細いチャット欄で文言を押しつぶさない）。
              py-1 はボタンの文字と1行目の高さをそろえるため */}
          <p className="basis-48 grow min-w-0 text-sm text-[#334155] break-words py-1">
            {heldClientName}さんから新しいメッセージがあります。書きかけがあるため、会話は切り替えていません。
          </p>
          <div className="ml-auto flex max-w-full items-center gap-1">
            <button
              type="button"
              onClick={onOpen}
              className="text-sm font-medium text-[#0F766E] hover:text-[#115E59] hover:bg-[#F0FDFA] rounded-md px-2 py-1 cursor-pointer transition-colors min-w-0 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
            >
              {heldClientName}さんの会話を開く
            </button>
            <button
              type="button"
              onClick={onDismiss}
              className="p-1 text-[#64748B] hover:text-[#334155] hover:bg-[#F1F5F9] rounded-md cursor-pointer transition-colors shrink-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
              aria-label="案内を閉じる"
              title="案内を閉じる"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
