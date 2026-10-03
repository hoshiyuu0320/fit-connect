'use client'

import { Moon, X } from 'lucide-react'

interface RecordQuotePreviewProps {
  /** 見出し（例 '睡眠 9/22(火)'） */
  label: string
  /** 本文の先頭に付く1行 */
  text: string
  onCancel: () => void
}

/** 入力欄の上に出す「記録の引用」チップ。送信時に text が本文の先頭に付く */
export function RecordQuotePreview({ label, text, onCancel }: RecordQuotePreviewProps) {
  return (
    <div className="bg-[#F0FDFA] border-l-[3px] border-[#14B8A6] rounded-md p-3 mb-2 flex items-center justify-between gap-3">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5 mb-1">
          <Moon className="h-3.5 w-3.5 text-[#14B8A6]" aria-hidden="true" />
          <span className="text-sm font-semibold text-[#14B8A6]">{label}</span>
        </div>
        <p className="text-sm text-[#475569] break-words">{text}</p>
      </div>
      <button
        type="button"
        onClick={onCancel}
        className="flex-shrink-0 p-1 text-[#94A3B8] hover:text-[#64748B] hover:bg-[#CCFBF1] rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
        aria-label="引用を取り消す"
        title="引用を取り消す"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  )
}
