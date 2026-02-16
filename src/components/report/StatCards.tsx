import React from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'

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
      <Card>
        <CardHeader>
          <CardTitle className="text-sm text-gray-600">体重変動</CardTitle>
        </CardHeader>
        <CardContent>
          {latestWeight !== null ? (
            <>
              <div className="text-3xl font-bold text-gray-900">
                {latestWeight.toFixed(1)} kg
              </div>
              {weightChange !== null && (
                <div
                  className={`text-lg font-semibold mt-2 ${
                    weightChange > 0
                      ? 'text-red-500'
                      : weightChange < 0
                      ? 'text-green-500'
                      : 'text-gray-500'
                  }`}
                >
                  {weightChange > 0 ? '+' : ''}
                  {weightChange.toFixed(1)} kg
                </div>
              )}
            </>
          ) : (
            <div className="text-lg text-gray-500">データなし</div>
          )}
        </CardContent>
      </Card>

      {/* カード2: 食事記録 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm text-gray-600">食事記録</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-3xl font-bold text-gray-900">{mealCount} 回</div>
        </CardContent>
      </Card>

      {/* カード3: 運動記録 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm text-gray-600">運動記録</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-3xl font-bold text-gray-900">
            {exerciseCount} 回
          </div>
          <div className="text-sm text-gray-600 mt-2">
            合計 {totalExerciseMinutes} 分
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
