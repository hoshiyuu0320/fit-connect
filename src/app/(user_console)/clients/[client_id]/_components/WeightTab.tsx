'use client'

import { WeightChart } from '@/components/clients/WeightChart'
import type { WeightRecord } from '@/types/client'

interface WeightTabProps {
  weightRecords: WeightRecord[]
  targetWeight: number
}

export function WeightTab({ weightRecords, targetWeight }: WeightTabProps) {
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
              // コメント抽出（notes内の数値以外のテキスト）
              const comment = record.notes
                ?.split('\n')
                .filter((line) => isNaN(Number(line.trim())) && line.trim() !== '')
                .join('\n') || null

              return (
                <div
                  key={record.id}
                  className="rounded-xl bg-white shadow-sm border border-gray-100 p-4"
                >
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
                      <span className="text-gray-500 leading-none">💬</span>
                      <p className="text-sm text-gray-700 whitespace-pre-wrap leading-tight">
                        コメント: {comment}
                      </p>
                    </div>
                  )}
                </div>
              )
            })}
        </div>
      </div>
    </div>
  )
}
