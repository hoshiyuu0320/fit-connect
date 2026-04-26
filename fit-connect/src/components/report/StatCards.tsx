'use client'

import React from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Scale, Utensils, Dumbbell } from 'lucide-react'

interface StatCardsProps {
  weightChange: number | null  // 期間内の体重変動（kg）例: -2.5
  latestWeight: number | null  // 最新体重
  mealCount: number            // 食事記録回数
  exerciseCount: number        // 運動記録回数
  totalExerciseMinutes: number // 運動合計時間（分）
}

export function StatCards({
  weightChange,
  latestWeight,
  mealCount,
  exerciseCount,
  totalExerciseMinutes,
}: StatCardsProps) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
      {/* カード1: 体重変動 */}
      <Card className="border border-[#E2E8F0] rounded-md" style={{ boxShadow: 'none' }}>
        <CardHeader>
          <div className="flex items-center gap-2">
            <Scale className="w-4 h-4 text-[#94A3B8]" />
            <CardTitle className="text-sm text-[#64748B]">体重変動</CardTitle>
          </div>
        </CardHeader>
        <CardContent>
          {latestWeight !== null ? (
            <>
              <div className="text-3xl font-bold text-[#0F172A]">
                {latestWeight.toFixed(1)} kg
              </div>
              {weightChange !== null && (
                <div
                  className={`text-lg font-semibold mt-2 ${
                    weightChange > 0
                      ? 'text-[#DC2626]'
                      : weightChange < 0
                      ? 'text-[#16A34A]'
                      : 'text-[#94A3B8]'
                  }`}
                >
                  {weightChange > 0 ? '+' : ''}
                  {weightChange.toFixed(1)} kg
                </div>
              )}
            </>
          ) : (
            <div className="text-lg text-[#94A3B8]">データなし</div>
          )}
        </CardContent>
      </Card>

      {/* カード2: 食事記録 */}
      <Card className="border border-[#E2E8F0] rounded-md" style={{ boxShadow: 'none' }}>
        <CardHeader>
          <div className="flex items-center gap-2">
            <Utensils className="w-4 h-4 text-[#94A3B8]" />
            <CardTitle className="text-sm text-[#64748B]">食事記録</CardTitle>
          </div>
        </CardHeader>
        <CardContent>
          <div className="text-3xl font-bold text-[#0F172A]">{mealCount} 回</div>
        </CardContent>
      </Card>

      {/* カード3: 運動記録 */}
      <Card className="border border-[#E2E8F0] rounded-md" style={{ boxShadow: 'none' }}>
        <CardHeader>
          <div className="flex items-center gap-2">
            <Dumbbell className="w-4 h-4 text-[#94A3B8]" />
            <CardTitle className="text-sm text-[#64748B]">運動記録</CardTitle>
          </div>
        </CardHeader>
        <CardContent>
          <div className="text-3xl font-bold text-[#0F172A]">
            {exerciseCount} 回
          </div>
          <div className="text-sm text-[#64748B] mt-2">
            合計 {totalExerciseMinutes} 分
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
