'use client'

import { useState } from 'react'
import Image from 'next/image'
import { WeightChart } from '@/components/clients/WeightChart'
import { ImageModal } from '@/components/message/ImageModal'
import type { WeightRecord } from '@/types/client'

interface WeightTabProps {
  weightRecords: WeightRecord[]
  targetWeight: number
}

export function WeightTab({ weightRecords, targetWeight }: WeightTabProps) {
  const [selectedImageUrl, setSelectedImageUrl] = useState<string | null>(null)

  if (weightRecords.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <p className="text-gray-500">まだ体重記録がありません</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* グラフ表示 */}
      <WeightChart weightRecords={weightRecords} targetWeight={targetWeight} />

      {/* 記録一覧 */}
      <div className="mt-6 pt-4 border-t">
        <p className="text-sm text-gray-600 mb-3">記録一覧（最新10件）</p>
        <div className="max-h-[400px] overflow-y-auto custom-scrollbar space-y-3">
          {weightRecords
            .slice(-10)
            .reverse()
            .map((record) => {
              // コメント抽出（notes先頭の数値+kg部分を除去）
              const comment = record.notes
                ?.replace(/^[\d.]+\s*(?:kg)?\s*/i, '')
                .trim() || null
              const hasImage = record.image_urls && record.image_urls.length > 0

              return (
                <div
                  key={record.id}
                  className="rounded-xl bg-white shadow-sm border border-gray-100 p-4"
                >
                  {/* 上段: 日付・体重・コメント */}
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-800">
                      {new Date(record.recorded_at).toLocaleDateString('ja-JP', {
                        month: 'numeric',
                        day: 'numeric',
                      })}
                    </span>
                    <span className="text-lg font-bold">
                      {record.weight} <span className="text-sm font-normal">kg</span>
                    </span>
                  </div>
                  {comment && (
                    <div className="mt-2 bg-gray-100 rounded-lg px-3 py-2 flex items-center gap-2">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400 flex-shrink-0">
                        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                      </svg>
                      <p className="text-sm text-gray-700 whitespace-pre-wrap leading-tight">
                        {comment}
                      </p>
                    </div>
                  )}

                  {/* 下段: 写真セクション（区切り線付き） */}
                  {hasImage && (
                    <>
                      <div className="border-t border-dashed border-gray-200 mt-3 pt-3" />
                      <div className="flex gap-2">
                        {record.image_urls!.map((url, imgIndex) => (
                          <button
                            key={imgIndex}
                            type="button"
                            onClick={() => setSelectedImageUrl(url)}
                            className="relative w-24 h-24 rounded-lg overflow-hidden bg-gray-100 cursor-pointer hover:opacity-80 transition-opacity"
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
                    </>
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
