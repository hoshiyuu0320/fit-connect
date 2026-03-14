'use client'

import { useState, useMemo } from 'react'
import Image from 'next/image'
import { format } from 'date-fns'
import { WeightChart } from '@/components/clients/WeightChart'
import { ImageModal } from '@/components/message/ImageModal'
import type { WeightRecord } from '@/types/client'

interface WeightTabProps {
  weightRecords: WeightRecord[]
  targetWeight: number
}

type WeightPeriod = '1W' | '1M' | '3M' | 'ALL'

const WEIGHT_PERIOD_BUTTONS: { value: WeightPeriod; label: string }[] = [
  { value: '1W', label: '1W' },
  { value: '1M', label: '1M' },
  { value: '3M', label: '3M' },
  { value: 'ALL', label: 'ALL' },
]

export function WeightTab({ weightRecords, targetWeight }: WeightTabProps) {
  const [selectedImageUrl, setSelectedImageUrl] = useState<string | null>(null)
  const [weightPeriod, setWeightPeriod] = useState<WeightPeriod>('1M')

  const filteredRecords = useMemo(() => {
    const now = new Date()
    let startDate: Date
    switch (weightPeriod) {
      case '1W':
        startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
        break
      case '1M':
        startDate = new Date(now.getFullYear(), now.getMonth() - 1, now.getDate())
        break
      case '3M':
        startDate = new Date(now.getFullYear(), now.getMonth() - 3, now.getDate())
        break
      case 'ALL':
      default:
        return weightRecords
    }
    return weightRecords.filter((r) => new Date(r.recorded_at) >= startDate)
  }, [weightRecords, weightPeriod])

  if (weightRecords.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <p className="text-[#94A3B8] text-sm">まだ体重記録がありません</p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* グラフカード */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-semibold text-[#0F172A]">体重推移</h3>
          <div className="flex items-center gap-1">
            {WEIGHT_PERIOD_BUTTONS.map((btn) => (
              <button
                key={btn.value}
                onClick={() => setWeightPeriod(btn.value)}
                className={`px-2.5 py-1 text-xs font-medium rounded-md transition-colors ${
                  weightPeriod === btn.value
                    ? 'bg-[#14B8A6] text-white'
                    : 'bg-[#F8FAFC] text-[#64748B] border border-[#E2E8F0] hover:border-[#14B8A6]'
                }`}
              >
                {btn.label}
              </button>
            ))}
          </div>
        </div>

        {/* 目標体重インジケーター */}
        <div className="flex items-center gap-2 mb-2 text-xs text-[#94A3B8]">
          <span className="inline-block w-4 border-t-2 border-dashed border-[#DC2626]" />
          <span>目標: {targetWeight}kg</span>
        </div>

        <WeightChart weightRecords={filteredRecords} targetWeight={targetWeight} showPeriodFilter={false} />
      </div>

      {/* 最近の記録リスト（最新5件） */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <h3 className="text-sm font-semibold text-[#0F172A] mb-3">最近の記録</h3>
        <div className="space-y-0">
          {weightRecords.slice(0, 5).map((record, i) => {
            const prevRecord = weightRecords[i + 1]
            const change = prevRecord ? record.weight - prevRecord.weight : null
            const comment = record.notes
              ?.replace(/^[\d.]+\s*(?:kg)?\s*/i, '')
              .trim() || null
            const hasImage = record.image_urls && record.image_urls.length > 0

            return (
              <div key={record.id} className="py-3 border-b border-[#F1F5F9] last:border-0">
                {/* 上段: 日付・体重・変化量 */}
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <span className="text-xs text-[#94A3B8] w-16">
                      {format(new Date(record.recorded_at), 'M/d')}
                    </span>
                    <span className="text-sm font-bold text-[#0F172A]">{record.weight}kg</span>
                  </div>
                  <div className="flex items-center gap-2">
                    {change !== null && (
                      <span
                        className={`text-xs font-medium ${
                          change > 0
                            ? 'text-[#DC2626]'
                            : change < 0
                              ? 'text-[#16A34A]'
                              : 'text-[#94A3B8]'
                        }`}
                      >
                        {change > 0 ? '+' : ''}
                        {change.toFixed(1)}
                      </span>
                    )}
                    {hasImage && (
                      <span className="text-[10px] text-[#94A3B8]">📷</span>
                    )}
                  </div>
                </div>

                {/* コメント */}
                {comment && (
                  <div className="mt-2 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-center gap-2">
                    <svg
                      width="12"
                      height="12"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      className="text-[#94A3B8] flex-shrink-0"
                    >
                      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                    </svg>
                    <p className="text-xs text-[#64748B] whitespace-pre-wrap leading-tight">
                      {comment}
                    </p>
                  </div>
                )}

                {/* 写真 */}
                {hasImage && (
                  <div className="flex gap-2 mt-2">
                    {record.image_urls!.map((url, imgIndex) => (
                      <button
                        key={imgIndex}
                        type="button"
                        onClick={() => setSelectedImageUrl(url)}
                        className="relative w-14 h-14 rounded-md overflow-hidden border border-[#E2E8F0] hover:opacity-80 transition-opacity"
                      >
                        <Image
                          src={url}
                          alt={`体重記録画像 ${imgIndex + 1}`}
                          fill
                          className="object-cover"
                          unoptimized
                        />
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </div>

      <ImageModal imageUrl={selectedImageUrl} onClose={() => setSelectedImageUrl(null)} />
    </div>
  )
}
