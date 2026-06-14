'use client'

import { useMemo, useState } from 'react'
import { X, ClipboardList } from 'lucide-react'
import type { Message } from '@/types/client'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'
import type { RecordCardType } from '@/components/message/recordCardParser'
import { RecordCard } from '@/components/message/RecordCard'
import { PfcBalanceCard } from '@/components/clients/PfcBalanceCard'
import { WeightNutritionChart } from '@/components/clients/WeightNutritionChart'
import { extractRecordLog, filterByType } from '@/components/message/recordLog'

interface RecordSidePanelProps {
  messages: Message[]
  clientId: string
  nutritionData: DailyNutritionPoint[]
  targetWeight?: number
  summaryLoading?: boolean
  onClose: () => void
  onImageClick: (url: string) => void
}

const TYPE_TABS: { value: RecordCardType | 'all'; label: string }[] = [
  { value: 'all', label: 'すべて' },
  { value: 'meal', label: '食事' },
  { value: 'weight', label: '体重' },
  { value: 'exercise', label: '運動' },
]

export function RecordSidePanel({
  messages,
  clientId,
  nutritionData,
  targetWeight,
  summaryLoading,
  onClose,
  onImageClick,
}: RecordSidePanelProps) {
  const [typeFilter, setTypeFilter] = useState<RecordCardType | 'all'>('all')

  const logItems = useMemo(() => {
    const all = extractRecordLog(messages)
    // filterByType('all') は元配列をそのまま返すため slice() で複製してから reverse（in-place 破壊防止）
    return filterByType(all, typeFilter).slice().reverse()
  }, [messages, typeFilter])

  return (
    <aside className="w-96 bg-white border-l border-[#E2E8F0] flex flex-col h-full overflow-hidden">
      {/* ヘッダー */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-[#E2E8F0] flex-shrink-0">
        <div className="flex items-center gap-2">
          <ClipboardList className="w-4 h-4 text-[#64748B]" aria-hidden="true" />
          <span className="text-sm font-semibold text-[#0F172A]">記録</span>
        </div>
        <button
          type="button"
          aria-label="記録パネルを閉じる"
          onClick={onClose}
          className="cursor-pointer p-1 rounded-md text-[#64748B] hover:text-[#0F172A] hover:bg-[#F1F5F9] transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
        >
          <X className="w-4 h-4" aria-hidden="true" />
        </button>
      </div>

      {/* サマリーセクション */}
      <div className="flex-shrink-0 border-b border-[#E2E8F0]">
        <div className="px-4 pt-4 pb-2">
          <p className="text-xs text-[#64748B] uppercase tracking-wide font-semibold mb-3">
            サマリー
          </p>

          {/* 体重 × 栄養トレンドグラフ */}
          <div className="mb-4">
            <WeightNutritionChart
              data={nutritionData}
              targetWeight={targetWeight}
              loading={summaryLoading}
            />
          </div>

          {/* PFCバランスカード */}
          <div className="overflow-x-auto">
            <PfcBalanceCard data={nutritionData} />
          </div>
        </div>
      </div>

      {/* 種別フィルタ chips */}
      <div className="flex items-center gap-2 px-4 py-3 border-b border-[#E2E8F0] flex-shrink-0 flex-wrap">
        {TYPE_TABS.map((tab) => {
          const isActive = typeFilter === tab.value
          return (
            <button
              key={tab.value}
              type="button"
              onClick={() => setTypeFilter(tab.value)}
              className={[
                'cursor-pointer px-3 py-1 text-xs font-medium rounded-md border transition-colors duration-200',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]',
                isActive
                  ? 'bg-[#14B8A6] text-white border-[#14B8A6]'
                  : 'bg-white text-[#64748B] border-[#E2E8F0] hover:border-[#14B8A6] hover:text-[#0F172A]',
              ].join(' ')}
            >
              {tab.label}
            </button>
          )
        })}
      </div>

      {/* 記録ログ */}
      <div className="flex-1 overflow-y-auto">
        {logItems.length === 0 ? (
          /* Empty state */
          <div className="flex flex-col items-center justify-center h-full px-6 py-12 text-center">
            <ClipboardList className="w-10 h-10 text-[#94A3B8] mb-3" aria-hidden="true" />
            <p className="text-sm font-semibold text-[#0F172A]">記録がありません</p>
            <p className="text-xs text-[#64748B] mt-2 leading-relaxed">
              クライアントが食事・体重・運動を記録すると、ここに表示されます
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-[#E2E8F0]">
            {logItems.map((item) => (
              <li key={item.message.id} className="px-4 py-3">
                <RecordCard
                  data={item.card}
                  clientId={clientId}
                  imageUrls={item.message.image_urls}
                  onImageClick={onImageClick}
                />
                <p className="text-[10px] text-[#94A3B8] mt-1.5">
                  {new Date(item.message.created_at).toLocaleString('ja-JP', {
                    month: 'numeric',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit',
                  })}
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </aside>
  )
}
